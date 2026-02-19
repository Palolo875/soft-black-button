import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/route_cache_helper.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/routing_models.dart';

void main() {
  group('RouteCacheKey', () {
    test('generates correct key', () {
      final key = RouteCacheKey(
        mode: 'cycling',
        speedBucketMps: 4.5,
        startLat: 48.8566,
        startLng: 2.3522,
        endLat: 48.8606,
        endLng: 2.3376,
      );

      expect(key.toKey(), 'v2_cycling_s4.5_48.86_2.35__48.86_2.34');
    });

    test('generates correct legacy key', () {
      final key = RouteCacheKey(
        mode: 'cycling',
        speedBucketMps: 4.5,
        startLat: 48.8566,
        startLng: 2.3522,
        endLat: 48.8606,
        endLng: 2.3376,
      );

      expect(key.toLegacyKey(), 'v1_48.86_2.35__48.86_2.34');
    });

    test('fromLocations creates correct key', () {
      final start = LatLng(48.8566, 2.3522);
      final end = LatLng(48.8606, 2.3376);

      final key = RouteCacheKey.fromLocations(start, end, 'cycling', 4.2);

      expect(key?.mode, 'cycling');
      expect(key?.speedBucketMps, 4.0);
    });

    test('fromLocations returns null for invalid locations', () {
      final key = RouteCacheKey.fromLocations(
        LatLng(48.8566, 2.3522),
        LatLng(48.8606, 2.3376),
        '',
        0,
      );

      expect(key, isNull);
    });
  });

  group('RouteCacheSerializer', () {
    test('serializes variants correctly', () {
      final variants = [
        RouteVariant(
          kind: RouteVariantKind.fast,
          shape: [
            LatLng(48.8566, 2.3522),
            LatLng(48.8606, 2.3376),
          ],
          lengthKm: 5.2,
          timeSeconds: 1200,
          weatherSamples: const [],
        ),
      ];

      final serialized = RouteCacheSerializer.serializeVariants(variants);

      expect(serialized['variants'], hasLength(1));
      final variant = (serialized['variants'] as List).first;
      expect(variant['kind'], 'fast');
      expect(variant['lengthKm'], 5.2);
      expect(variant['timeSeconds'], 1200);
    });

    test('deserializes variants correctly', () {
      final payload = {
        'variants': [
          {
            'kind': 'fast',
            'lengthKm': 5.2,
            'timeSeconds': 1200,
            'shape': [
              [2.3522, 48.8566],
              [2.3376, 48.8606],
            ],
          },
        ],
      };

      final variants = RouteCacheSerializer.deserializeVariants(payload);

      expect(variants, isNotNull);
      expect(variants!.length, 1);
      expect(variants.first.kind, RouteVariantKind.fast);
      expect(variants.first.lengthKm, 5.2);
      expect(variants.first.shape.length, 2);
    });

    test('deserializeVariants returns null for invalid payload', () {
      expect(RouteCacheSerializer.deserializeVariants({}), isNull);
      expect(RouteCacheSerializer.deserializeVariants({'variants': 'invalid'}), isNull);
      expect(RouteCacheSerializer.deserializeVariants({'variants': []}), isNull);
    });

    test('round trip preserves data', () {
      final original = [
        RouteVariant(
          kind: RouteVariantKind.safe,
          shape: [
            LatLng(48.8566, 2.3522),
            LatLng(48.8586, 2.3422),
            LatLng(48.8606, 2.3376),
          ],
          lengthKm: 3.5,
          timeSeconds: 700,
          weatherSamples: const [],
        ),
      ];

      final serialized = RouteCacheSerializer.serializeVariants(original);
      final deserialized = RouteCacheSerializer.deserializeVariants(serialized);

      expect(deserialized?.length, 1);
      expect(deserialized!.first.kind, RouteVariantKind.safe);
      expect(deserialized.first.lengthKm, 3.5);
      expect(deserialized.first.shape.length, 3);
    });
  });
}
