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

  final double baseLat = 48.8566;
  final double baseLng = 2.3522;

  void initWeather(MaplibreMapController controller) async {
    // Créer les particules initiales
    for (int i = 0; i < 50; i++) {
      _particles.add(WindParticle(
        lat: baseLat + (_random.nextDouble() - 0.5) * 0.1,
        lng: baseLng + (_random.nextDouble() - 0.5) * 0.1,
        speed: 0.0002 + _random.nextDouble() * 0.0003,
        angle: _random.nextDouble() * 2 * pi,
      ));
    }

    await controller.addSource("wind-source", GeojsonSourceProperties(data: _getGeoJson()));

    await controller.addCircleLayer(
      "wind-source",
      "wind-layer",
      const CircleLayerProperties(
        circleRadius: 2.5,
        circleColor: "#ffffff",
        circleOpacity: 0.5,
      ),
    );

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

  void dispose() {
    _animationTimer?.cancel();
  }
}
