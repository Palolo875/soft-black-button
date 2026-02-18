import 'dart:math';

import 'package:horizon/core/constants/cycling_constants.dart';
import 'package:horizon/services/routing_models.dart';
import 'package:horizon/services/weather_models.dart';

enum ExplanationLevel { level1, level2 }

enum ExplanationFactorKind { wind, rain, temperature, confidence, comfort }

class ExplanationFactor {
  final ExplanationFactorKind kind;
  final String title;
  final String detail;
  final double severity; // 0..1

  const ExplanationFactor({
    required this.kind,
    required this.title,
    required this.detail,
    required this.severity,
  });
}

class RouteVariantMetrics {
  final double avgConfidence; // 0..1
  final double avgWind; // m/s
  final double rainKm;
  final double extremeTempKm;
  final double minComfort;

  const RouteVariantMetrics({
    required this.avgConfidence,
    required this.avgWind,
    required this.rainKm,
    required this.extremeTempKm,
    required this.minComfort,
  });
}

class RouteExplanation {
  final RouteVariantKind kind;
  final String headline;
  final String? caveat;
  final RouteVariantMetrics metrics;
  final List<ExplanationFactor> factors; // sorted, most important first

  const RouteExplanation({
    required this.kind,
    required this.headline,
    required this.metrics,
    required this.factors,
    this.caveat,
  });
}

class ExplainabilityEngine {
  const ExplainabilityEngine();

  RouteVariantMetrics metricsFor(RouteVariant v) {
    if (v.weatherSamples.isEmpty) {
      return const RouteVariantMetrics(
        avgConfidence: 0.0,
        avgWind: 0.0,
        rainKm: 0.0,
        extremeTempKm: 0.0,
        minComfort: 0.0,
      );
    }

    double sumConf = 0;
    double sumWind = 0;
    double minComfort = 999;

    int rainCount = 0;
    int extremeTempCount = 0;

    for (final s in v.weatherSamples) {
      sumConf += s.confidence;
      sumWind += s.snapshot.windSpeed;
      minComfort = min(minComfort, s.comfortScore);

      if (s.snapshot.precipitation >= 1.0) rainCount++;

      final t = s.snapshot.apparentTemperature.isFinite
          ? s.snapshot.apparentTemperature
          : s.snapshot.temperature;
      if (t <= CyclingConstants.tempExtremelyCold || t >= CyclingConstants.tempExtremelyHot) extremeTempCount++;
    }

    final n = v.weatherSamples.length;
    final kmPerSample = v.lengthKm / max(1, n);
    final rainKm = rainCount * kmPerSample;
    final extremeTempKm = extremeTempCount * kmPerSample;

    return RouteVariantMetrics(
      avgConfidence: sumConf / n,
      avgWind: sumWind / n,
      rainKm: rainKm,
      extremeTempKm: extremeTempKm,
      minComfort: minComfort.isFinite ? minComfort : 0.0,
    );
  }

  RouteExplanation explain({
    required RouteVariant v,
    required Map<RouteVariantKind, RouteVariantMetrics> allMetrics,
  }) {
    final m = allMetrics[v.kind] ?? metricsFor(v);

    final factors = <ExplanationFactor>[];

    // Wind
    if (m.avgWind >= CyclingConstants.windBreezy) {
      final sev = ((m.avgWind - CyclingConstants.windBreezy) / 10.0).clamp(0.0, 1.0);
      factors.add(ExplanationFactor(
        kind: ExplanationFactorKind.wind,
        title: 'Vent',
        detail: 'Vent moyen estimé ~${m.avgWind.toStringAsFixed(1)} m/s',
        severity: sev,
      ));
    }

    // Rain
    if (m.rainKm >= max(CyclingConstants.routeImpactMinDistanceKm, v.lengthKm * CyclingConstants.routeImpactDistanceRatio)) {
      final sev = (m.rainKm / max(1.0, v.lengthKm)).clamp(0.0, 1.0);
      factors.add(ExplanationFactor(
        kind: ExplanationFactorKind.rain,
        title: 'Pluie',
        detail: 'Pluie probable sur ~${m.rainKm.toStringAsFixed(1)} km',
        severity: sev,
      ));
    }

    // Temperature
    if (m.extremeTempKm >= max(CyclingConstants.routeImpactMinDistanceKm, v.lengthKm * CyclingConstants.routeImpactDistanceRatio)) {
      final sev = (m.extremeTempKm / max(1.0, v.lengthKm)).clamp(0.0, 1.0);
      factors.add(ExplanationFactor(
        kind: ExplanationFactorKind.temperature,
        title: 'Température',
        detail: 'Inconfort possible sur ~${m.extremeTempKm.toStringAsFixed(1)} km',
        severity: sev,
      ));
    }

    // Comfort
    if (m.minComfort <= CyclingConstants.comfortThresholdBad) {
      final sev = ((CyclingConstants.comfortThresholdBad - m.minComfort) / CyclingConstants.comfortThresholdBad).clamp(0.0, 1.0);
      factors.add(ExplanationFactor(
        kind: ExplanationFactorKind.comfort,
        title: 'Confort',
        detail: 'Minimum confort ${m.minComfort.toStringAsFixed(1)}/10',
        severity: sev,
      ));
    }

    // Confidence as a factor when low (anti-overtrust)
    String? caveat;
    if (m.avgConfidence < CyclingConstants.comfortThresholdUncertain) {
      caveat = 'Incertitude élevée : ces estimations peuvent varier localement.';
      final sev = ((CyclingConstants.comfortThresholdUncertain - m.avgConfidence) / CyclingConstants.comfortThresholdUncertain).clamp(0.0, 1.0);
      factors.add(ExplanationFactor(
        kind: ExplanationFactorKind.confidence,
        title: 'Fiabilité',
        detail: 'Confiance moyenne ${(m.avgConfidence * 100).round()}%',
        severity: sev,
      ));
    }

    factors.sort((a, b) => b.severity.compareTo(a.severity));

    final headline = _headlineFor(v, m, allMetrics);

    return RouteExplanation(
      kind: v.kind,
      headline: headline,
      caveat: caveat,
      metrics: m,
      factors: factors.take(3).toList(),
    );
  }

  String _headlineFor(RouteVariant v, RouteVariantMetrics m, Map<RouteVariantKind, RouteVariantMetrics> all) {
    final others = all.entries.where((e) => e.key != v.kind).map((e) => e.value).toList();
    if (others.isEmpty) {
      return 'Synthèse météo et fiabilité';
    }

    final avgOtherRain = others.map((x) => x.rainKm).reduce((a, b) => a + b) / others.length;
    final avgOtherWind = others.map((x) => x.avgWind).reduce((a, b) => a + b) / others.length;

    final rainBetter = m.rainKm + 0.6 < avgOtherRain;
    final windBetter = m.avgWind + 0.6 < avgOtherWind;

    if (rainBetter && windBetter) return 'Moins exposée (vent + pluie), à estimation égale';
    if (rainBetter) return 'Moins exposée à la pluie (estimé)';
    if (windBetter) return 'Moins exposée au vent (estimé)';

    if (m.avgConfidence < CyclingConstants.comfortThresholdUncertain) return 'Météo incertaine : prudence recommandée';
    return 'Conditions globales estimées';
  }
}

