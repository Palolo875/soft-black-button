import 'dart:math';
import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/elevation_service.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/valhalla_client.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/core/log/app_log.dart';

class RoutingEngine {
  final ValhallaClient _valhalla;
  final RouteWeatherProjector _projector;
  final ElevationService _elevation;

  RoutingEngine({
    ValhallaClient? valhalla,
    RouteWeatherProjector? projector,
    ElevationService? elevation,
  })  : _valhalla = valhalla ?? ValhallaClient(),
        _projector = projector ?? RouteWeatherProjector(),
        _elevation = elevation ?? ElevationService();

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

        return _buildVariants(
          fast: fast,
          safe: safe,
          scenic: scenic,
          fastSamples: fastSamples,
          safeSamples: safeSamples,
          scenicSamples: scenicSamples,
        );
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

        return _buildVariants(
          fast: fast,
          safe: safe,
          scenic: scenic,
          fastSamples: fastSamples,
          safeSamples: safeSamples,
          scenicSamples: scenicSamples,
        );
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

      return enrichWithElevation([
        RouteVariant(
          kind: RouteVariantKind.fast,
          shape: base.shape,
          lengthKm: base.lengthKm,
          timeSeconds: base.timeSeconds,
          weatherSamples: samples,
        ),
      ]);
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

    final variants = [
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

    return enrichWithElevation(variants);
  }

  Future<List<RouteVariant>> _buildVariants({
    required ValhallaRouteResult fast,
    required ValhallaRouteResult safe,
    required ValhallaRouteResult scenic,
    required List<RouteWeatherSample> fastSamples,
    required List<RouteWeatherSample> safeSamples,
    required List<RouteWeatherSample> scenicSamples,
  }) async {
    final variants = [
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

    return enrichWithElevation(variants);
  }

  Future<List<RouteVariant>> enrichWithElevation(List<RouteVariant> variants) async {
    final enriched = <RouteVariant>[];
    for (final v in variants) {
      try {
        final List<LatLng> sampledPoints = [];
        // Sample every ~200m for better precision, capped at 400 points
        final double distMeters = v.lengthKm * 1000;
        final int idealSamples = (distMeters / 200).round();
        final int maxSamples = 400;
        final int numSamples = idealSamples.clamp(20, maxSamples);
        final step = max(1, v.shape.length ~/ numSamples);
        
        for (int i = 0; i < v.shape.length; i += step) {
          sampledPoints.add(v.shape[i]);
        }
        if (sampledPoints.isEmpty || sampledPoints.last != v.shape.last) {
          sampledPoints.add(v.shape.last);
        }

        final elevations = await _elevation.getElevation(sampledPoints);
        double gain = 0;
        double loss = 0;
        for (int i = 1; i < elevations.length; i++) {
          final diff = elevations[i] - elevations[i - 1];
          if (diff > 0) gain += diff;
          else loss += diff.abs();
        }

        enriched.add(RouteVariant(
          kind: v.kind,
          shape: v.shape,
          lengthKm: v.lengthKm,
          timeSeconds: v.timeSeconds,
          weatherSamples: v.weatherSamples,
          elevationGain: gain,
          elevationLoss: loss,
          elevationProfile: elevations,
        ));
      } catch (e, st) {
        AppLog.w('Could not enrich variant with elevation', error: e, stackTrace: st);
        enriched.add(v);
      }
    }
    return enriched;
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
        return 'motorcycle';
    }
  }
}
