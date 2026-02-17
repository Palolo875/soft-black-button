import 'dart:convert';

import 'package:app/services/secure_http_client.dart';

class MetNoAdapter {
  static const _base = 'https://api.met.no/weatherapi/locationforecast/2.0/compact';

  final SecureHttpClient _http;

  MetNoAdapter({SecureHttpClient? httpClient}) : _http = httpClient ?? SecureHttpClient();

  Future<Map<String, dynamic>> fetchCompact({
    required double latitude,
    required double longitude,
    int? altitude,
    required String userAgent,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      'lat': latitude.toStringAsFixed(6),
      'lon': longitude.toStringAsFixed(6),
      if (altitude != null) 'altitude': altitude.toString(),
    });

    final response = await _http.get(uri, headers: {
      'User-Agent': userAgent,
    });
    if (response.statusCode != 200) {
      throw Exception('Met.no HTTP ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) throw Exception('Met.no response invalid');
    return Map<String, dynamic>.from(decoded as Map);
  }
}
