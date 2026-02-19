import 'package:horizon/services/secure_file_store.dart';
import 'package:horizon/core/log/app_log.dart';

class RouteCacheEntry {
  final DateTime savedAt;
  final Map<String, dynamic> payload;

  const RouteCacheEntry({required this.savedAt, required this.payload});

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'payload': payload,
      };

  static RouteCacheEntry? fromJson(Map<String, dynamic> json) {
    final savedAtRaw = json['savedAt'];
    final payloadRaw = json['payload'];
    if (savedAtRaw is! String || payloadRaw is! Map) return null;
    final savedAt = DateTime.tryParse(savedAtRaw);
    if (savedAt == null) return null;
    return RouteCacheEntry(
      savedAt: savedAt,
      payload: Map<String, dynamic>.from(payloadRaw as Map),
    );
  }
}

class RouteCache {
  static const _secureEntryPrefix = 'route_cache_';
  static const _secureIndexKey = 'route_cache_index_v1';

  final Duration ttl;
  final bool encrypted;
  final int maxEntries;
  final SecureFileStore _store;

  RouteCache({
    this.ttl = const Duration(days: 2),
    this.encrypted = false,
    this.maxEntries = 64,
    SecureFileStore? secureStore,
  }) : _store = secureStore ?? SecureFileStore();

  Future<Map<String, dynamic>> _loadIndex() async {
    final raw = await _store.readJsonDecrypted(_secureIndexKey);
    if (raw == null) return <String, dynamic>{'items': <String, dynamic>{}};
    final items = raw['items'];
    if (items is! Map) return <String, dynamic>{'items': <String, dynamic>{}};
    return <String, dynamic>{'items': Map<String, dynamic>.from(items)};
  }

  Future<void> _saveIndex(Map<String, dynamic> index) async {
    await _store.writeJsonEncrypted(_secureIndexKey, index);
  }

  Future<void> _touchIndex(String key, {DateTime? savedAt}) async {
    final index = await _loadIndex();
    final items = Map<String, dynamic>.from(index['items'] as Map);
    final now = DateTime.now().toUtc().toIso8601String();
    final prev = items[key];
    if (prev is Map) {
      final m = Map<String, dynamic>.from(prev);
      m['lastAccess'] = now;
      if (savedAt != null) m['savedAt'] = savedAt.toUtc().toIso8601String();
      items[key] = m;
    } else {
      items[key] = {
        'lastAccess': now,
        if (savedAt != null) 'savedAt': savedAt.toUtc().toIso8601String(),
      };
    }
    index['items'] = items;
    await _saveIndex(index);
  }

  Future<void> _removeFromIndex(String key) async {
    final index = await _loadIndex();
    final items = Map<String, dynamic>.from(index['items'] as Map);
    if (!items.containsKey(key)) return;
    items.remove(key);
    index['items'] = items;
    await _saveIndex(index);
  }

  Future<void> prune() async {
    final index = await _loadIndex();
    final items = Map<String, dynamic>.from(index['items'] as Map);
    if (items.isEmpty) return;

    final now = DateTime.now().toUtc();
    final toDelete = <String>[];

    for (final entry in items.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final savedAtRaw = v['savedAt'];
      if (savedAtRaw is String) {
        final savedAt = DateTime.tryParse(savedAtRaw);
        if (savedAt != null && now.difference(savedAt) > ttl) {
          toDelete.add(entry.key);
        }
      }
    }

    int deleted = 0;
    for (final k in toDelete) {
      await delete(k);
      items.remove(k);
      deleted++;
    }

    if (items.length > maxEntries) {
      final sortable = <(String, DateTime)>[];
      for (final entry in items.entries) {
        final v = entry.value;
        DateTime t = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (v is Map) {
          final la = v['lastAccess'];
          if (la is String) {
            final parsed = DateTime.tryParse(la);
            if (parsed != null) t = parsed.toUtc();
          }
        }
        sortable.add((entry.key, t));
      }
      sortable.sort((a, b) => a.$2.compareTo(b.$2));
      final overflow = sortable.length - maxEntries;
      for (int i = 0; i < overflow; i++) {
        final k = sortable[i].$1;
        await delete(k);
        items.remove(k);
        deleted++;
      }
    }

    index['items'] = items;
    await _saveIndex(index);
  }

  Future<RouteCacheEntry?> read(String key) async {
    final payload = await _store.readJsonDecrypted('$_secureEntryPrefix$key');
    if (payload == null) return null;
    final entry = RouteCacheEntry.fromJson(payload);
    if (entry == null) return null;
    final age = DateTime.now().difference(entry.savedAt);
    if (age > ttl) {
      await delete(key);
      return null;
    }
    await _touchIndex(key);
    return entry;
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
    await _store.writeJsonEncrypted('$_secureEntryPrefix$key', entry.toJson());
    await _touchIndex(key, savedAt: entry.savedAt);
    await prune();
  }

  Future<void> delete(String key) async {
    await _store.delete('$_secureEntryPrefix$key');
    await _removeFromIndex(key);
  }
}
