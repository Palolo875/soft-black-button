import 'dart:convert';

import 'package:horizon/services/secure_http_client.dart';

class OpenMeteoAdapter {
  final SecureHttpClient _http;

  OpenMeteoAdapter({SecureHttpClient? httpClient}) : _http = httpClient ?? SecureHttpClient();
  static const _base = 'https://api.open-meteo.com/v1/forecast';

  Future<Map<String, dynamic>> fetchForecast({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
    String? models,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      'latitude': latitude.toStringAsFixed(6),
      'longitude': longitude.toStringAsFixed(6),
      'hourly': [
        'temperature_2m',
        'apparent_temperature',
        'precipitation',
        'relativehumidity_2m',
        'cloudcover',
        'pressure_msl',
        'windspeed_10m',
        'winddirection_10m',
      ].join(','),
      'current_weather': 'true',
      'forecast_days': forecastDays.toString(),
      if (models != null) 'models': models,
    });

    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Open-Meteo HTTP ${response.statusCode}');
    }
    final decoded = json.decode(response.body);
    if (decoded is! Map) throw Exception('Open-Meteo response invalid');
    return Map<String, dynamic>.from(decoded as Map);
  }
}
