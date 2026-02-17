import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

double haversineMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * 0.017453292519943295;
  final lat2 = b.latitude * 0.017453292519943295;
  final dLat = (b.latitude - a.latitude) * 0.017453292519943295;
  final dLon = (b.longitude - a.longitude) * 0.017453292519943295;
  final sinDLat = sin(dLat / 2);
  final sinDLon = sin(dLon / 2);
  final x = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon;
  final c = 2 * atan2(sqrt(x), sqrt(1 - x));
  return r * c;
}

double polylineLengthMeters(List<LatLng> pts) {
  double len = 0.0;
  for (int i = 1; i < pts.length; i++) {
    len += haversineMeters(pts[i - 1], pts[i]);
  }
  return len;
}
