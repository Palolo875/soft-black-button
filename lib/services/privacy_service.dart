import 'dart:io';

import 'package:app/services/offline_registry.dart';
import 'package:app/services/secure_file_store.dart';
import 'package:path_provider/path_provider.dart';

class LocalDataReport {
  final int secureStoreBytes;
  final int routeCacheBytes;
  final int weatherCacheBytes;
  final int offlinePacksBytes;

  const LocalDataReport({
    required this.secureStoreBytes,
    required this.routeCacheBytes,
    required this.weatherCacheBytes,
    required this.offlinePacksBytes,
  });

  int get totalBytes => secureStoreBytes + routeCacheBytes + weatherCacheBytes + offlinePacksBytes;
}

class PrivacyService {
  const PrivacyService();

  static const _routeCacheFolder = 'horizon_route_cache';
  static const _weatherCacheFolder = 'horizon_weather_cache';

  Future<LocalDataReport> computeReport() async {
    final docs = await getApplicationDocumentsDirectory();

    final secureBytes = await const SecureFileStore().approxSizeBytes();

    final routeDir = Directory('${docs.path}/$_routeCacheFolder');
    final weatherDir = Directory('${docs.path}/$_weatherCacheFolder');

    final routeBytes = await _dirSize(routeDir);
    final weatherBytes = await _dirSize(weatherDir);

    final offlineRoot = await OfflineRegistry().rootDir();
    final offlineBytes = await _dirSize(offlineRoot);

    return LocalDataReport(
      secureStoreBytes: secureBytes,
      routeCacheBytes: routeBytes,
      weatherCacheBytes: weatherBytes,
      offlinePacksBytes: offlineBytes,
    );
  }

  Future<void> panicWipeAllLocalData() async {
    // 1) Encrypted store + secure keys.
    await const SecureFileStore().panicWipe();

    // 2) Plaintext caches (legacy).
    final docs = await getApplicationDocumentsDirectory();
    final routeDir = Directory('${docs.path}/$_routeCacheFolder');
    final weatherDir = Directory('${docs.path}/$_weatherCacheFolder');

    await _deleteDirIfExists(routeDir);
    await _deleteDirIfExists(weatherDir);

    // 3) Offline packs registry + downloaded content.
    final offlineRoot = await OfflineRegistry().rootDir();
    await _deleteDirIfExists(offlineRoot);
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _deleteDirIfExists(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort.
    }
  }
}
