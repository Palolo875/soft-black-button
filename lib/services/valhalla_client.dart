import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

class ValhallaRouteResult {
  final List<LatLng> shape;
  final double lengthKm;
  final double timeSeconds;
  final Map<String, dynamic> raw;

  const ValhallaRouteResult({
    required this.shape,
    required this.lengthKm,
    required this.timeSeconds,
    required this.raw,
  });
}

class ValhallaClient {
  final Uri base;

  ValhallaClient({
    Uri? base,
  }) : base = base ?? _defaultBase();

  static Uri _defaultBase() {
    const raw = String.fromEnvironment(
      'VALHALLA_BASE_URL',
      defaultValue: 'https://valhalla1.openstreetmap.de',
    );
    final parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return const Uri(scheme: 'https', host: 'valhalla1.openstreetmap.de');
    }
    if (!parsed.hasScheme) {
      return Uri.parse('https://$raw');
    }
    return parsed;
  }

  Future<ValhallaRouteResult> route({
    required List<LatLng> locations,
    required String costing,
    Map<String, dynamic>? costingOptions,
  }) async {
    final req = <String, dynamic>{
      'locations': locations
          .map((p) => {
                'lat': p.latitude,
                'lon': p.longitude,
                'type': 'break',
              })
          .toList(),
      'costing': costing,
      'directions_options': {
        'units': 'kilometers',
      },
      'shape_format': 'polyline6',
      if (costingOptions != null) 'costing_options': costingOptions,
    };

    final jsonParam = json.encode(req);
    final uri = base.replace(
      path: '/route',
      queryParameters: {
        'json': jsonParam,
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Valhalla HTTP ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) throw Exception('Valhalla invalid response');
    final map = Map<String, dynamic>.from(decoded as Map);
    final trip = map['trip'];
    if (trip is! Map) throw Exception('Valhalla missing trip');

    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) throw Exception('Valhalla missing legs');
    final leg0 = legs.first;
    if (leg0 is! Map) throw Exception('Valhalla leg invalid');

    final shapeEnc = leg0['shape'];
    if (shapeEnc is! String) throw Exception('Valhalla missing shape');

    final summary = trip['summary'];
    if (summary is! Map) throw Exception('Valhalla missing summary');
    final length = summary['length'];
    final time = summary['time'];
    if (length is! num || time is! num) throw Exception('Valhalla invalid summary');

    return ValhallaRouteResult(
      shape: decodePolyline6(shapeEnc),
      lengthKm: length.toDouble(),
      timeSeconds: time.toDouble(),
      raw: map,
    );
  }
}

List<LatLng> decodePolyline6(String encoded) {
  int index = 0;
  int lat = 0;
  int lng = 0;
  final coordinates = <LatLng>[];

  while (index < encoded.length) {
    final latRes = _decodeChunk(encoded, index);
    final dLat = latRes.$1;
    index = latRes.$2;
    lat += dLat;

    final lngRes = _decodeChunk(encoded, index);
    final dLng = lngRes.$1;
    index = lngRes.$2;
    lng += dLng;

    coordinates.add(LatLng(lat / 1e6, lng / 1e6));
  }

  return coordinates;
}

(int, int) _decodeChunk(String encoded, int index) {
  int result = 0;
  int shift = 0;

  while (true) {
    final b = encoded.codeUnitAt(index++) - 63;
    result |= (b & 0x1f) << shift;
    shift += 5;
    if (b < 0x20) break;
  }

  final signed = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  return (signed, index);
}
