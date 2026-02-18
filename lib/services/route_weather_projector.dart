import 'dart:math';
import 'package:horizon/services/route_geometry.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/weather_engine_sota.dart';
import 'package:horizon/services/weather_models.dart';
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

    final totalLen = polylineLengthMeters(polyline);
    final effectiveEvery = maxSamples <= 2
        ? sampleEveryMeters
        : max(sampleEveryMeters, totalLen / (maxSamples - 1));

    final samples = _resamplePolyline(polyline, effectiveEvery);

    double total = 0.0;
    final out = <RouteWeatherSample>[];
    for (int i = 0; i < samples.length; i++) {
      if (i > 0) {
        total += haversineMeters(samples[i - 1], samples[i]);
      }
      final eta = departureTime.add(Duration(
        milliseconds: ((total / speedMetersPerSecond) * 1000).round(),
      ));

      final heading = bearingDegrees(
        i == 0 ? samples[i] : samples[i - 1],
        i == 0 && samples.length > 1 ? samples[i + 1] : samples[i],
      );

      final decision = await _engine.getDecisionForPointAtTime(
        samples[i],
        at: eta,
        userHeadingDegrees: heading,
      );

      final rel = angleDiffDegrees(heading, decision.now.windDirection);
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

  List<LatLng> _resamplePolyline(List<LatLng> input, double everyMeters) {
    final out = <LatLng>[];
    out.add(input.first);

    double carry = 0.0;
    for (int i = 1; i < input.length; i++) {
      final a = input[i - 1];
      final b = input[i];
      final segLen = haversineMeters(a, b);
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

    if (out.last.latitude != input.last.latitude ||
        out.last.longitude != input.last.longitude) {
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

  RelativeWindKind _relativeWindKind(double headwindness, double crosswindness) {
    if (crosswindness >= 0.70) return RelativeWindKind.cross;
    if (headwindness <= -0.35) return RelativeWindKind.tail;
    if (headwindness >= 0.35) return RelativeWindKind.head;
    return RelativeWindKind.cross;
  }

  Map<String, dynamic> buildSegments(RouteVariant v) {
    final features = <Map<String, Object?>>[];
    final samples = v.weatherSamples;

    for (int i = 0; i + 1 < samples.length; i++) {
      final a = samples[i];
      final b = samples[i + 1];
      features.add({
        'type': 'Feature',
        'properties': {
          'windKind': a.relativeWindKind.name,
          'confidence': a.confidence,
          'comfort': a.comfortScore,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [a.location.longitude, a.location.latitude],
            [b.location.longitude, b.location.latitude],
          ],
        },
      });
    }

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }
}
