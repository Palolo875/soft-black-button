import 'package:app/services/route_weather_projector.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/valhalla_client.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class RoutingEngine {
  final ValhallaClient _valhalla;
  final RouteWeatherProjector _projector;

  const RoutingEngine({
    ValhallaClient valhalla = const ValhallaClient(),
    RouteWeatherProjector projector = const RouteWeatherProjector(),
  })  : _valhalla = valhalla,
        _projector = projector;

  Future<List<RouteVariant>> computeVariants({
    required LatLng start,
    required LatLng end,
    required DateTime departureTime,
    required double speedMetersPerSecond,
  }) async {
    final baseLocations = [start, end];

    final fast = await _valhalla.route(
      locations: baseLocations,
      costing: 'bicycle',
      costingOptions: {
        'bicycle': {
          'bicycle_type': 'Road',
          'cycling_speed': 24,
          'use_roads': 0.85,
          'use_hills': 0.70,
          'avoid_bad_surfaces': 0.10,
        }
      },
    );

    final safe = await _valhalla.route(
      locations: baseLocations,
      costing: 'bicycle',
      costingOptions: {
        'bicycle': {
          'bicycle_type': 'Hybrid',
          'cycling_speed': 18,
          'use_roads': 0.20,
          'use_hills': 0.25,
          'avoid_bad_surfaces': 0.65,
        }
      },
    );

    final scenic = await _valhalla.route(
      locations: baseLocations,
      costing: 'bicycle',
      costingOptions: {
        'bicycle': {
          'bicycle_type': 'City',
          'cycling_speed': 16,
          'use_roads': 0.35,
          'use_hills': 0.35,
          'avoid_bad_surfaces': 0.35,
          'maneuver_penalty': 10,
        }
      },
    );

    final fastSamples = await _projector.projectAlongPolyline(
      polyline: fast.shape,
      departureTime: departureTime,
      speedMetersPerSecond: speedMetersPerSecond,
      sampleEveryMeters: 900,
      maxSamples: 60,
    );

    final safeSamples = await _projector.projectAlongPolyline(
      polyline: safe.shape,
      departureTime: departureTime,
      speedMetersPerSecond: speedMetersPerSecond,
      sampleEveryMeters: 900,
      maxSamples: 60,
    );

    final scenicSamples = await _projector.projectAlongPolyline(
      polyline: scenic.shape,
      departureTime: departureTime,
      speedMetersPerSecond: speedMetersPerSecond,
      sampleEveryMeters: 900,
      maxSamples: 60,
    );

    return [
      RouteVariant(
        kind: RouteVariantKind.fast,
        shape: fast.shape,
        lengthKm: fast.lengthKm,
        timeSeconds: fast.timeSeconds,
        weatherSamples: fastSamples,
      ),
      RouteVariant(
        kind: RouteVariantKind.safe,
        shape: safe.shape,
        lengthKm: safe.lengthKm,
        timeSeconds: safe.timeSeconds,
        weatherSamples: safeSamples,
      ),
      RouteVariant(
        kind: RouteVariantKind.scenic,
        shape: scenic.shape,
        lengthKm: scenic.lengthKm,
        timeSeconds: scenic.timeSeconds,
        weatherSamples: scenicSamples,
      ),
    ];
  }
}
