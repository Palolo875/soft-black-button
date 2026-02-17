import 'dart:io';

import 'package:app/services/offline_downloader.dart';
import 'package:app/services/offline_integrity.dart';
import 'package:app/services/offline_lru.dart';
import 'package:app/services/offline_registry.dart';

class OfflineCore {
  final OfflineRegistry registry;
  final OfflineDownloader downloader;
  final OfflineIntegrity integrity;
  final OfflineLru lru;

  OfflineCore({
    OfflineRegistry? registry,
    OfflineDownloader? downloader,
    OfflineIntegrity? integrity,
    OfflineLru? lru,
  })  : registry = registry ?? OfflineRegistry(),
        downloader = downloader ?? OfflineDownloader(),
        integrity = integrity ?? const OfflineIntegrity(),
        lru = lru ?? const OfflineLru();

  Future<File> installFilePack({
    required String id,
    required OfflinePackType type,
    required Uri url,
    required String fileName,
    String? expectedSha256,
    String? region,
    String? version,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final root = await registry.rootDir();
    final dest = File('${root.path}/$fileName');

    await downloader.downloadAtomic(
      url: url,
      destination: dest,
      expectedSha256: expectedSha256,
      onProgress: onProgress,
    );

    final size = await dest.length();
    final sha = expectedSha256 ?? await integrity.sha256OfFile(dest);
    final now = DateTime.now();

    await registry.upsert(
      OfflinePack(
        id: id,
        type: type,
        region: region,
        version: version,
        path: dest.path,
        sizeBytes: size,
        sha256: sha,
        installedAt: now,
        lastUsedAt: now,
      ),
    );

    await lru.enforce(registry: registry, protectedPackIds: {id});

    return dest;
  }

  Future<void> uninstallPackById(String id) async {
    final packs = await registry.listPacks();
    final pack = packs.where((p) => p.id == id).firstOrNull;
    if (pack == null) return;

    try {
      final file = File(pack.path);
      if (await file.exists()) {
        await file.delete();
      } else {
        final dir = Directory(pack.path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {}

    await registry.remove(id);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
