import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:horizon/services/routing_engine.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/trip_engine.dart';
import 'package:horizon/services/trip_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakeRoutingEngine extends RoutingEngine {
  final Map<String, List<RouteVariant>> byLeg;

  _FakeRoutingEngine(this.byLeg);

  String _k(LatLng a, LatLng b) => '${a.latitude},${a.longitude}__${b.latitude},${b.longitude}';

  @override
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
    return byLeg[_k(start, end)] ?? const [];
  }
}

void main() {
  test('TripEngine aggregates shapes and times and includes intermediate stays', () async {
    const a = LatLng(0, 0);
    const b = LatLng(1, 1);
    const c = LatLng(2, 2);

    const plan = TripPlan(
      id: 't1',
      name: 'Test',
      mode: TravelMode.walking,
      stops: [
        TripStop(id: 'a', name: 'A', location: a),
        TripStop(id: 'b', name: 'B', location: b, stay: Duration(minutes: 10)),
        TripStop(id: 'c', name: 'C', location: c, stay: Duration(minutes: 99)),
      ],
    );

    const leg1Fast = RouteVariant(
      kind: RouteVariantKind.fast,
      shape: [a, b],
      lengthKm: 1,
      timeSeconds: 60,
      weatherSamples: [],
    );
    const leg1Safe = RouteVariant(
      kind: RouteVariantKind.safe,
      shape: [a, b],
      lengthKm: 1.2,
      timeSeconds: 75,
      weatherSamples: [],
    );
    const leg1Scenic = RouteVariant(
      kind: RouteVariantKind.scenic,
      shape: [a, b],
      lengthKm: 1.5,
      timeSeconds: 90,
      weatherSamples: [],
    );

    const leg2Fast = RouteVariant(
      kind: RouteVariantKind.fast,
      shape: [b, c],
      lengthKm: 2,
      timeSeconds: 120,
      weatherSamples: [],
    );
    const leg2Safe = RouteVariant(
      kind: RouteVariantKind.safe,
      shape: [b, c],
      lengthKm: 2.4,
      timeSeconds: 150,
      weatherSamples: [],
    );
    const leg2Scenic = RouteVariant(
      kind: RouteVariantKind.scenic,
      shape: [b, c],
      lengthKm: 2.8,
      timeSeconds: 180,
      weatherSamples: [],
    );

    final engine = TripEngine(
      routingEngine: _FakeRoutingEngine({
        '0.0,0.0__1.0,1.0': const [leg1Fast, leg1Safe, leg1Scenic],
        '1.0,1.0__2.0,2.0': const [leg2Fast, leg2Safe, leg2Scenic],
      }),
    );

    final res = await engine.computeTripVariants(
      plan: plan,
      departureTimeUtc: DateTime.utc(2026, 1, 1, 12),
      speedMetersPerSecond: 1.4,
    );

    expect(res, hasLength(3));

    final fast = res.firstWhere((v) => v.kind == RouteVariantKind.fast);
    expect(fast.shape, [a, b, c]);
    expect(fast.lengthKm, 3);
    expect(fast.timeSeconds, 60 + 120 + (10 * 60));
  });

  test('TripEngine drops a kind when any leg is missing it', () async {
    const a = LatLng(0, 0);
    const b = LatLng(1, 1);
    const c = LatLng(2, 2);

    const plan = TripPlan(
      id: 't1',
      name: 'Test',
      mode: TravelMode.car,
      stops: [
        TripStop(id: 'a', name: 'A', location: a),
        TripStop(id: 'b', name: 'B', location: b),
        TripStop(id: 'c', name: 'C', location: c),
      ],
    );

    const leg1Fast = RouteVariant(kind: RouteVariantKind.fast, shape: [a, b], lengthKm: 1, timeSeconds: 60, weatherSamples: []);
    const leg1Safe = RouteVariant(kind: RouteVariantKind.safe, shape: [a, b], lengthKm: 1.2, timeSeconds: 75, weatherSamples: []);

    const leg2Fast = RouteVariant(kind: RouteVariantKind.fast, shape: [b, c], lengthKm: 2, timeSeconds: 120, weatherSamples: []);
    const leg2Safe = RouteVariant(kind: RouteVariantKind.safe, shape: [b, c], lengthKm: 2.4, timeSeconds: 150, weatherSamples: []);

    final engine = TripEngine(
      routingEngine: _FakeRoutingEngine({
        '0.0,0.0__1.0,1.0': const [leg1Fast, leg1Safe],
        '1.0,1.0__2.0,2.0': const [leg2Fast, leg2Safe],
      }),
    );

    final res = await engine.computeTripVariants(
      plan: plan,
      departureTimeUtc: DateTime.utc(2026, 1, 1, 12),
      speedMetersPerSecond: 10,
    );

    expect(res.any((v) => v.kind == RouteVariantKind.scenic), isFalse);
    expect(res.any((v) => v.kind == RouteVariantKind.fast), isTrue);
    expect(res.any((v) => v.kind == RouteVariantKind.safe), isTrue);
  });
}
