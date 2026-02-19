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
double angleDiffDegrees(double a, double b) {
  var d = (a - b) % 360.0;
  if (d < 0) d += 360.0;
  if (d > 180) d = 360.0 - d;
  return d;
}

double bearingDegrees(LatLng a, LatLng b) {
  final lat1 = a.latitude * pi / 180.0;
  final lat2 = b.latitude * pi / 180.0;
  final dLon = (b.longitude - a.longitude) * pi / 180.0;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  final brng = atan2(y, x) * 180.0 / pi;
  var out = (brng + 360.0) % 360.0;
  if (!out.isFinite) out = 0.0;
  return out;
}
