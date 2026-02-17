import 'package:maplibre_gl/maplibre_gl.dart';

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

class WeatherPoint {
  final LatLng location;
  final List<WeatherSnapshot> timeline;

  const WeatherPoint({required this.location, required this.timeline});
}

class WeatherDecision {
  final WeatherSnapshot now;
  final double comfortScore;
  final double confidence;

  const WeatherDecision({
    required this.now,
    required this.comfortScore,
    required this.confidence,
  });
}

class RouteWeatherSample {
  final LatLng location;
  final DateTime eta;
  final WeatherSnapshot snapshot;
  final double comfortScore;
  final double confidence;

  const RouteWeatherSample({
    required this.location,
    required this.eta,
    required this.snapshot,
    required this.comfortScore,
    required this.confidence,
  });
}
