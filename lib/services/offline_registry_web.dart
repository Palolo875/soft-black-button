import 'dart:convert';

import 'dart:html' as html;

enum OfflinePackType { pmtiles, valhallaTiles, elevation, cache }

class OfflinePack {
  final String id;
  final OfflinePackType type;
  final String? region;
  final String? version;
  final String path;
  final int sizeBytes;
  final String? sha256;
  final DateTime installedAt;
  final DateTime lastUsedAt;

  const OfflinePack({
    required this.id,
    required this.type,
    required this.path,
    required this.sizeBytes,
    required this.installedAt,
    required this.lastUsedAt,
    this.region,
    this.version,
    this.sha256,
  });

  OfflinePack copyWith({
    DateTime? lastUsedAt,
    int? sizeBytes,
    String? sha256,
    String? version,
  }) {
    return OfflinePack(
      id: id,
      type: type,
      region: region,
      version: version ?? this.version,
      path: path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      installedAt: installedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'region': region,
        'version': version,
        'path': path,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'installedAt': installedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  static OfflinePack? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['type'];
    final path = json['path'];
    final sizeBytes = json['sizeBytes'];
    final installedAt = json['installedAt'];
    final lastUsedAt = json['lastUsedAt'];

    if (id is! String || type is! String || path is! String || sizeBytes is! num) return null;
    if (installedAt is! String || lastUsedAt is! String) return null;

    final typeEnum = OfflinePackType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => OfflinePackType.cache,
    );

    final installedDt = DateTime.tryParse(installedAt);
    final lastUsedDt = DateTime.tryParse(lastUsedAt);
    if (installedDt == null || lastUsedDt == null) return null;

    return OfflinePack(
      id: id,
      type: typeEnum,
      region: json['region'] is String ? json['region'] as String : null,
      version: json['version'] is String ? json['version'] as String : null,
      path: path,
      sizeBytes: sizeBytes.toInt(),
      sha256: json['sha256'] is String ? json['sha256'] as String : null,
      installedAt: installedDt,
      lastUsedAt: lastUsedDt,
    );
  }
}

class OfflineRegistry {
  static const _storageKey = 'horizon_offline_registry_v1';

  Future<List<OfflinePack>> listPacks() async {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return const [];
      final packsRaw = decoded['packs'];
      if (packsRaw is! List) return const [];
      final packs = <OfflinePack>[];
      for (final p in packsRaw) {
        if (p is! Map) continue;
        final pack = OfflinePack.fromJson(Map<String, dynamic>.from(p));
        if (pack != null) packs.add(pack);
      }
      return packs;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePacks(List<OfflinePack> packs) async {
    html.window.localStorage[_storageKey] = json.encode({
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'packs': packs.map((p) => p.toJson()).toList(),
    });
  }

  Future<void> upsert(OfflinePack pack) async {
    final packs = (await listPacks()).toList();
    final idx = packs.indexWhere((p) => p.id == pack.id);
    if (idx >= 0) {
      packs[idx] = pack;
    } else {
      packs.add(pack);
    }
    await savePacks(packs);
  }

  Future<void> touch(String id) async {
    final packs = (await listPacks()).toList();
    final idx = packs.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    packs[idx] = packs[idx].copyWith(lastUsedAt: DateTime.now());
    await savePacks(packs);
  }

  Future<void> remove(String id) async {
    final packs = (await listPacks()).toList();
    packs.removeWhere((p) => p.id == id);
    await savePacks(packs);
  }

  Future<void> pruneMissingFiles() async {
  }
}
