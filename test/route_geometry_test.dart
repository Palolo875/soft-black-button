import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/route_geometry.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('haversineMeters is symmetric and zero for identical points', () {
    const a = LatLng(48.8566, 2.3522);
    const b = LatLng(51.5074, -0.1278);

    expect(haversineMeters(a, a), closeTo(0.0, 1e-9));
    expect(haversineMeters(a, b), closeTo(haversineMeters(b, a), 1e-6));
    expect(haversineMeters(a, b), greaterThan(100000));
  });

  test('polylineLengthMeters sums segment lengths', () {
    const a = LatLng(0, 0);
    const b = LatLng(0, 1);
    const c = LatLng(0, 2);

    final ab = haversineMeters(a, b);
    final bc = haversineMeters(b, c);
    final total = polylineLengthMeters(const [a, b, c]);

    expect(total, closeTo(ab + bc, 1e-6));
    expect(polylineLengthMeters(const [a]), 0.0);
    expect(polylineLengthMeters(const <LatLng>[]), 0.0);
  });
}
