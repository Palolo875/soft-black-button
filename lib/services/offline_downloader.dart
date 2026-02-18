import 'dart:io';

import 'package:horizon/services/offline_integrity.dart';
import 'package:http/http.dart' as http;
import 'package:horizon/services/secure_http_client.dart';
import 'package:horizon/core/log/app_log.dart';

class OfflineDownloader {
  final OfflineIntegrity _integrity;
  final SecureHttpClient _http;

  OfflineDownloader({
    OfflineIntegrity integrity = const OfflineIntegrity(),
    SecureHttpClient? httpClient,
  })  : _integrity = integrity,
        _http = httpClient ?? SecureHttpClient();

  Future<File> downloadAtomic({
    required Uri url,
    required File destination,
    String? expectedSha256,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final tmp = File('${destination.path}.tmp');
    final bak = File('${destination.path}.bak');
    if (await tmp.exists()) {
      await tmp.delete();
    }

    final req = http.Request('GET', url);
    final resp = await _http.send(req);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final total = resp.contentLength;
    int received = 0;

    final sink = tmp.openWrite();
    try {
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      await _integrity.verifySha256(file: tmp, expectedHex: expectedSha256);
    }

    // Rollback-safe swap: keep previous as .bak until new file is in place.
    if (await bak.exists()) {
      await bak.delete();
    }
    if (await destination.exists()) {
      await destination.rename(bak.path);
    }

    try {
      await tmp.rename(destination.path);
      if (await bak.exists()) {
        await bak.delete();
      }
    } catch (e, st) {
      assert(() {
        AppLog.w('offlineDownloader.atomicSwap failed', error: e, stackTrace: st, props: {
          'url': url.toString(),
          'destination': destination.path,
        });
        return true;
      }());
      // Restore previous version if possible.
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
        if (await bak.exists()) {
          await bak.rename(destination.path);
        }
      } catch (err, st) {
        AppLog.w('offlineDownloader.rollback failed', error: err, stackTrace: st, props: {'path': destination.path});
      }
      rethrow;
    }
    return destination;
  }
}
