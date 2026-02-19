import 'dart:async';
import 'dart:math';
import 'package:maplibre_gl/maplibre_gl.dart';

class WindParticle {
  double lat;
  double lng;
  double speed;
  double angle;

  WindParticle({required this.lat, required this.lng, required this.speed, required this.angle});

  void move() {
    lat += speed * sin(angle);
    lng += speed * cos(angle);
  }
}

class WeatherService {
  Timer? _animationTimer;
  final Random _random = Random();
  final List<WindParticle> _particles = [];
  double _timeOffset = 0.0;

  final double baseLat = 48.8566;
  final double baseLng = 2.3522;

  Future<void> initWeather({required MaplibreMapController controller}) async {
    _animationTimer?.cancel();
    _particles.clear();
    // Créer les particules initiales
    for (int i = 0; i < 150; i++) {
      _particles.add(WindParticle(
        lat: baseLat + (_random.nextDouble() - 0.5) * 0.1,
        lng: baseLng + (_random.nextDouble() - 0.5) * 0.1,
        speed: 0.0005 + _random.nextDouble() * 0.0008,
        angle: _random.nextDouble() * 2 * pi,
      ));
    }

    await controller.addSource("wind-source", GeojsonSourceProperties(data: _getGeoJson()));

    await controller.addCircleLayer(
      "wind-source",
      "wind-layer",
      const CircleLayerProperties(
        circleRadius: [
          "interpolate",
          ["linear"],
          ["zoom"],
          5, 1.0,
          12, 4.0
        ],
        circleColor: "#ffffff",
        circleOpacity: 0.4,
        circleBlur: 0.8,
      ),
    );

    _addOpportunities(controller);

    _animationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      for (var p in _particles) {
        p.move();
        // Wrap around
        if ((p.lat - baseLat).abs() > 0.05) p.lat = baseLat - (p.lat - baseLat);
        if ((p.lng - baseLng).abs() > 0.05) p.lng = baseLng - (p.lng - baseLng);
      }
      controller.setGeoJsonSource("wind-source", _getGeoJson());
    });
  }

  Map<String, dynamic> _getGeoJson() {
    return {
      "type": "FeatureCollection",
      "features": _particles.map((p) => {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [p.lng, p.lat]
        }
      }).toList()
    };
  }

  void updateTimeOffset(double offset) {
    // Simuler un changement de direction du vent avec le temps
    double delta = offset - _timeOffset;
    for (var p in _particles) {
      p.angle += delta * 0.5;
      p.speed *= (1.0 + delta * 0.1);
    }
    _timeOffset = offset;
  }

  Future<void> _addOpportunities(MapLibreMapController controller) async {
    final opportunities = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"title": "Point de vue Serein", "type": "view"},
          "geometry": {"type": "Point", "coordinates": [2.3522, 48.86]}
        },
        {
          "type": "Feature",
          "properties": {"title": "Alerte Vent Doux", "type": "weather"},
          "geometry": {"type": "Point", "coordinates": [2.36, 48.85]}
        }
      ]
    };

    await controller.addSource("opp-source", GeojsonSourceProperties(data: opportunities));
    await controller.addCircleLayer(
      "opp-source",
      "opp-layer",
      const CircleLayerProperties(
        circleRadius: 8.0,
        circleColor: "#abc9d3",
        circleStrokeWidth: 2.0,
        circleStrokeColor: "#ffffff",
      ),
    );
  }

  void dispose() {
    _animationTimer?.cancel();
  }
}
