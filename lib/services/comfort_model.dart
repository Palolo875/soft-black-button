import 'dart:math';

import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/services/comfort_profile.dart';
import 'package:horizon/services/route_geometry.dart';
import 'package:horizon/services/weather_models.dart';

enum ComfortContributionKind {
  rain,
  temperature,
  headwind,
  crosswind,
  humidity,
  night,
}

class ComfortContribution {
  final ComfortContributionKind kind;
  final String label;
  final double delta;

  const ComfortContribution({
    required this.kind,
    required this.label,
    required this.delta,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'label': label,
        'delta': delta,
      };

  static ComfortContribution fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'];
    final labelRaw = json['label'];
    final deltaRaw = json['delta'];
    final kind = ComfortContributionKind.values.firstWhere(
      (e) => e.name == kindRaw,
      orElse: () => ComfortContributionKind.temperature,
    );
    final label = labelRaw is String ? labelRaw : 'Facteur';
    final delta = deltaRaw is num ? deltaRaw.toDouble() : 0.0;
    return ComfortContribution(kind: kind, label: label, delta: delta);
  }
}

class ComfortBreakdown {
  final double score;
  final List<ComfortContribution> contributions;

  const ComfortBreakdown({
    required this.score,
    required this.contributions,
  });

  Map<String, dynamic> toJson() => {
        'score': score,
        'contributions': contributions.map((e) => e.toJson()).toList(),
      };

  static ComfortBreakdown fromJson(Map<String, dynamic> json) {
    final scoreRaw = json['score'];
    final score = scoreRaw is num ? scoreRaw.toDouble() : 0.0;
    final raw = json['contributions'];
    final contrib = <ComfortContribution>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          contrib.add(ComfortContribution.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ComfortBreakdown(score: score, contributions: contrib);
  }
}

class ComfortModel {
  const ComfortModel();

  ComfortBreakdown compute({
    required WeatherSnapshot s,
    required double? userHeadingDegrees,
    required ComfortProfile profile,
    required DateTime atUtc,
  }) {
    final contributions = <ComfortContribution>[];

    double penalty = 0.0;

    double rainPenalty = 0.0;
    if (s.precipitation >= HorizonConstants.rainLight) {
      if (s.precipitation >= HorizonConstants.rainExtreme) {
        rainPenalty = 4.0;
      } else if (s.precipitation >= HorizonConstants.rainHeavy) {
        rainPenalty = 2.7;
      } else if (s.precipitation >= HorizonConstants.rainModerate) {
        rainPenalty = 1.4;
      } else {
        rainPenalty = 0.6;
      }
    }
    rainPenalty *= profile.weightRain;
    penalty += rainPenalty;
    if (rainPenalty > 0.1) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.rain, label: 'Pluie', delta: -rainPenalty));
    }

    final t = s.apparentTemperature.isFinite ? s.apparentTemperature : s.temperature;
    final base = HorizonConstants.comfortBaseTemperature;
    final dt = (t - base).abs();
    var tempPenalty = min(5.0, pow(dt / 6.0, 1.3).toDouble());
    tempPenalty *= profile.weightTemperature;
    penalty += tempPenalty;
    if (tempPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.temperature, label: 'Température', delta: -tempPenalty));
    }

    final wind = s.windSpeed;
    double headwindness = 0.0;
    double crosswindness = 0.0;
    if (userHeadingDegrees != null) {
      final rel = angleDiffDegrees(userHeadingDegrees, s.windDirection);
      headwindness = cos(rel * pi / 180.0).clamp(-1.0, 1.0);
      crosswindness = sin(rel * pi / 180.0).abs().clamp(0.0, 1.0);
    }

    double headPenalty = 0.0;
    if (headwindness > 0 && wind >= HorizonConstants.windModerate) {
      final w = (wind - 6.0).clamp(0.0, 18.0);
      headPenalty = (w * 0.12 * profile.weightHeadwind);
      penalty += headPenalty;
    }
    if (headPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.headwind, label: 'Vent de face', delta: -headPenalty));
    }

    var crossPenalty = min(3.5, (wind / 10.0) * crosswindness);
    crossPenalty *= profile.weightCrosswind;
    penalty += crossPenalty;
    if (crossPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.crosswind, label: 'Vent latéral', delta: -crossPenalty));
    }

    double humidityPenalty = 0.0;
    if (t >= HorizonConstants.heatHumidityThreshold && s.humidity.isFinite) {
      final heatHum = (t - HorizonConstants.heatHumidityThreshold).clamp(0.0, 14.0);
      humidityPenalty = (heatHum * (s.humidity.clamp(0.0, 100.0) / 100.0) * 0.05 * profile.weightHumidity);
      penalty += humidityPenalty;
    }
    if (humidityPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.humidity, label: 'Humidité', delta: -humidityPenalty));
    }

    final hour = atUtc.toLocal().hour;
    final isNight = hour <= HorizonConstants.nightEndHour || hour >= HorizonConstants.nightStartHour;
    final nightPenalty = isNight ? (1.0 * profile.weightNight) : 0.0;
    penalty += nightPenalty;
    if (nightPenalty > 0.1) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.night, label: 'Nuit', delta: -nightPenalty));
    }

    final comfort = (10.0 - penalty).clamp(1.0, 10.0);

    contributions.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    return ComfortBreakdown(score: comfort, contributions: contributions);
  }
}
