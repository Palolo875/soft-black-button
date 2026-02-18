import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/comfort_model.dart';
import 'package:app/services/comfort_profile.dart';
import 'package:app/services/weather_models.dart';

void main() {
  group('ComfortContribution', () {
    test('fromJson is resilient to invalid fields', () {
      final c = ComfortContribution.fromJson(const {'kind': 'nope', 'label': 1, 'delta': 'x'});
      expect(c.kind, ComfortContributionKind.temperature);
      expect(c.label, 'Facteur');
      expect(c.delta, 0.0);
    });
  });

  group('ComfortBreakdown', () {
    test('fromJson ignores invalid contributions', () {
      final b = ComfortBreakdown.fromJson({
        'score': 7,
        'contributions': [
          {'kind': 'rain', 'label': 'Pluie', 'delta': -3.5},
          'bad',
          123,
          {'kind': 'temperature', 'label': 'Température', 'delta': -1.0},
        ],
      });

      expect(b.score, 7.0);
      expect(b.contributions, hasLength(2));
    });
  });

  group('ComfortModel.compute', () {
    test('penalizes rain above threshold', () {
      const model = ComfortModel();
      final now = DateTime.utc(2026, 1, 1, 12);
      const profile = ComfortProfile();

      final dry = model.compute(
        s: WeatherSnapshot(
          timestamp: now,
          temperature: 18,
          apparentTemperature: 18,
          windSpeed: 0,
          windDirection: 0,
          precipitation: 0,
          humidity: 50,
          cloudCover: 0,
          pressure: 1000,
        ),
        userHeadingDegrees: null,
        profile: profile,
        atUtc: now,
      );

      final wet = model.compute(
        s: WeatherSnapshot(
          timestamp: now,
          temperature: 18,
          apparentTemperature: 18,
          windSpeed: 0,
          windDirection: 0,
          precipitation: 2.0,
          humidity: 50,
          cloudCover: 0,
          pressure: 1000,
        ),
        userHeadingDegrees: null,
        profile: profile,
        atUtc: now,
      );

      expect(wet.score, lessThan(dry.score));
      expect(wet.contributions.any((c) => c.kind == ComfortContributionKind.rain), isTrue);
    });

    test('penalizes headwind more than tailwind when heading provided', () {
      const model = ComfortModel();
      final now = DateTime.utc(2026, 1, 1, 12);
      const profile = ComfortProfile();

      final headwind = model.compute(
        s: WeatherSnapshot(
          timestamp: now,
          temperature: 18,
          apparentTemperature: 18,
          windSpeed: 12,
          windDirection: 0,
          precipitation: 0,
          humidity: 50,
          cloudCover: 0,
          pressure: 1000,
        ),
        userHeadingDegrees: 0,
        profile: profile,
        atUtc: now,
      );

      final tailwind = model.compute(
        s: WeatherSnapshot(
          timestamp: now,
          temperature: 18,
          apparentTemperature: 18,
          windSpeed: 12,
          windDirection: 180,
          precipitation: 0,
          humidity: 50,
          cloudCover: 0,
          pressure: 1000,
        ),
        userHeadingDegrees: 0,
        profile: profile,
        atUtc: now,
      );

      expect(headwind.score, lessThan(tailwind.score));
      expect(headwind.contributions.any((c) => c.kind == ComfortContributionKind.headwind), isTrue);
    });

    test('adds night penalty during night hours', () {
      const model = ComfortModel();
      const profile = ComfortProfile();

      final night = DateTime.utc(2026, 1, 1, 23);
      final day = DateTime.utc(2026, 1, 1, 12);

      ComfortBreakdown runAt(DateTime atUtc) {
        return model.compute(
          s: WeatherSnapshot(
            timestamp: atUtc,
            temperature: 18,
            apparentTemperature: 18,
            windSpeed: 0,
            windDirection: 0,
            precipitation: 0,
            humidity: 50,
            cloudCover: 0,
            pressure: 1000,
          ),
          userHeadingDegrees: null,
          profile: profile,
          atUtc: atUtc,
        );
      }

      final bNight = runAt(night);
      final bDay = runAt(day);
      expect(bNight.score, lessThan(bDay.score));
      expect(bNight.contributions.any((c) => c.kind == ComfortContributionKind.night), isTrue);
    });

    test('sorts contributions by magnitude descending', () {
      const model = ComfortModel();
      final now = DateTime.utc(2026, 1, 1, 12);
      const profile = ComfortProfile();

      final b = model.compute(
        s: WeatherSnapshot(
          timestamp: now,
          temperature: -5,
          apparentTemperature: -5,
          windSpeed: 20,
          windDirection: 0,
          precipitation: 3.0,
          humidity: 50,
          cloudCover: 0,
          pressure: 1000,
        ),
        userHeadingDegrees: 0,
        profile: profile,
        atUtc: now,
      );

      expect(b.contributions, isNotEmpty);
      for (int i = 1; i < b.contributions.length; i++) {
        expect(b.contributions[i - 1].delta.abs(), greaterThanOrEqualTo(b.contributions[i].delta.abs()));
      }
    });
  });
}
