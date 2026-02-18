import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/route_compare_service.dart';
import 'package:horizon/services/route_weather_projector.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakeProjector extends RouteWeatherProjector {
  final List<RouteWeatherSample> samples;

  _FakeProjector(this.samples);

  @override
  Future<List<RouteWeatherSample>> projectAlongPolyline({
    required List<LatLng> polyline,
    required DateTime departureTime,
    required double speedMetersPerSecond,
    double sampleEveryMeters = 1000,
    int maxSamples = 60,
  }) async {
    return samples;
  }
}

void main() {
  test('compareDepartures computes metrics for each offset', () async {
    final now = DateTime.utc(2026, 1, 1);
    final samples = <RouteWeatherSample>[
      RouteWeatherSample(
        location: const LatLng(0, 0),
        eta: now,
        snapshot: WeatherSnapshot(
          timestamp: now,
          temperature: 10,
          apparentTemperature: 10,
          windSpeed: 10,
          windDirection: 90,
          precipitation: 0,
          humidity: 0.5,
          cloudCover: 0.2,
          pressure: 1000,
        ),
        comfortScore: 6,
        confidence: 0.6,
        relativeWindKind: RelativeWindKind.head,
      ),
      RouteWeatherSample(
        location: const LatLng(0, 0),
        eta: now,
        snapshot: WeatherSnapshot(
          timestamp: now,
          temperature: 10,
          apparentTemperature: 10,
          windSpeed: 10,
          windDirection: 90,
          precipitation: 2.0,
          humidity: 0.5,
          cloudCover: 0.2,
          pressure: 1000,
        ),
        comfortScore: 4,
        confidence: 0.4,
        relativeWindKind: RelativeWindKind.cross,
      ),
    ];

    final svc = RouteCompareService(projector: _FakeProjector(samples));

    const variant = RouteVariant(
      kind: RouteVariantKind.fast,
      shape: <LatLng>[LatLng(0, 0), LatLng(1, 1)],
      lengthKm: 10,
      timeSeconds: 100,
      weatherSamples: <RouteWeatherSample>[],
    );

    final res = await svc.compareDepartures(
      variant: variant,
      baseDepartureUtc: now,
      speedMetersPerSecond: 4.2,
      offsets: const [Duration.zero, Duration(hours: 1)],
    );

    expect(res, hasLength(2));
    expect(res.first.avgComfort, closeTo(5.0, 1e-9));
    expect(res.first.minComfort, 4);
    expect(res.first.avgConfidence, closeTo(0.5, 1e-9));
    expect(res.first.rainKm, closeTo(5.0, 1e-9));
    expect(res.first.dominantWind, RelativeWindKind.cross);
  });
}
