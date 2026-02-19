import 'package:horizon/core/mobility/exposure_profile.dart';
import 'package:horizon/core/mobility/travel_mode.dart';
import 'package:horizon/services/home_today_store.dart';
import 'package:horizon/services/weather_engine_sota.dart';
import 'package:horizon/services/weather_models.dart';

class PlaceNowSummary {
  final FavoritePlace place;
  final WeatherDecision decision;

  const PlaceNowSummary({
    required this.place,
    required this.decision,
  });
}

class PlaceWindowCandidate {
  final FavoritePlace place;
  final DateTime atUtc;
  final WeatherDecision decision;

  const PlaceWindowCandidate({
    required this.place,
    required this.atUtc,
    required this.decision,
  });
}

class HomeTodaySummary {
  final DateTime computedAtUtc;
  final List<PlaceNowSummary> now;
  final List<PlaceWindowCandidate> bestWindows;

  const HomeTodaySummary({
    required this.computedAtUtc,
    required this.now,
    required this.bestWindows,
  });
}

class HomeTodayEngine {
  final WeatherEngineSota _weather;

  HomeTodayEngine({required WeatherEngineSota weatherEngine}) : _weather = weatherEngine;

  Future<HomeTodaySummary> compute({
    required List<FavoritePlace> places,
    DateTime? nowUtc,
    Duration horizon = const Duration(hours: 10),
    Duration step = const Duration(minutes: 30),
  }) async {
    final baseNow = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final comfortProfile = ExposureProfile.defaultsFor(TravelMode.stay).toComfortProfile();

    final nowOut = <PlaceNowSummary>[];
    for (final p in places) {
      final d = await _weather.getDecisionForPointAtTime(
        p.location,
        at: baseNow,
        comfortProfile: comfortProfile,
      );
      nowOut.add(PlaceNowSummary(place: p, decision: d));
    }

    final bestWindows = <PlaceWindowCandidate>[];
    for (final p in places) {
      PlaceWindowCandidate? best;
      for (var t = baseNow; !t.isAfter(baseNow.add(horizon)); t = t.add(step)) {
        final d = await _weather.getDecisionForPointAtTime(
          p.location,
          at: t,
          comfortProfile: comfortProfile,
        );
        final c = PlaceWindowCandidate(place: p, atUtc: t, decision: d);
        if (best == null || _score(c) > _score(best)) {
          best = c;
        }
      }
      if (best != null) bestWindows.add(best);
    }

    return HomeTodaySummary(
      computedAtUtc: baseNow,
      now: nowOut,
      bestWindows: bestWindows,
    );
  }

  double _score(PlaceWindowCandidate c) {
    final rain = c.decision.now.precipitation;
    final comfort = c.decision.comfortScore;
    final conf = c.decision.confidence;

    double score = (comfort * 1.0) + (conf * 1.0);
    if (rain >= 1.0) score -= 1.5;
    if (rain >= 3.0) score -= 2.5;

    return score;
  }
}
