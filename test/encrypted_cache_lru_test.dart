import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/route_cache.dart';
import 'package:horizon/services/weather_cache.dart';
import 'package:horizon/services/secure_file_store.dart';

class _FakeSecureFileStore extends SecureFileStore {
  final Map<String, Map<String, dynamic>> mem = {};

  _FakeSecureFileStore();

  @override
  Future<void> writeJsonEncrypted(String name, Map<String, dynamic> jsonMap) async {
    mem[name] = Map<String, dynamic>.from(jsonMap);
  }

  @override
  Future<Map<String, dynamic>?> readJsonDecrypted(String name) async {
    final v = mem[name];
    if (v == null) return null;
    return Map<String, dynamic>.from(v);
  }

  @override
  Future<void> delete(String name) async {
    mem.remove(name);
  }
}

void main() {
  test('WeatherCache(encrypted) prunes to maxEntries using index', () async {
    final store = _FakeSecureFileStore();
    final cache = WeatherCache(encrypted: true, maxEntries: 2, secureStore: store);

    await cache.write('a', const {'x': 1});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.write('b', const {'x': 2});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.write('c', const {'x': 3});

    final a = await cache.read('a');
    final b = await cache.read('b');
    final c = await cache.read('c');

    expect(a, isNull);
    expect(b, isNotNull);
    expect(c, isNotNull);
  });

  test('RouteCache(encrypted) prunes to maxEntries using index', () async {
    final store = _FakeSecureFileStore();
    final cache = RouteCache(encrypted: true, maxEntries: 2, secureStore: store);

    await cache.write('a', const {'x': 1});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.write('b', const {'x': 2});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await cache.write('c', const {'x': 3});

    final a = await cache.read('a');
    final b = await cache.read('b');
    final c = await cache.read('c');

    expect(a, isNull);
    expect(b, isNotNull);
    expect(c, isNotNull);
  });
}
