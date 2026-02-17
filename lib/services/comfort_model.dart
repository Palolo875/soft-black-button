import 'dart:math';

import 'package:app/services/comfort_profile.dart';
import 'package:app/services/weather_models.dart';

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

    final r = s.precipitation;
    double rainPenalty;
    if (r <= 0.1) {
      rainPenalty = 0.0;
    } else if (r <= 0.5) {
      rainPenalty = 1.5;
    } else if (r <= 1.5) {
      rainPenalty = 3.5;
    } else if (r <= 4.0) {
      rainPenalty = 6.0;
    } else {
      rainPenalty = 8.0;
    }
    rainPenalty *= profile.weightRain;
    penalty += rainPenalty;
    if (rainPenalty > 0.1) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.rain, label: 'Pluie', delta: -rainPenalty));
    }

    final t = s.apparentTemperature.isFinite ? s.apparentTemperature : s.temperature;
    final dt = (t - 18.0).abs();
    var tempPenalty = min(5.0, pow(dt / 6.0, 1.3).toDouble());
    tempPenalty *= profile.weightTemperature;
    penalty += tempPenalty;
    if (tempPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.temperature, label: 'Température', delta: -tempPenalty));
    }

    final w = s.windSpeed;
    double headwindness = 0.0;
    double crosswindness = 0.0;
    if (userHeadingDegrees != null) {
      final rel = _angleDiffDegrees(userHeadingDegrees, s.windDirection);
      headwindness = cos(rel * pi / 180.0).clamp(-1.0, 1.0);
      crosswindness = sin(rel * pi / 180.0).abs().clamp(0.0, 1.0);
    }

    var headPenalty = 0.0;
    if (headwindness > 0) {
      headPenalty = min(6.0, (w / 8.0) * (1.0 + 0.8 * headwindness));
    }
    headPenalty *= profile.weightHeadwind;
    penalty += headPenalty;
    if (headPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.headwind, label: 'Vent de face', delta: -headPenalty));
    }

    var crossPenalty = min(3.5, (w / 10.0) * crosswindness);
    crossPenalty *= profile.weightCrosswind;
    penalty += crossPenalty;
    if (crossPenalty > 0.2) {
      contributions.add(ComfortContribution(kind: ComfortContributionKind.crosswind, label: 'Vent latéral', delta: -crossPenalty));
    }

    if (t >= 22.0 && s.humidity.isFinite) {
      var humPenalty = min(1.5, (s.humidity - 60.0).clamp(0.0, 40.0) / 30.0);
      humPenalty *= profile.weightHumidity;
      penalty += humPenalty;
      if (humPenalty > 0.15) {
        contributions.add(ComfortContribution(kind: ComfortContributionKind.humidity, label: 'Humidité', delta: -humPenalty));
      }
    }

    final hour = atUtc.toLocal().hour;
    final isNight = hour <= 6 || hour >= 22;
    if (isNight) {
      final nightPenalty = 0.9 * profile.weightNight;
      penalty += nightPenalty;
      if (nightPenalty > 0.1) {
        contributions.add(ComfortContribution(kind: ComfortContributionKind.night, label: 'Nuit', delta: -nightPenalty));
      }
    }

    final comfort = (10.0 - penalty).clamp(1.0, 10.0);

    contributions.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    return ComfortBreakdown(score: comfort, contributions: contributions);
  }

  double _angleDiffDegrees(double a, double b) {
    var d = (a - b) % 360.0;
    if (d < 0) d += 360.0;
    if (d > 180) d = 360.0 - d;
    return d;
  }
}
