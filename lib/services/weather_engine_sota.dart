import 'dart:math';

import 'package:app/services/metno_adapter.dart';
import 'package:app/services/open_meteo_adapter.dart';
import 'package:app/services/weather_cache.dart';
import 'package:app/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class WeatherEngineSota {
  final OpenMeteoAdapter _openMeteo;
  final MetNoAdapter _metNo;
  final WeatherCache _cache;
  final String _metNoUserAgent;

  const WeatherEngineSota({
    OpenMeteoAdapter openMeteo = const OpenMeteoAdapter(),
    MetNoAdapter metNo = const MetNoAdapter(),
    WeatherCache cache = const WeatherCache(),
    String metNoUserAgent = const String.fromEnvironment(
      'METNO_USER_AGENT',
      defaultValue: 'HORIZON/1.0 (+https://example.com/contact)',
    ),
  })  : _openMeteo = openMeteo,
        _metNo = metNo,
        _cache = cache,
        _metNoUserAgent = metNoUserAgent;

  static String cacheKeyFor(LatLng p) {
    double round(double v) => (v * 50).roundToDouble() / 50;
    return 'v2_${round(p.latitude)}_${round(p.longitude)}';
  }

  Future<WeatherDecision> getDecisionForPoint(
    LatLng point, {
    double? userHeadingDegrees,
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
    final now = _pickNow(weatherPoint);
    final comfort = _comfortBike(now, userHeadingDegrees: userHeadingDegrees);
    final confidence = _confidenceHeuristic(weatherPoint);

    return WeatherDecision(now: now, comfortScore: comfort, confidence: confidence);
  }

  Future<Map<String, dynamic>> _fetchWithFallback(LatLng p) async {
    try {
      return await _openMeteo.fetchForecast(
        latitude: p.latitude,
        longitude: p.longitude,
        forecastDays: 3,
      );
    } catch (_) {
      // Met.no requires a descriptive User-Agent with contact info.
      final metPayload = await _metNo.fetchCompact(
        latitude: p.latitude,
        longitude: p.longitude,
        userAgent: _metNoUserAgent,
      );
      return _mapMetNoToOpenMeteoShape(metPayload);
    }
  }

  // Convert Met.no compact response into a subset shaped like Open-Meteo hourly.
  Map<String, dynamic> _mapMetNoToOpenMeteoShape(Map<String, dynamic> met) {
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

  WeatherSnapshot _pickNow(WeatherPoint point) {
    if (point.timeline.isEmpty) {
      throw Exception('Weather: empty timeline');
    }
    final now = DateTime.now().toUtc();
    WeatherSnapshot best = point.timeline.first;
    var bestDelta = (best.timestamp.difference(now)).abs();
    for (final s in point.timeline) {
      final d = (s.timestamp.difference(now)).abs();
      if (d < bestDelta) {
        best = s;
        bestDelta = d;
      }
    }
    return best;
  }

  double _confidenceHeuristic(WeatherPoint p) {
    if (p.timeline.length < 3) return 0.6;
    final now = _pickNow(p);
    final idx = p.timeline.indexOf(now);
    if (idx < 0) return 0.6;

    final next1 = p.timeline.elementAtOrNull(idx + 1);
    final next2 = p.timeline.elementAtOrNull(idx + 2);

    double score = 0.85;

    double delta(double a, double b) => (a - b).abs();

    if (next1 != null) {
      score -= min(0.25, delta(now.precipitation, next1.precipitation) / 3.0);
      score -= min(0.15, delta(now.windSpeed, next1.windSpeed) / 20.0);
    }
    if (next2 != null) {
      score -= min(0.20, delta(now.precipitation, next2.precipitation) / 4.0);
    }

    if (now.precipitation >= 2.0) score -= 0.2;
    if (now.precipitation >= 5.0) score -= 0.2;

    return score.clamp(0.25, 0.95);
  }

  double _comfortBike(
    WeatherSnapshot s, {
    double? userHeadingDegrees,
  }) {
    double penalty = 0.0;

    final r = s.precipitation;
    if (r <= 0.1) {
      penalty += 0.0;
    } else if (r <= 0.5) {
      penalty += 1.5;
    } else if (r <= 1.5) {
      penalty += 3.5;
    } else if (r <= 4.0) {
      penalty += 6.0;
    } else {
      penalty += 8.0;
    }

    final t = s.apparentTemperature.isFinite ? s.apparentTemperature : s.temperature;
    final dt = (t - 18.0).abs();
    penalty += min(5.0, pow(dt / 6.0, 1.3).toDouble());

    final w = s.windSpeed;
    double windFactor = 1.0;
    if (userHeadingDegrees != null) {
      final rel = _angleDiffDegrees(userHeadingDegrees, s.windDirection);
      final headness = cos((rel) * pi / 180.0);
      windFactor = (1.0 + 0.8 * headness).clamp(0.4, 1.8);
    }
    penalty += min(6.0, (w / 8.0) * windFactor);

    if (t >= 22.0 && s.humidity.isFinite) {
      penalty += min(1.5, (s.humidity - 60.0).clamp(0.0, 40.0) / 30.0);
    }

    final comfort = 10.0 - penalty;
    return comfort.clamp(1.0, 10.0);
  }

  double _angleDiffDegrees(double a, double b) {
    var d = (a - b) % 360.0;
    if (d < 0) d += 360.0;
    if (d > 180) d = 360.0 - d;
    return d;
  }
}

extension ListX<T> on List<T> {
  T? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }
}
