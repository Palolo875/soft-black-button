import 'dart:math';

import 'package:app/services/weather_engine_sota.dart';
import 'package:app/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class RouteWeatherProjector {
  final WeatherEngineSota _engine;

  RouteWeatherProjector({WeatherEngineSota? engine}) : _engine = engine ?? WeatherEngineSota();

  Future<List<RouteWeatherSample>> projectAlongPolyline({
    required List<LatLng> polyline,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    double sampleEveryMeters = 1000,
    int maxSamples = 60,
  }) async {
    if (polyline.length < 2) return const [];
    if (speedMetersPerSecond <= 0) {
      throw Exception('speedMetersPerSecond must be > 0');
    }

    final totalLen = _polylineLengthMeters(polyline);
    final effectiveEvery = maxSamples <= 2
        ? sampleEveryMeters
        : max(sampleEveryMeters, totalLen / (maxSamples - 1));

    final samples = _resamplePolyline(polyline, effectiveEvery);

    double total = 0.0;
    final out = <RouteWeatherSample>[];
    for (int i = 0; i < samples.length; i++) {
      if (i > 0) {
        total += _haversineMeters(samples[i - 1], samples[i]);
      }
      final eta = departureTime.add(Duration(
        milliseconds: ((total / speedMetersPerSecond) * 1000).round(),
      ));

      final heading = _bearingDegrees(
        i == 0 ? samples[i] : samples[i - 1],
        i == 0 && samples.length > 1 ? samples[i + 1] : samples[i],
      );

      final decision = await _engine.getDecisionForPointAtTime(
        samples[i],
        at: eta,
        userHeadingDegrees: heading,
      );

      final rel = _angleDiffDegrees(heading, decision.now.windDirection);
      final headness = cos(rel * pi / 180.0).clamp(-1.0, 1.0);
      final crossness = sin(rel * pi / 180.0).abs().clamp(0.0, 1.0);
      final impact = (decision.now.windSpeed * (0.65 * crossness + 1.0 * max(0.0, headness))).clamp(0.0, 60.0);
      final kind = _relativeWindKind(headness, crossness);
      out.add(RouteWeatherSample(
        location: samples[i],
        eta: eta,
        snapshot: decision.now,
        comfortScore: decision.comfortScore,
        confidence: decision.confidence,
        comfortBreakdown: decision.comfortBreakdown,
        headingDegrees: heading,
        relativeWindKind: kind,
        headwindness: headness,
        crosswindness: crossness,
        relativeWindImpact: impact,
      ));
    }

    return out;
  }

  double _polylineLengthMeters(List<LatLng> input) {
    double len = 0.0;
    for (int i = 1; i < input.length; i++) {
      len += _haversineMeters(input[i - 1], input[i]);
    }
    return len;
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

  double _bearingDegrees(LatLng a, LatLng b) {
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final brng = atan2(y, x) * 180.0 / pi;
    var out = (brng + 360.0) % 360.0;
    if (!out.isFinite) out = 0.0;
    return out;
  }

  double _angleDiffDegrees(double a, double b) {
    var d = (a - b) % 360.0;
    if (d < 0) d += 360.0;
    if (d > 180) d = 360.0 - d;
    return d;
  }

  RelativeWindKind _relativeWindKind(double headwindness, double crosswindness) {
    if (crosswindness >= 0.70) return RelativeWindKind.cross;
    if (headwindness <= -0.35) return RelativeWindKind.tail;
    if (headwindness >= 0.35) return RelativeWindKind.head;
    return RelativeWindKind.cross;
  }

  double _deg2rad(double d) => d * pi / 180.0;
}
