import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/open_meteo_adapter.dart';
import 'package:horizon/services/weather_cache.dart';
import 'package:horizon/services/weather_engine_sota.dart';
import 'package:horizon/services/weather_cache_io.dart' show WeatherCacheEntry;
import 'package:maplibre_gl/maplibre_gl.dart';

class _MemWeatherCache extends WeatherCache {
  final Map<String, WeatherCacheEntry> mem = {};

  _MemWeatherCache() : super(encrypted: true);

  @override
  Future<WeatherCacheEntry?> read(String key) async {
    return mem[key];
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    mem[key] = WeatherCacheEntry(fetchedAt: DateTime.now().toUtc(), payload: payload);
  }
}

class _FakeOpenMeteoAdapter extends OpenMeteoAdapter {
  int calls = 0;

  _FakeOpenMeteoAdapter();

  @override
  Future<Map<String, dynamic>> fetchForecast({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
    String? models,
  }) async {
    calls++;
    return {
      'hourly': {
        'time': <String>[],
      },
    };
  }
}

void main() {
  test('prefetchForecasts deduplicates points by cache key', () async {
    final cache = _MemWeatherCache();
    final open = _FakeOpenMeteoAdapter();

    final engine = WeatherEngineSota(
      openMeteo: open,
      cache: cache,
    );

    const p1 = LatLng(10.00001, 20.00001);
    const p2 = LatLng(10.00002, 20.00002);
    const p3 = LatLng(10.9, 20.9);

    await engine.prefetchForecasts([p1, p2, p3, p1], maxConcurrent: 2);

    final k1 = WeatherEngineSota.cacheKeyFor(p1);
    final k2 = WeatherEngineSota.cacheKeyFor(p2);
    final k3 = WeatherEngineSota.cacheKeyFor(p3);

    final uniqueKeys = {k1, k2, k3};
    expect(open.calls, uniqueKeys.length);
    for (final k in uniqueKeys) {
      expect(cache.mem.containsKey(k), isTrue);
    }
  });

  test('prefetchForecasts skips already cached keys', () async {
    final cache = _MemWeatherCache();
    final open = _FakeOpenMeteoAdapter();

    final engine = WeatherEngineSota(
      openMeteo: open,
      cache: cache,
    );

    const p = LatLng(10.1, 20.1);
    await engine.prefetchForecast(p);
    expect(open.calls, 1);

    await engine.prefetchForecast(p);
    expect(open.calls, 1);
  });
}
