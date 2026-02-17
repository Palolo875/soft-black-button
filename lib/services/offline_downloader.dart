import 'dart:io';

import 'package:app/services/offline_integrity.dart';
import 'package:http/http.dart' as http;

class OfflineDownloader {
  final OfflineIntegrity _integrity;

  const OfflineDownloader({OfflineIntegrity integrity = const OfflineIntegrity()}) : _integrity = integrity;

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
    final resp = await req.send();
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
    } catch (e) {
      // Restore previous version if possible.
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
        if (await bak.exists()) {
          await bak.rename(destination.path);
        }
      } catch (_) {}
      rethrow;
    }
    return destination;
  }
}
