import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:app/services/weather_service.dart';

class MapProvider with ChangeNotifier {
  MaplibreMapController? _mapController;
  bool _isStyleLoaded = false;
  final WeatherService _weatherService = WeatherService();
  double _timeOffset = 0.0;

  MaplibreMapController? get mapController => _mapController;
  bool get isStyleLoaded => _isStyleLoaded;

  void setController(MaplibreMapController controller) {
    _mapController = controller;
    notifyListeners();
  }

  double get timeOffset => _timeOffset;

  void setTimeOffset(double value) {
    _timeOffset = value;
    _weatherService.updateTimeOffset(value);
    notifyListeners();
  }

  void setStyleLoaded(bool loaded) {
    _isStyleLoaded = loaded;
    if (loaded && _mapController != null) {
      _weatherService.initWeather(_mapController!);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _weatherService.dispose();
    super.dispose();
  }

  void centerOnUser(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 14.0),
    );
  }
}
