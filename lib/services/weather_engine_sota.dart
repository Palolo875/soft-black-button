import 'dart:math';

import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/services/metno_adapter.dart';
import 'package:horizon/services/open_meteo_adapter.dart';
import 'package:horizon/services/comfort_model.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:horizon/services/comfort_profile_store.dart';
import 'package:horizon/services/weather_cache.dart';
import 'package:horizon/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

Map<String, dynamic> mapMetNoToOpenMeteoShape(Map<String, dynamic> met) {
  final props = met['properties'];
  if (props is! Map) throw Exception('Met.no: missing properties');
  final timeseries = props['timeseries'];
  if (timeseries is! List) throw Exception('Met.no: missing timeseries');

  final time = <String>[];
  final temperature = <double>[];
  final apparent = <double>[];
  final precipitation = <double>[];
  final humidity = <double>[];
  final cloud = <double>[];
  final pressure = <double>[];
  final windSpeed = <double>[];
  final windDir = <double>[];

  for (final item in timeseries.take(72)) {
    if (item is! Map) continue;
    final t = item['time'];
    final data = item['data'];
    if (t is! String || data is! Map) continue;
    final instant = data['instant'];
    final next1h = data['next_1_hours'];
    if (instant is! Map) continue;
    final details = instant['details'];
    if (details is! Map) continue;

    double numVal(dynamic v, [double fallback = double.nan]) => (v is num) ? v.toDouble() : fallback;

    time.add(t);
    final temp = numVal(details['air_temperature']);
    temperature.add(temp);
    apparent.add(temp);
    windSpeed.add(numVal(details['wind_speed']));
    windDir.add(numVal(details['wind_from_direction']));
    humidity.add(numVal(details['relative_humidity']));
    cloud.add(numVal(details['cloud_area_fraction']));
    pressure.add(numVal(details['air_pressure_at_sea_level']));

    double p1h = 0.0;
    if (next1h is Map) {
      final pDetails = next1h['details'];
      if (pDetails is Map) {
        p1h = numVal(pDetails['precipitation_amount'], 0.0);
      }
    }
    precipitation.add(p1h);
  }

  return {
    'hourly': {
      'time': time,
      'temperature_2m': temperature,
      'apparent_temperature': apparent,
      'precipitation': precipitation,
      'relativehumidity_2m': humidity,
      'cloudcover': cloud,
      'pressure_msl': pressure,
      'windspeed_10m': windSpeed,
      'winddirection_10m': windDir,
    },
  };
}

class WeatherEngineSota {
  final OpenMeteoAdapter _openMeteo;
  final MetNoAdapter _metNo;
  final WeatherCache _cache;
  final String _metNoUserAgent;
  final ComfortProfileStore _profileStore;
  final ComfortModel _comfortModel;
  Future<ComfortProfile>? _profileFuture;

  WeatherEngineSota({
    OpenMeteoAdapter? openMeteo,
    MetNoAdapter? metNo,
    WeatherCache? cache,
    ComfortProfileStore? profileStore,
    ComfortModel comfortModel = const ComfortModel(),
    String metNoUserAgent = const String.fromEnvironment(
      'METNO_USER_AGENT',
      defaultValue: 'HORIZON/1.0 (+https://example.com/contact)',
    ),
  })  : _openMeteo = openMeteo ?? OpenMeteoAdapter(),
        _metNo = metNo ?? MetNoAdapter(),
        _cache = cache ?? WeatherCache(encrypted: true),
        _profileStore = profileStore ?? ComfortProfileStore(),
        _comfortModel = comfortModel,
        _metNoUserAgent = metNoUserAgent;

  Future<ComfortProfile> _profile() {
    return _profileFuture ??= _profileStore.load();
  }

  static String cacheKeyFor(LatLng p) {
    double round(double v) => (v * HorizonConstants.cacheGridFactor).roundToDouble() / HorizonConstants.cacheGridFactor;
    return 'v2_${round(p.latitude)}_${round(p.longitude)}';
  }

  Future<void> prefetchForecast(LatLng point) async {
    final key = cacheKeyFor(point);
    final cached = await _cache.read(key);
    if (cached != null) return;
    final payload = await _fetchWithFallback(point);
    await _cache.write(key, payload);
  }

  Future<void> prefetchForecasts(List<LatLng> points, {int maxConcurrent = 6}) async {
    if (points.isEmpty) return;
    final unique = <String, LatLng>{};
    for (final p in points) {
      unique[cacheKeyFor(p)] = p;
    }
    final list = unique.values.toList();

    assert(() {
      AppLog.d('weatherEngine.prefetchForecasts', props: {'points': points.length, 'unique': list.length});
      return true;
    }());

    for (int i = 0; i < list.length; i += maxConcurrent) {
      final chunk = list.sublist(i, (i + maxConcurrent) > list.length ? list.length : (i + maxConcurrent));
      await Future.wait(chunk.map(prefetchForecast));
    }
  }

  Future<WeatherDecision> getDecisionForPoint(
    LatLng point, {
    double? userHeadingDegrees,
    ComfortProfile? comfortProfile,
  }) async {
    return getDecisionForPointAtTime(
      point,
      at: DateTime.now().toUtc(),
      userHeadingDegrees: userHeadingDegrees,
      comfortProfile: comfortProfile,
    );
  }

