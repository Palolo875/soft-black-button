import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/weather_engine_sota.dart';

void main() {
  test('mapMetNoToOpenMeteoShape maps minimal met.no compact response', () {
    final met = {
      'properties': {
        'timeseries': [
          {
            'time': '2026-01-01T00:00:00Z',
            'data': {
              'instant': {
                'details': {
                  'air_temperature': 10.0,
                  'wind_speed': 5.0,
                  'wind_from_direction': 90.0,
                  'relative_humidity': 50.0,
                  'cloud_area_fraction': 20.0,
                  'air_pressure_at_sea_level': 1013.0,
                },
              },
              'next_1_hours': {
                'details': {
                  'precipitation_amount': 0.7,
                },
              },
            },
          },
        ],
      },
    };

    final out = mapMetNoToOpenMeteoShape(met);
    expect(out, isA<Map<String, dynamic>>());

    final hourly = out['hourly'] as Map<String, dynamic>;
    expect(hourly['time'], ['2026-01-01T00:00:00Z']);
    expect(hourly['temperature_2m'], [10.0]);
    expect(hourly['apparent_temperature'], [10.0]);
    expect(hourly['precipitation'], [0.7]);
    expect(hourly['relativehumidity_2m'], [50.0]);
    expect(hourly['cloudcover'], [20.0]);
    expect(hourly['pressure_msl'], [1013.0]);
    expect(hourly['windspeed_10m'], [5.0]);
    expect(hourly['winddirection_10m'], [90.0]);
  });
}
