import 'package:app/services/secure_file_store.dart';

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
  static const _secureEntryPrefix = 'weather_cache_';

  final Duration ttl;
  final bool encrypted;
  final SecureFileStore _store;

  WeatherCache({
    this.ttl = const Duration(minutes: 30),
    this.encrypted = false,
    SecureFileStore secureStore = const SecureFileStore(),
  }) : _store = secureStore;

  Future<WeatherCacheEntry?> read(String key) async {
    final payload = await _store.readJsonDecrypted('$_secureEntryPrefix$key');
    if (payload == null) return null;
    final entry = WeatherCacheEntry.fromJson(payload);
    if (entry == null) return null;
    final age = DateTime.now().difference(entry.fetchedAt);
    if (age > ttl) return null;
    return entry;
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final entry = WeatherCacheEntry(fetchedAt: DateTime.now(), payload: payload);
    await _store.writeJsonEncrypted('$_secureEntryPrefix$key', entry.toJson());
  }
}
