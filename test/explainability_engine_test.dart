import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/explainability_engine.dart';
import 'package:app/services/routing_models.dart';
import 'package:app/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  group('ExplainabilityEngine.metricsFor', () {
    test('returns zeros when no samples', () {
      const engine = ExplainabilityEngine();
      const v = RouteVariant(
        kind: RouteVariantKind.fast,
        shape: <LatLng>[],
        lengthKm: 10,
        timeSeconds: 100,
        weatherSamples: <RouteWeatherSample>[],
      );

      final m = engine.metricsFor(v);
      expect(m.avgConfidence, 0);
      expect(m.avgWind, 0);
      expect(m.rainKm, 0);
      expect(m.extremeTempKm, 0);
      expect(m.minComfort, 0);
    });

    test('computes aggregated metrics', () {
      const engine = ExplainabilityEngine();
      final now = DateTime.utc(2026, 1, 1);

      final samples = <RouteWeatherSample>[
        RouteWeatherSample(
          location: const LatLng(0, 0),
          eta: now,
          snapshot: WeatherSnapshot(
            timestamp: now,
            temperature: 10,
            apparentTemperature: 10,
            windSpeed: 5,
            windDirection: 90,
            precipitation: 0,
            humidity: 0.5,
            cloudCover: 0.2,
            pressure: 1000,
          ),
          comfortScore: 7,
          confidence: 0.8,
        ),
        RouteWeatherSample(
          location: const LatLng(0, 0),
          eta: now,
          snapshot: WeatherSnapshot(
            timestamp: now,
            temperature: 4,
            apparentTemperature: 4,
            windSpeed: 15,
            windDirection: 90,
            precipitation: 1.5,
            humidity: 0.5,
            cloudCover: 0.2,
            pressure: 1000,
          ),
          comfortScore: 3,
          confidence: 0.4,
        ),
      ];

      final v = RouteVariant(
        kind: RouteVariantKind.fast,
        shape: const <LatLng>[],
        lengthKm: 10,
        timeSeconds: 100,
        weatherSamples: samples,
      );

      final m = engine.metricsFor(v);
      expect(m.avgConfidence, closeTo((0.8 + 0.4) / 2, 1e-9));
      expect(m.avgWind, closeTo((5 + 15) / 2, 1e-9));
      expect(m.minComfort, 3);
      expect(m.rainKm, closeTo(5.0, 1e-9));
      expect(m.extremeTempKm, closeTo(5.0, 1e-9));
    });
  });

  group('ExplainabilityEngine.explain', () {
    test('adds confidence caveat when avg confidence is low', () {
      const engine = ExplainabilityEngine();
      const v = RouteVariant(
        kind: RouteVariantKind.fast,
        shape: <LatLng>[],
        lengthKm: 10,
        timeSeconds: 100,
        weatherSamples: <RouteWeatherSample>[],
      );

      const low = RouteVariantMetrics(
        avgConfidence: 0.2,
        avgWind: 0,
        rainKm: 0,
        extremeTempKm: 0,
        minComfort: 10,
      );

      final ex = engine.explain(v: v, allMetrics: const {RouteVariantKind.fast: low});
      expect(ex.caveat, isNotNull);
      expect(ex.factors.any((f) => f.kind == ExplanationFactorKind.confidence), isTrue);
    });
  });
}
