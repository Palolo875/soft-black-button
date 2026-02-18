import 'dart:io';

import 'package:app/core/log/app_log.dart';
import 'package:app/services/offline_registry.dart';

class OfflineLru {
  final int maxBytes;

  const OfflineLru({this.maxBytes = 1500 * 1024 * 1024});

  Future<void> enforce({
    required OfflineRegistry registry,
    Set<String> protectedPackIds = const {},
  }) async {
    final packs = (await registry.listPacks()).toList();
    packs.sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));

    int total = packs.fold(0, (sum, p) => sum + p.sizeBytes);
    if (total <= maxBytes) return;

    for (final p in packs) {
      if (protectedPackIds.contains(p.id)) continue;
      try {
        final file = File(p.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, st) {
        AppLog.w('offlineLru.delete failed', error: e, stackTrace: st, props: {'id': p.id, 'path': p.path});
      }

      total -= p.sizeBytes;
      final remaining = packs.where((x) => x.id != p.id).toList();
      await registry.savePacks(remaining);

      if (total <= maxBytes) return;
    }
  }
}