  Future<WeatherDecision> getDecisionForPointAtTime(
    LatLng point, {
    required DateTime at,
    double? userHeadingDegrees,
    ComfortProfile? comfortProfile,
  }) async {
    final key = cacheKeyFor(point);

    Map<String, dynamic> payload;
    final cached = await _cache.read(key);
    if (cached != null) {
      payload = cached.payload;
    } else {
      payload = await _fetchWithFallback(point);
      await _cache.write(key, payload);
    }

    final weatherPoint = _normalize(point, payload);
    final snap = _pickNearest(weatherPoint, at.toUtc());
    final profile = comfortProfile ?? await _profile();
    final breakdown = _comfortModel.compute(
      s: snap,
      userHeadingDegrees: userHeadingDegrees,
      profile: profile,
      atUtc: at.toUtc(),
    );
    final confidence = _confidenceHeuristic(weatherPoint);

    return WeatherDecision(
      now: snap,
      comfortScore: breakdown.score,
      confidence: confidence,
      comfortBreakdown: breakdown,
    );
  }

  Future<Map<String, dynamic>> _fetchWithFallback(LatLng p) async {
    try {
      return await _openMeteo.fetchForecast(
        latitude: p.latitude,
        longitude: p.longitude,
        forecastDays: 3,
      );
    } catch (e, st) {
      AppLog.w('weatherEngine.openMeteo failed, falling back to met.no', error: e, stackTrace: st);
      // Met.no requires a descriptive User-Agent with contact info.
      final metPayload = await _metNo.fetchCompact(
        latitude: p.latitude,
        longitude: p.longitude,
        userAgent: _metNoUserAgent,
      );
      return mapMetNoToOpenMeteoShape(metPayload);
    }
  }

  WeatherPoint _normalize(LatLng point, Map<String, dynamic> payload) {
    final hourly = payload['hourly'];
    if (hourly is! Map) {
      throw Exception('Weather: missing hourly');
    }

    final time = (hourly['time'] as List?)?.cast<String>() ?? const <String>[];
    List<double> listD(String key) {
      final raw = hourly[key];
      if (raw is! List) return List<double>.filled(time.length, double.nan);
      return raw.map((e) => (e is num) ? e.toDouble() : double.nan).toList();
    }

    final temperature = listD('temperature_2m');
    final apparent = listD('apparent_temperature');
    final precipitation = listD('precipitation');
    final humidity = listD('relativehumidity_2m');
    final cloud = listD('cloudcover');
    final pressure = listD('pressure_msl');
    final windSpeed = listD('windspeed_10m');
    final windDir = listD('winddirection_10m');

    final timeline = <WeatherSnapshot>[];
    for (int i = 0; i < time.length; i++) {
      final ts = DateTime.tryParse(time[i]);
      if (ts == null) continue;
      timeline.add(
        WeatherSnapshot(
          timestamp: ts.toUtc(),
          temperature: temperature.elementAtOrNull(i) ?? double.nan,
          apparentTemperature: apparent.elementAtOrNull(i) ?? double.nan,
          windSpeed: windSpeed.elementAtOrNull(i) ?? double.nan,
          windDirection: windDir.elementAtOrNull(i) ?? double.nan,
          precipitation: precipitation.elementAtOrNull(i) ?? 0.0,
          humidity: humidity.elementAtOrNull(i) ?? double.nan,
          cloudCover: cloud.elementAtOrNull(i) ?? double.nan,
          pressure: pressure.elementAtOrNull(i) ?? double.nan,
        ),
      );
    }

    return WeatherPoint(location: point, timeline: timeline);
  }

  WeatherSnapshot _pickNearest(WeatherPoint point, DateTime atUtc) {
    if (point.timeline.isEmpty) {
      throw Exception('Weather: empty timeline');
    }
    WeatherSnapshot best = point.timeline.first;
    var bestDelta = (best.timestamp.difference(atUtc)).abs();
    for (final s in point.timeline) {
      final d = (s.timestamp.difference(atUtc)).abs();
      if (d < bestDelta) {
        best = s;
        bestDelta = d;
      }
    }
    return best;
  }

  double _confidenceHeuristic(WeatherPoint p) {
    if (p.timeline.length < 3) return HorizonConstants.confidenceHeuristicFallback;
    final now = _pickNearest(p, DateTime.now().toUtc());
    final idx = p.timeline.indexOf(now);
    if (idx < 0) return HorizonConstants.confidenceHeuristicFallback;

    final next1 = p.timeline.elementAtOrNull(idx + 1);
    final next2 = p.timeline.elementAtOrNull(idx + 2);

    double score = HorizonConstants.confidenceHeuristicBase;

    double delta(double a, double b) => (a - b).abs();

    if (next1 != null) {
      score -= min(0.25, delta(now.precipitation, next1.precipitation) / 3.0);
      score -= min(0.15, delta(now.windSpeed, next1.windSpeed) / 20.0);
    }
    if (next2 != null) {
      score -= min(0.20, delta(now.precipitation, next2.precipitation) / 4.0);
    }

    if (now.precipitation >= HorizonConstants.confidenceHeuristicRainHeavy) score -= 0.2;
    if (now.precipitation >= HorizonConstants.confidenceHeuristicRainExtreme) score -= 0.2;

    return score.clamp(0.25, 0.95);
  }
}

