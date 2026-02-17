import 'package:app/services/weather_models.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

enum RouteVariantKind { fast, safe, scenic, imported }

class RouteVariant {
  final RouteVariantKind kind;
  final List<LatLng> shape;
  final double lengthKm;
  final double timeSeconds;
  final List<RouteWeatherSample> weatherSamples;

  const RouteVariant({
    required this.kind,
    required this.shape,
    required this.lengthKm,
    required this.timeSeconds,
    required this.weatherSamples,
  });
}
