import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class LocationProvider with ChangeNotifier {
  StreamSubscription<Position>? _sub;

  bool _permissionGranted = false;
  LatLng? _lastPosition;
  double? _lastAccuracyMeters;

  bool get permissionGranted => _permissionGranted;
  LatLng? get lastPosition => _lastPosition;
  double? get lastAccuracyMeters => _lastAccuracyMeters;

  Future<void> ensurePermission() async {
    if (kIsWeb) {
      _permissionGranted = false;
      notifyListeners();
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _permissionGranted = false;
      notifyListeners();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final granted = permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
    if (_permissionGranted != granted) {
      _permissionGranted = granted;
      notifyListeners();
    }

    if (_permissionGranted) {
      startTracking();
    }
  }

  void startTracking({LocationSettings? settings}) {
    if (kIsWeb) return;
    if (!_permissionGranted) return;
    if (_sub != null) return;

    final locationSettings = settings ?? const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 40);

    _sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (p) {
        _lastPosition = LatLng(p.latitude, p.longitude);
        _lastAccuracyMeters = p.accuracy;
        notifyListeners();
      },
      onError: (_) {},
    );
  }

  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<Position> getCurrentPosition({LocationAccuracy accuracy = LocationAccuracy.best}) {
    return Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: accuracy));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
