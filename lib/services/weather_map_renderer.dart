import 'dart:ui';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/weather_models.dart';

/// Handles MapLibre layer management for weather visualizations.
/// 
/// Decouples UI/Map rendering from the WeatherProvider business logic.
class WeatherMapRenderer {
  const WeatherMapRenderer();

  Future<void> initLayers(MaplibreMapController controller) async {
    try {
      await controller.addSource('expert-weather', GeojsonSourceProperties(data: _emptyFeatureCollection()));
    } catch (_) {
      // Source might already exist
    }

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-wind-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'windKmh'],
            0, 2.0,
            25, 5.0,
            55, 9.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'windKmh'],
            0, '#ABC9D3',
            25, '#4A90A0',
            55, '#2E2E2E',
          ],
          circleOpacity: 0.55,
          circleBlur: 0.2,
        ),
      );
    } catch (_) {}

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-rain-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'rainMmH'],
            0, 1.0,
            1, 4.0,
            5, 9.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'rainMmH'],
            0, '#ffffff',
            1, '#5AA6B5',
            5, '#2B4C9A',
          ],
          circleOpacity: 0.42,
          circleBlur: 0.35,
        ),
      );
    } catch (_) {}

    try {
      await controller.addCircleLayer(
        'expert-weather',
        'expert-cloud-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'cloudPct'],
            0, 1.0,
            100, 8.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'cloudPct'],
            0, '#B4C6D6',
            100, '#808A94',
          ],
          circleOpacity: 0.28,
          circleBlur: 0.25,
        ),
      );
    } catch (_) {}
  }

  Future<void> render({
    required MaplibreMapController? controller,
    required bool styleLoaded,
    required bool expertWeatherMode,
    required bool expertWindLayer,
    required bool expertRainLayer,
    required bool expertCloudLayer,
    required LatLng? lastPosition,
    required WeatherDecision? decision,
  }) async {
    if (controller == null || !styleLoaded) return;

    if (!expertWeatherMode) {
      try {
        await controller.setGeoJsonSource('expert-weather', _emptyFeatureCollection());
      } catch (_) {}
      return;
    }

    final points = <Map<String, Object?>>[];
    if (lastPosition != null && decision != null) {
      final s = decision.now;
      points.add({
        'type': 'Feature',
        'properties': {
          'windKmh': s.windSpeed * 3.6,
          'rainMmH': s.precipitation,
          'cloudPct': (s.cloudCover * 100).clamp(0, 100),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [lastPosition.longitude, lastPosition.latitude],
        },
      });
    }

    try {
      await controller.setGeoJsonSource('expert-weather', {
        'type': 'FeatureCollection',
        'features': points,
      });
    } catch (_) {}

    try {
      await controller.setPaintProperty('expert-wind-layer', 'circle-opacity', expertWindLayer ? 0.55 : 0.0);
      await controller.setPaintProperty('expert-rain-layer', 'circle-opacity', expertRainLayer ? 0.42 : 0.0);
      await controller.setPaintProperty('expert-cloud-layer', 'circle-opacity', expertCloudLayer ? 0.28 : 0.0);
    } catch (_) {}
  }

  Map<String, dynamic> _emptyFeatureCollection() => const {
        'type': 'FeatureCollection',
        'features': [],
      };
}
