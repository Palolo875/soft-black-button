import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
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
  static const _folderName = 'horizon_route_cache';
  static const _secureEntryPrefix = 'route_cache_';
  static const _secureIndexKey = 'route_cache_index_v1';

  final Duration ttl;
  final bool encrypted;
  final int maxEntries;
  final SecureFileStore _secureStore;

  RouteCache({
    this.ttl = const Duration(days: 2),
    this.encrypted = false,
    this.maxEntries = 64,
    SecureFileStore secureStore = const SecureFileStore(),
  }) : _secureStore = secureStore;

  Future<Map<String, dynamic>> _loadIndex() async {
    final raw = await _secureStore.readJsonDecrypted(_secureIndexKey);
    if (raw == null) return <String, dynamic>{'items': <String, dynamic>{}};
    final items = raw['items'];
    if (items is! Map) return <String, dynamic>{'items': <String, dynamic>{}};
    return <String, dynamic>{'items': Map<String, dynamic>.from(items)};
  }

  Future<void> _saveIndex(Map<String, dynamic> index) async {
    await _secureStore.writeJsonEncrypted(_secureIndexKey, index);
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

    if (deleted > 0) {
      AppLog.d('routeCache.prune', props: {'deleted': deleted, 'remaining': items.length, 'encrypted': encrypted});
    }
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

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _keyToFileName(String key) {
    final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '$safe.json';
  }

  Future<RouteCacheEntry?> read(String key) async {
    if (encrypted) {
      final payload = await _secureStore.readJsonDecrypted('$_secureEntryPrefix$key');
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
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final entry = RouteCacheEntry.fromJson(decoded);
      if (entry == null) return null;
      final age = DateTime.now().difference(entry.savedAt);
      if (age > ttl) {
        await delete(key);
        return null;
      }
      await _touchIndex(key);
      return entry;
    } catch (e, st) {
      AppLog.w('routeCache.read failed', error: e, stackTrace: st, props: {'key': key, 'encrypted': false});
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    if (encrypted) {
      final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
      await _secureStore.writeJsonEncrypted('$_secureEntryPrefix$key', entry.toJson());
      await _touchIndex(key, savedAt: entry.savedAt);
      await prune();
      return;
    }
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
    await file.writeAsString(json.encode(entry.toJson()), flush: true);
    await _touchIndex(key, savedAt: entry.savedAt);
    await prune();
  }

  Future<void> delete(String key) async {
    if (encrypted) {
      await _secureStore.delete('$_secureEntryPrefix$key');
      await _removeFromIndex(key);
      return;
    }
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    if (await file.exists()) {
      await file.delete();
    }
    await _removeFromIndex(key);
  }
}
