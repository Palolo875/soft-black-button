import 'package:app/services/secure_file_store.dart';

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

  final Duration ttl;
  final bool encrypted;
  final SecureFileStore _store;

  RouteCache({
    this.ttl = const Duration(days: 2),
    this.encrypted = false,
    SecureFileStore secureStore = const SecureFileStore(),
  }) : _store = secureStore;

  Future<RouteCacheEntry?> read(String key) async {
    final payload = await _store.readJsonDecrypted('$_secureEntryPrefix$key');
    if (payload == null) return null;
    final entry = RouteCacheEntry.fromJson(payload);
    if (entry == null) return null;
    final age = DateTime.now().difference(entry.savedAt);
    if (age > ttl) return null;
    return entry;
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final entry = RouteCacheEntry(savedAt: DateTime.now(), payload: payload);
    await _store.writeJsonEncrypted('$_secureEntryPrefix$key', entry.toJson());
  }
}
