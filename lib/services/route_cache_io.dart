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

  final Duration ttl;
  final bool encrypted;
  final SecureFileStore _secureStore;

  RouteCache({
    this.ttl = const Duration(days: 2),
    this.encrypted = false,
    SecureFileStore secureStore = const SecureFileStore(),
  }) : _secureStore = secureStore;

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
      if (age > ttl) return null;
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
      if (age > ttl) return null;
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
      return;
    }
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
    await file.writeAsString(json.encode(entry.toJson()), flush: true);
  }
}
