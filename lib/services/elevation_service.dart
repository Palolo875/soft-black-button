import 'dart:convert';
import 'package:horizon/services/secure_http_client.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class ElevationService {
  final SecureHttpClient _http;
  static const _base = 'https://api.open-meteo.com/v1/elevation';

  ElevationService({SecureHttpClient? httpClient}) : _http = httpClient ?? SecureHttpClient();

  Future<List<double>> getElevation(List<LatLng> points) async {
    if (points.isEmpty) return [];

    // Open-Meteo supports multiple coordinates in a single request.
    // However, if there are too many (e.g. for a long route), we should batch.
    const batchSize = 100;
    final results = <double>[];

    for (int i = 0; i < points.length; i += batchSize) {
      final chunk = points.sublist(i, (i + batchSize) > points.length ? points.length : (i + batchSize));
      
      final lats = chunk.map((p) => p.latitude.toStringAsFixed(6)).join(',');
      final lons = chunk.map((p) => p.longitude.toStringAsFixed(6)).join(',');

      final uri = Uri.parse(_base).replace(queryParameters: {
        'latitude': lats,
        'longitude': lons,
      });

      final response = await _http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Elevation API HTTP ${response.statusCode}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map || decoded['elevation'] == null) {
        results.addAll(List.filled(chunk.length, 0.0));
      } else {
        results.addAll((decoded['elevation'] as List).cast<num>().map((e) => e.toDouble()));
      }
    }

    return results;
  }
}
