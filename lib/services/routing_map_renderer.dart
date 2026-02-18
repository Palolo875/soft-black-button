import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:horizon/services/routing_models.dart';

/// Handles MapLibre layer management for route visualizations.
/// 
/// Manages route lines, start/end markers, and weather-contextual segments.
class RoutingMapRenderer {
  const RoutingMapRenderer();

  Future<void> initLayers(MaplibreMapController controller) async {
    try {
      await controller.addSource('route-source', GeojsonSourceProperties(data: _emptyFeatureCollection()));
      await controller.addLineLayer(
        'route-source',
        'route-line',
        const LineLayerProperties(
          lineColor: '#4A90A0',
          lineWidth: 5.0,
          lineOpacity: 0.85,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-weather-segments', GeojsonSourceProperties(data: _emptyFeatureCollection()));
      await controller.addLineLayer(
        'route-weather-segments',
        'route-weather-segments-layer',
        const LineLayerProperties(
          lineWidth: 8.0,
          lineJoin: 'round',
          lineCap: 'round',
          lineColor: [
            'match',
            ['get', 'windKind'],
            'tail', '#88D3A2',
            'cross', '#FFC56E',
            'head', '#B55A5A',
            '#4A90A0',
          ],
          lineOpacity: [
            'interpolate',
            ['linear'],
            ['get', 'confidence'],
            0.25, 0.25,
            0.95, 0.92,
          ],
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-markers', GeojsonSourceProperties(data: _emptyFeatureCollection()));
      await controller.addCircleLayer(
        'route-markers',
        'route-markers-layer',
        const CircleLayerProperties(
          circleRadius: 7.5,
          circleColor: [
            'case',
            ['==', ['get', 'kind'], 'start'],
            '#88D3A2',
            '#B55A5A',
          ],
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.0,
        ),
      );
    } catch (_) {}

    try {
      await controller.addSource('route-weather', GeojsonSourceProperties(data: _emptyFeatureCollection()));
      await controller.addCircleLayer(
        'route-weather',
        'route-weather-layer',
        const CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['zoom'],
            10, 3.0,
            14, 6.0,
          ],
          circleColor: [
            'interpolate',
            ['linear'],
            ['get', 'comfort'],
            1, '#B55A5A',
            5, '#FFC56E',
            10, '#88D3A2',
          ],
          circleOpacity: [
            'interpolate',
            ['linear'],
            ['get', 'confidence'],
            0.25, 0.25,
            0.95, 0.9,
          ],
          circleBlur: 0.15,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 1.2,
        ),
      );
    } catch (_) {}
  }

  Future<void> render({
    required MaplibreMapController? controller,
    required bool styleLoaded,
    required LatLng? start,
    required LatLng? end,
    required RouteVariant? selectedVariant,
    required Map<String, dynamic>? weatherSegmentsGeoJson,
  }) async {
    if (controller == null || !styleLoaded) return;

    // Markers
    final features = <Map<String, Object?>>[];
    if (start != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'start'},
        'geometry': {
          'type': 'Point',
          'coordinates': [start.longitude, start.latitude],
        },
      });
    }
    if (end != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'end'},
        'geometry': {
          'type': 'Point',
          'coordinates': [end.longitude, end.latitude],
        },
      });
    }

    try {
      await controller.setGeoJsonSource('route-markers', {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}

    // Route line
    if (selectedVariant != null) {
      try {
        await controller.setGeoJsonSource('route-source', {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': selectedVariant.shape.map((p) => [p.longitude, p.latitude]).toList(),
          },
        });
      } catch (_) {}

      // Weather samples as dots
      final samples = <Map<String, Object?>>[];
      for (final s in selectedVariant.weatherSamples) {
        samples.add({
          'type': 'Feature',
          'properties': {
            'comfort': s.comfortScore,
            'confidence': s.confidence,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [s.location.longitude, s.location.latitude],
          },
        });
      }
      try {
        await controller.setGeoJsonSource('route-weather', {
          'type': 'FeatureCollection',
          'features': samples,
        });
      } catch (_) {}

      // Weather segments
      if (weatherSegmentsGeoJson != null) {
        try {
          await controller.setGeoJsonSource('route-weather-segments', weatherSegmentsGeoJson);
        } catch (_) {}
      } else {
        try {
          await controller.setGeoJsonSource('route-weather-segments', _emptyFeatureCollection());
        } catch (_) {}
      }
    } else {
      await clear(controller);
    }
  }

  Future<void> clear(MaplibreMapController? controller) async {
    if (controller == null) return;
    try {
      await controller.setGeoJsonSource('route-source', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather-segments', _emptyFeatureCollection());
      await controller.setGeoJsonSource('route-weather', _emptyFeatureCollection());
      // We keep markers unless they are manually cleared
    } catch (_) {}
  }

  Future<void> clearMarkers(MaplibreMapController? controller) async {
    if (controller == null) return;
    try {
      await controller.setGeoJsonSource('route-markers', _emptyFeatureCollection());
    } catch (_) {}
  }

  Map<String, dynamic> _emptyFeatureCollection() => const {
        'type': 'FeatureCollection',
        'features': [],
      };
}
