import 'dart:math';

import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class RouteWeatherProjector {
  final WeatherEngineSota _engine;

  const RouteWeatherProjector({WeatherEngineSota engine = const WeatherEngineSota()})
      : _engine = engine;

  Future<List<RouteWeatherSample>> projectAlongPolyline({
    required List<LatLng> polyline,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    double sampleEveryMeters = 1000,
  }) async {
    if (polyline.length < 2) return const [];
    if (speedMetersPerSecond <= 0) {
      throw Exception('speedMetersPerSecond must be > 0');
    }

    final samples = _resamplePolyline(polyline, sampleEveryMeters);

    double total = 0.0;
    final out = <RouteWeatherSample>[];
    for (int i = 0; i < samples.length; i++) {
      if (i > 0) {
        total += _haversineMeters(samples[i - 1], samples[i]);
      }
      final eta = departureTime.add(Duration(
        milliseconds: ((total / speedMetersPerSecond) * 1000).round(),
      ));

      final decision = await _engine.getDecisionForPoint(samples[i]);
      out.add(RouteWeatherSample(
        location: samples[i],
        eta: eta,
        snapshot: decision.now,
        comfortScore: decision.comfortScore,
        confidence: decision.confidence,
      ));
    }

    return out;
  }

  List<LatLng> _resamplePolyline(List<LatLng> input, double everyMeters) {
    final out = <LatLng>[];
    out.add(input.first);

    double carry = 0.0;
    for (int i = 1; i < input.length; i++) {
      final a = input[i - 1];
      final b = input[i];
      final segLen = _haversineMeters(a, b);
      if (segLen <= 0) continue;

      var dist = carry;
      while (dist + everyMeters <= segLen) {
        dist += everyMeters;
        final t = dist / segLen;
        out.add(_lerpLatLng(a, b, t));
      }
      carry = (dist + everyMeters) - segLen;
      if (carry < 0) carry = 0;
    }

    if (out.last.latitude != input.last.latitude || out.last.longitude != input.last.longitude) {
      out.add(input.last);
    }
    return out;
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);

    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon;
    return 2 * r * asin(min(1.0, sqrt(h)));
  }

  double _deg2rad(double d) => d * pi / 180.0;
}
