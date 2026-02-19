import 'package:horizon/services/comfort_profile.dart';
import 'package:horizon/services/routing_engine.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/weather_models.dart';
import 'package:horizon/services/trip_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class TripEngine {
  final RoutingEngine _routing;

  TripEngine({RoutingEngine? routingEngine}) : _routing = routingEngine ?? RoutingEngine();

  Future<List<RouteVariant>> computeTripVariants({
    required TripPlan plan,
    required DateTime departureTimeUtc,
    required double speedMetersPerSecond,
    ComfortProfile? comfortProfile,
    double sampleEveryMeters = 450,
    int maxSamples = 120,
  }) async {
    if (plan.stops.length < 2) return const [];

    final kinds = <RouteVariantKind>{
      RouteVariantKind.fast,
      RouteVariantKind.safe,
      RouteVariantKind.scenic,
    };

    final aggregated = <RouteVariantKind, _AggVariant>{
      for (final k in kinds) k: _AggVariant(kind: k),
    };

    DateTime segDeparture = departureTimeUtc.toUtc();

    for (int i = 0; i < plan.stops.length - 1; i++) {
      final a = plan.stops[i];
      final b = plan.stops[i + 1];

      final segVariants = await _routing.computeVariants(
        start: a.location,
        end: b.location,
        departureTime: segDeparture,
        speedMetersPerSecond: speedMetersPerSecond,
        mode: plan.mode,
        comfortProfile: comfortProfile,
        sampleEveryMeters: sampleEveryMeters,
        maxSamples: maxSamples,
      );

      final byKind = <RouteVariantKind, RouteVariant>{
        for (final v in segVariants) v.kind: v,
      };

      for (final k in kinds) {
        final seg = byKind[k];
        if (seg == null) {
          aggregated.remove(k);
          continue;
        }
        aggregated[k]?.add(seg);
      }

      final segFast = byKind[RouteVariantKind.fast] ?? segVariants.first;
      segDeparture = segDeparture.add(Duration(seconds: segFast.timeSeconds.round())).add(b.stay);
    }

    final intermediateStops = plan.stops.length > 2 ? plan.stops.sublist(1, plan.stops.length - 1) : const <TripStop>[];
    final totalStaySeconds = intermediateStops.fold<int>(0, (sum, s) => sum + s.stay.inSeconds);

    return aggregated.values
        .map((a) => a.build(extraTimeSeconds: totalStaySeconds))
        .toList();
  }
}

class _AggVariant {
  final RouteVariantKind kind;
  final List<RouteWeatherSample> samples = <RouteWeatherSample>[];
  final List<LatLng> _shape = <LatLng>[];
  double lengthKm = 0.0;
  double timeSeconds = 0.0;

  _AggVariant({required this.kind});

  void add(RouteVariant seg) {
    lengthKm += seg.lengthKm;
    timeSeconds += seg.timeSeconds;

    if (_shape.isEmpty) {
      _shape.addAll(seg.shape);
    } else {
      if (seg.shape.length > 1) {
        _shape.addAll(seg.shape.skip(1));
      }
    }

    samples.addAll(seg.weatherSamples);
  }

  RouteVariant build({required int extraTimeSeconds}) {
    return RouteVariant(
      kind: kind,
      shape: List.unmodifiable(_shape),
      lengthKm: lengthKm,
      timeSeconds: timeSeconds + extraTimeSeconds,
      weatherSamples: List.unmodifiable(samples),
    );
  }
}
