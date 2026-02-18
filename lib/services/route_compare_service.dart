import 'dart:math';

import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/weather_models.dart';

class RouteDepartureComparison {
  final Duration offset;
  final double avgComfort;
  final double minComfort;
  final double avgConfidence;
  final double rainKm;
  final RelativeWindKind dominantWind;

  const RouteDepartureComparison({
    required this.offset,
    required this.avgComfort,
    required this.minComfort,
    required this.avgConfidence,
    required this.rainKm,
    required this.dominantWind,
  });
}

class DepartureWindowRecommendation {
  final Duration bestOffset;
  final List<RouteDepartureComparison> candidates;
  final String rationale;

  const DepartureWindowRecommendation({
    required this.bestOffset,
    required this.candidates,
    required this.rationale,
  });
}

class RouteCompareService {
  final RouteWeatherProjector _projector;

  RouteCompareService({RouteWeatherProjector? projector}) : _projector = projector ?? RouteWeatherProjector();

  Future<List<RouteDepartureComparison>> compareDepartures({
    required RouteVariant variant,
    required DateTime baseDepartureUtc,
    required double speedMetersPerSecond,
    required List<Duration> offsets,
    double sampleEveryMeters = 450,
    int maxSamples = 120,
  }) async {
    final out = <RouteDepartureComparison>[];

    for (final off in offsets) {
      final dep = baseDepartureUtc.add(off);
      final samples = await _projector.projectAlongPolyline(
        polyline: variant.shape,
        departureTime: dep,
        speedMetersPerSecond: speedMetersPerSecond,
        sampleEveryMeters: sampleEveryMeters,
        maxSamples: maxSamples,
      );

      out.add(_metricsFor(off, variant.lengthKm, samples));
    }

    return out;
  }

  Future<DepartureWindowRecommendation> recommendDepartureWindow({
    required RouteVariant variant,
    required DateTime baseDepartureUtc,
    required double speedMetersPerSecond,
    Duration horizon = const Duration(hours: 6),
    Duration step = const Duration(minutes: 20),
    double sampleEveryMeters = 450,
    int maxSamples = 120,
  }) async {
    final offsets = <Duration>[];
    for (var m = 0; m <= horizon.inMinutes; m += step.inMinutes) {
      offsets.add(Duration(minutes: m));
    }

    final candidates = await compareDepartures(
      variant: variant,
      baseDepartureUtc: baseDepartureUtc,
      speedMetersPerSecond: speedMetersPerSecond,
      offsets: offsets,
      sampleEveryMeters: sampleEveryMeters,
      maxSamples: maxSamples,
    );

    RouteDepartureComparison best = candidates.first;
    double bestScore = double.negativeInfinity;
    for (final c in candidates) {
      final score = _score(c);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    final baseline = candidates.first;
    final rationale = _rationale(best, baseline);

    return DepartureWindowRecommendation(
      bestOffset: best.offset,
      candidates: candidates,
      rationale: rationale,
    );
  }

  double _score(RouteDepartureComparison c) {
    // Simple, explainable objective: comfort up, rain down, confidence up.
    return (c.avgComfort * 1.0) - (c.rainKm * 0.35) + (c.avgConfidence * 0.8) + (c.minComfort * 0.25);
  }

  String _rationale(RouteDepartureComparison best, RouteDepartureComparison baseline) {
    final parts = <String>[];
    if (best.rainKm + 0.6 < baseline.rainKm) {
      parts.add('pluie évitée');
    }
    if (best.avgComfort > baseline.avgComfort + 0.4) {
      parts.add('confort ↑');
    }
    if (best.avgConfidence > baseline.avgConfidence + 0.08) {
      parts.add('fiabilité ↑');
    }
    if (parts.isEmpty) {
      return 'Meilleur compromis estimé dans la fenêtre.';
    }
    return parts.join(', ');
  }

  RouteDepartureComparison _metricsFor(Duration offset, double routeLenKm, List<RouteWeatherSample> samples) {
    if (samples.isEmpty) {
      return RouteDepartureComparison(
        offset: offset,
        avgComfort: 0,
        minComfort: 0,
        avgConfidence: 0,
        rainKm: 0,
        dominantWind: RelativeWindKind.cross,
      );
    }

    double sumComfort = 0;
    double minComfort = 999;
    double sumConf = 0;

    int rainCount = 0;
    int head = 0;
    int cross = 0;
    int tail = 0;

    for (final s in samples) {
      sumComfort += s.comfortScore;
      minComfort = min(minComfort, s.comfortScore);
      sumConf += s.confidence;

      if (s.snapshot.precipitation >= 1.0) rainCount++;

      switch (s.relativeWindKind) {
        case RelativeWindKind.head:
          head++;
          break;
        case RelativeWindKind.cross:
          cross++;
          break;
        case RelativeWindKind.tail:
          tail++;
          break;
      }
    }

    final n = samples.length;
    final kmPerSample = routeLenKm / max(1, n);
    final rainKm = rainCount * kmPerSample;

    RelativeWindKind dom = RelativeWindKind.cross;
    var best = cross;
    if (head > best) {
      dom = RelativeWindKind.head;
      best = head;
    }
    if (tail > best) {
      dom = RelativeWindKind.tail;
      best = tail;
    }

    return RouteDepartureComparison(
      offset: offset,
      avgComfort: sumComfort / n,
      minComfort: minComfort.isFinite ? minComfort : 0.0,
      avgConfidence: sumConf / n,
      rainKm: rainKm,
      dominantWind: dom,
    );
  }
}
