import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class WeatherCacheEntry {
  final DateTime fetchedAt;
  final Map<String, dynamic> payload;

  const WeatherCacheEntry({required this.fetchedAt, required this.payload});

  Map<String, dynamic> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'payload': payload,
      };

  static WeatherCacheEntry? fromJson(Map<String, dynamic> json) {
    final fetchedAtRaw = json['fetchedAt'];
    final payloadRaw = json['payload'];
    if (fetchedAtRaw is! String || payloadRaw is! Map) return null;
    final fetchedAt = DateTime.tryParse(fetchedAtRaw);
    if (fetchedAt == null) return null;
    return WeatherCacheEntry(
      fetchedAt: fetchedAt,
      payload: Map<String, dynamic>.from(payloadRaw as Map),
    );
  }
}

class WeatherCache {
  static const _folderName = 'horizon_weather_cache';

  final Duration ttl;

  const WeatherCache({this.ttl = const Duration(minutes: 30)});

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

  Future<WeatherCacheEntry?> read(String key) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final entry = WeatherCacheEntry.fromJson(decoded);
      if (entry == null) return null;
      final age = DateTime.now().difference(entry.fetchedAt);
      if (age > ttl) return null;
      return entry;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_keyToFileName(key)}');
    final entry = WeatherCacheEntry(fetchedAt: DateTime.now(), payload: payload);
    await file.writeAsString(json.encode(entry.toJson()), flush: true);
  }
}
