import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  final Duration ttl;

  const RouteCache({this.ttl = const Duration(days: 2)});

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
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
    await file.writeAsString(json.encode(entry.toJson()), flush: true);
  }
}
