import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/valhalla_client.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class RoutingEngine {
  final ValhallaClient _valhalla;
  final RouteWeatherProjector _projector;

  RoutingEngine({
    ValhallaClient? valhalla,
    RouteWeatherProjector? projector,
  })  : _valhalla = valhalla ?? ValhallaClient(),
        _projector = projector ?? RouteWeatherProjector();

  Future<List<RouteVariant>> computeVariants({
    required LatLng start,
    required LatLng end,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    TravelMode mode = TravelMode.cycling,
    ComfortProfile? comfortProfile,
    double sampleEveryMeters = 450,
    int maxSamples = 120,
  }) async {
    final baseLocations = [start, end];

    final costing = _costingFor(mode);

    if (mode != TravelMode.cycling) {
      if (mode == TravelMode.car || mode == TravelMode.motorbike) {
        final results = await _computeMotorizedVariants(
          locations: baseLocations,
          mode: mode,
          costing: costing,
        );

        final fast = results.$1;
        final safe = results.$2;
        final scenic = results.$3;

        final fastSamples = await _projector.projectAlongPolyline(
          polyline: fast.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
        );

        final safeSamples = await _projector.projectAlongPolyline(
          polyline: safe.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
        );

        final scenicSamples = await _projector.projectAlongPolyline(
          polyline: scenic.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
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

      if (mode == TravelMode.walking) {
        final fast = await _valhalla.route(
          locations: baseLocations,
          costing: 'pedestrian',
        );

        final safe = await _valhalla.route(
          locations: baseLocations,
          costing: 'pedestrian',
          costingOptions: {
            'pedestrian': {
              'maneuver_penalty': 10,
            },
          },
        );

        final scenic = await _valhalla.route(
          locations: baseLocations,
          costing: 'pedestrian',
          costingOptions: {
            'pedestrian': {
              'maneuver_penalty': 30,
            },
          },
        );

        final fastSamples = await _projector.projectAlongPolyline(
          polyline: fast.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
        );

        final safeSamples = await _projector.projectAlongPolyline(
          polyline: safe.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
        );

        final scenicSamples = await _projector.projectAlongPolyline(
          polyline: scenic.shape,
          departureTime: departureTime,
          speedMetersPerSecond: speedMetersPerSecond,
          comfortProfile: comfortProfile,
          sampleEveryMeters: sampleEveryMeters,
          maxSamples: maxSamples,
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

      final base = await _valhalla.route(
        locations: baseLocations,
        costing: costing,
      );

      final samples = await _projector.projectAlongPolyline(
        polyline: base.shape,
        departureTime: departureTime,
        speedMetersPerSecond: speedMetersPerSecond,
        comfortProfile: comfortProfile,
        sampleEveryMeters: sampleEveryMeters,
        maxSamples: maxSamples,
      );

      return [
        RouteVariant(
          kind: RouteVariantKind.fast,
          shape: base.shape,
          lengthKm: base.lengthKm,
          timeSeconds: base.timeSeconds,
          weatherSamples: samples,
        ),
      ];
    }

    final fast = await _valhalla.route(
      locations: baseLocations,
      costing: costing,
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
      costing: costing,
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
      costing: costing,
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
      comfortProfile: comfortProfile,
      sampleEveryMeters: sampleEveryMeters,
      maxSamples: maxSamples,
    );

    final safeSamples = await _projector.projectAlongPolyline(
      polyline: safe.shape,
      departureTime: departureTime,
      speedMetersPerSecond: speedMetersPerSecond,
      comfortProfile: comfortProfile,
      sampleEveryMeters: sampleEveryMeters,
      maxSamples: maxSamples,
    );

    final scenicSamples = await _projector.projectAlongPolyline(
      polyline: scenic.shape,
      departureTime: departureTime,
      speedMetersPerSecond: speedMetersPerSecond,
      comfortProfile: comfortProfile,
      sampleEveryMeters: sampleEveryMeters,
      maxSamples: maxSamples,
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

  Future<(ValhallaRouteResult, ValhallaRouteResult, ValhallaRouteResult)> _computeMotorizedVariants({
    required List<LatLng> locations,
    required TravelMode mode,
    required String costing,
  }) async {
    if (mode == TravelMode.car) {
      final fast = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 1.0,
            'use_tolls': 0.65,
          },
        },
      );

      final safe = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 0.05,
            'use_tolls': 0.0,
            'maneuver_penalty': 10,
          },
        },
      );

      final scenic = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 0.0,
            'use_tolls': 0.0,
            'maneuver_penalty': 30,
          },
        },
      );

      return (fast, safe, scenic);
    }

    try {
      final fast = await _valhalla.route(
        locations: locations,
        costing: costing,
        costingOptions: {
          'motorcycle': {
            'use_highways': 1.0,
            'use_tolls': 0.65,
          },
        },
      );

      final safe = await _valhalla.route(
        locations: locations,
        costing: costing,
        costingOptions: {
          'motorcycle': {
            'use_highways': 0.10,
            'use_tolls': 0.0,
            'maneuver_penalty': 10,
          },
        },
      );

      final scenic = await _valhalla.route(
        locations: locations,
        costing: costing,
        costingOptions: {
          'motorcycle': {
            'use_highways': 0.0,
            'use_tolls': 0.0,
            'maneuver_penalty': 30,
          },
        },
      );

      return (fast, safe, scenic);
    } catch (_) {
      final fast = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 1.0,
            'use_tolls': 0.65,
          },
        },
      );

      final safe = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 0.10,
            'use_tolls': 0.0,
            'maneuver_penalty': 10,
          },
        },
      );

      final scenic = await _valhalla.route(
        locations: locations,
        costing: 'auto',
        costingOptions: {
          'auto': {
            'use_highways': 0.0,
            'use_tolls': 0.0,
            'maneuver_penalty': 30,
          },
        },
      );

      return (fast, safe, scenic);
    }
  }

  String _costingFor(TravelMode mode) {
    switch (mode) {
      case TravelMode.walking:
      case TravelMode.stay:
        return 'pedestrian';
      case TravelMode.cycling:
        return 'bicycle';
      case TravelMode.car:
        return 'auto';
      case TravelMode.motorbike:
        // Not all Valhalla deployments enable motorcycle; we will fall back to
        // auto at runtime if this costing isn't supported.
        return 'motorcycle';
    }
  }
}
