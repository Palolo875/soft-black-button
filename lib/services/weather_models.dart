import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:horizon/services/comfort_model.dart';

class WeatherSnapshot {
  final DateTime timestamp;
  final double temperature;
  final double apparentTemperature;
  final double windSpeed;
  final double windDirection;
  final double precipitation;
  final double humidity;
  final double cloudCover;
  final double pressure;

  const WeatherSnapshot({
    required this.timestamp,
    required this.temperature,
    required this.apparentTemperature,
    required this.windSpeed,
    required this.windDirection,
    required this.precipitation,
    required this.humidity,
    required this.cloudCover,
    required this.pressure,
  });
}

enum RelativeWindKind {
  head,
  tail,
  cross,
}

class WeatherPoint {
  final LatLng location;
  final List<WeatherSnapshot> timeline;

  const WeatherPoint({required this.location, required this.timeline});
}

class WeatherDecision {
  final WeatherSnapshot now;
  final double comfortScore;
  final double confidence;
  final ComfortBreakdown? comfortBreakdown;

  const WeatherDecision({
    required this.now,
    required this.comfortScore,
    required this.confidence,
    this.comfortBreakdown,
  });
}

class RouteWeatherSample {
  final LatLng location;
  final DateTime eta;
  final WeatherSnapshot snapshot;
  final double comfortScore;
  final double confidence;
  final ComfortBreakdown? comfortBreakdown;
  final double headingDegrees;
  final RelativeWindKind relativeWindKind;
  final double headwindness;
  final double crosswindness;
  final double relativeWindImpact;

  const RouteWeatherSample({
    required this.location,
    required this.eta,
    required this.snapshot,
    required this.comfortScore,
    required this.confidence,
    this.comfortBreakdown,
    this.headingDegrees = 0.0,
    this.relativeWindKind = RelativeWindKind.cross,
    this.headwindness = 0.0,
    this.crosswindness = 0.0,
    this.relativeWindImpact = 0.0,
  });
}
