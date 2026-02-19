import 'dart:io';

import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/services/offline_registry.dart';
import 'package:horizon/services/secure_file_store.dart';
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
    await const SecureFileStore().panicWipe();

    final docs = await getApplicationDocumentsDirectory();
    final routeDir = Directory('${docs.path}/$_routeCacheFolder');
    final weatherDir = Directory('${docs.path}/$_weatherCacheFolder');

    await _deleteDirIfExists(routeDir);
    await _deleteDirIfExists(weatherDir);

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
        } catch (err, st) {
          AppLog.w('privacy.dirSize file.length failed', error: err, stackTrace: st, props: {'path': e.path});
        }
      }
    }
    return total;
  }

  Future<void> _deleteDirIfExists(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      AppLog.w('privacy.deleteDir failed', error: e, stackTrace: st, props: {'path': dir.path});
    }
  }
}
