import 'dart:convert';
import 'package:horizon/services/secure_http_client.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class GeocodingResult {
  final String name;
  final LatLng location;
  final String? country;
  final String? admin1;

  const GeocodingResult({
    required this.name,
    required this.location,
    this.country,
    this.admin1,
  });
}

class GeocodingService {
  final SecureHttpClient _http;
  static const _base = 'https://geocoding-api.open-meteo.com/v1/search';

  GeocodingService({SecureHttpClient? httpClient}) : _http = httpClient ?? SecureHttpClient();

  Future<List<GeocodingResult>> search(String query, {int count = 5}) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(_base).replace(queryParameters: {
      'name': query,
      'count': count.toString(),
      'language': 'fr',
      'format': 'json',
    });

    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Geocoding API HTTP ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map || decoded['results'] == null) return [];

    final results = decoded['results'] as List;
    return results.map((r) {
      return GeocodingResult(
        name: r['name'] as String,
        location: LatLng(r['latitude'] as double, r['longitude'] as double),
        country: r['country'] as String?,
        admin1: r['admin1'] as String?,
      );
    }).toList();
  }
}
