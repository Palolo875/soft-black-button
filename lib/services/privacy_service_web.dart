import 'package:app/services/secure_file_store.dart';

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

  Future<LocalDataReport> computeReport() async {
    final secureBytes = await const SecureFileStore().approxSizeBytes();
    return LocalDataReport(
      secureStoreBytes: secureBytes,
      routeCacheBytes: 0,
      weatherCacheBytes: 0,
      offlinePacksBytes: 0,
    );
  }

  Future<void> panicWipeAllLocalData() async {
    await const SecureFileStore().panicWipe();
  }
}
