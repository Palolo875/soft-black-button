import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/core/constants/horizon_constants.dart';

class RouteCacheKey {
  final String mode;
  final double speedBucketMps;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;

  const RouteCacheKey({
    required this.mode,
    required this.speedBucketMps,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  String toKey({double gridFactor = HorizonConstants.routeCacheGridFactor}) {
    double round(double v) => (v * gridFactor).roundToDouble() / gridFactor;
    return 'v2_${mode}_s${speedBucketMps.toStringAsFixed(1)}_${round(startLat)}_${round(startLng)}__${round(endLat)}_${round(endLng)}';
  }

  String toLegacyKey({double gridFactor = HorizonConstants.routeCacheGridFactor}) {
    double round(double v) => (v * gridFactor).roundToDouble() / gridFactor;
    return 'v1_${round(startLat)}_${round(startLng)}__${round(endLat)}_${round(endLng)}';
  }

  static RouteCacheKey? fromLocations(
    LatLng start,
    LatLng end,
    String mode,
    double speedMps,
  ) {
    final speedBucket = (speedMps * 2).round() / 2;
    return RouteCacheKey(
      mode: mode,
      speedBucketMps: speedBucket,
      startLat: start.latitude,
      startLng: start.longitude,
      endLat: end.latitude,
      endLng: end.longitude,
    );
  }
}

class RouteCacheSerializer {
  static Map<String, dynamic> serializeVariants(List<RouteVariant> variants) {
    return {
      'variants': variants
          .map((v) => {
                'kind': v.kind.name,
                'lengthKm': v.lengthKm,
                'timeSeconds': v.timeSeconds,
                'shape': v.shape.map((p) => [p.longitude, p.latitude]).toList(),
                'elevationGain': v.elevationGain,
                'elevationLoss': v.elevationLoss,
                'elevationProfile': v.elevationProfile,
              })
          .toList(),
    };
  }

  static List<RouteVariant>? deserializeVariants(Map<String, dynamic> payload) {
    final variantsRaw = payload['variants'];
    if (variantsRaw is! List) return null;

    final out = <RouteVariant>[];
    for (final raw in variantsRaw) {
      if (raw is! Map) continue;
      final kindRaw = raw['kind'];
      final lengthRaw = raw['lengthKm'];
      final timeRaw = raw['timeSeconds'];
      final shapeRaw = raw['shape'];

      if (kindRaw is! String || lengthRaw is! num || timeRaw is! num || shapeRaw is! List) {
        continue;
      }

      RouteVariantKind? kind;
      for (final k in RouteVariantKind.values) {
        if (k.name == kindRaw) {
          kind = k;
          break;
        }
      }
      if (kind == null) continue;

      final shape = <LatLng>[];
      for (final p in shapeRaw) {
        if (p is! List || p.length != 2) continue;
        final lon = p[0];
        final lat = p[1];
        if (lon is! num || lat is! num) continue;
        shape.add(LatLng(lat.toDouble(), lon.toDouble()));
      }
      if (shape.length < 2) continue;

      out.add(RouteVariant(
        kind: kind,
        shape: shape,
        lengthKm: lengthRaw.toDouble(),
        timeSeconds: timeRaw.toDouble(),
        weatherSamples: const [],
        elevationGain: raw['elevationGain']?.toDouble(),
        elevationLoss: raw['elevationLoss']?.toDouble(),
        elevationProfile: (raw['elevationProfile'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      ));
    }

    if (out.isEmpty) return null;
    return out;
  }
}
