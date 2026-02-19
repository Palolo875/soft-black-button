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
  double _currentCenterLat = 0.0;
  double _currentCenterLng = 0.0;

  final double baseLat = 48.8566;
  final double baseLng = 2.3522;

  Future<void> initWeather({
    required MaplibreMapController controller,
    double? initialLat,
    double? initialLng,
    double windSpeed = 5.0, // km/h
    double windAngleRad = 0.0,
  }) async {
    final lat = initialLat ?? baseLat;
    final lng = initialLng ?? baseLng;
    _currentCenterLat = lat;
    _currentCenterLng = lng;
    
    _animationTimer?.cancel();
    _particles.clear();
    // Créer les particules initiales
    // Créer les particules initiales basées sur le vent réel
    for (int i = 0; i < 150; i++) {
      final speedFactor = 0.0001 * (windSpeed / 10.0).clamp(0.5, 3.0);
      _particles.add(WindParticle(
        lat: lat + (_random.nextDouble() - 0.5) * 0.1,
        lng: lng + (_random.nextDouble() - 0.5) * 0.1,
        speed: speedFactor + _random.nextDouble() * 0.0002,
        angle: windAngleRad + (_random.nextDouble() - 0.5) * 0.2, // Variation légère
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
        if ((p.lat - _currentCenterLat).abs() > 0.1) p.lat = _currentCenterLat - (p.lat - _currentCenterLat);
        if ((p.lng - _currentCenterLng).abs() > 0.1) p.lng = _currentCenterLng - (p.lng - _currentCenterLng);
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

  void updateWithRealWind(double speedKmh, double angleRad) {
    for (var p in _particles) {
      p.angle = angleRad + (_random.nextDouble() - 0.5) * 0.2;
      p.speed = 0.0001 * (speedKmh / 10.0).clamp(0.5, 3.0) + _random.nextDouble() * 0.0002;
    }
  }

  void updateTimeOffset(double offset) {
    _timeOffset = offset;
  }

  Future<void> _addOpportunities(MaplibreMapController controller) async {
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

  void move(double lat, double lng) {
    _currentCenterLat = lat;
    _currentCenterLng = lng;
  }

  void dispose() {
    _animationTimer?.cancel();
  }
}
