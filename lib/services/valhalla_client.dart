import 'dart:async';
import 'dart:convert';

import 'package:horizon/core/constants/horizon_constants.dart';
import 'package:horizon/core/errors/remote_service_exception.dart';
import 'package:horizon/core/log/app_log.dart';
import 'package:horizon/services/secure_http_client.dart';
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
  final SecureHttpClient _http;
  final List<String> _pinsPem;
  final bool _allowHttp;
  final Duration _requestTimeout;
  final int _maxAttempts;

  ValhallaClient({
    Uri? base,
    SecureHttpClient? httpClient,
    bool allowHttp = const bool.fromEnvironment('VALHALLA_ALLOW_HTTP', defaultValue: false),
    Duration requestTimeout = const Duration(seconds: 20),
    int maxAttempts = 2,
  })  : base = base ?? _defaultBase(),
        _http = httpClient ?? SecureHttpClient(),
        _pinsPem = _loadPinsPem(),
        _allowHttp = allowHttp,
        _requestTimeout = requestTimeout,
        _maxAttempts = maxAttempts;

  static List<String> _loadPinsPem() {
    const raw = String.fromEnvironment('VALHALLA_TLS_PINS_B64', defaultValue: '');
    if (raw.trim().isEmpty) return const [];
    final parts = raw.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final out = <String>[];
    for (final p in parts) {
      try {
        final bytes = base64.decode(p);
        out.add(utf8.decode(bytes));
      } catch (e, st) {
        AppLog.w('valhalla.tlsPins decode failed', error: e, stackTrace: st);
      }
    }
    return out;
  }

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

    final jsonBody = json.encode(req);
    final routePath = (base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path) + '/route';
    final postUri = base.replace(path: routePath, queryParameters: const {});

    final response = await _requestWithRetry(
      () => _http.postJson(
        postUri,
        body: jsonBody,
        config: SecureHttpConfig(
          requestTimeout: _requestTimeout,
          allowHttp: _allowHttp,
          pinnedServerCertificatesPem: _pinsPem,
        ),
      ),
      fallback: () {
        final getUri = base.replace(
          path: routePath,
          queryParameters: {
            'json': jsonBody,
          },
        );
        return _http.get(
          getUri,
          config: SecureHttpConfig(
            requestTimeout: _requestTimeout,
            allowHttp: _allowHttp,
            pinnedServerCertificatesPem: _pinsPem,
          ),
        );
      },
    );

    if (response.statusCode != 200) {
      final msg = _extractValhallaErrorMessage(response);
      throw RemoteServiceException(
        service: 'Valhalla',
        statusCode: response.statusCode,
        message: msg ?? 'Service de routage indisponible.',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Réponse du service de routage invalide.');
    }
    final map = Map<String, dynamic>.from(decoded as Map);
    final trip = map['trip'];
    if (trip is! Map) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Réponse du service de routage incomplète.');
    }

    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Route introuvable.');
    }
    final leg0 = legs.first;
    if (leg0 is! Map) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Route introuvable.');
    }

    final shapeEnc = leg0['shape'];
    if (shapeEnc is! String) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Route introuvable.');
    }

    final summary = trip['summary'];
    if (summary is! Map) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Réponse du service de routage incomplète.');
    }
    final length = summary['length'];
    final time = summary['time'];
    if (length is! num || time is! num) {
      throw const RemoteServiceException(service: 'Valhalla', message: 'Réponse du service de routage incomplète.');
    }

    return ValhallaRouteResult(
      shape: decodePolyline6(shapeEnc),
      lengthKm: length.toDouble(),
      timeSeconds: time.toDouble(),
      raw: map,
    );
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    Future<http.Response> Function()? fallback,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await request();
      } catch (e, st) {
        lastError = e;
        if (fallback != null) {
          try {
            return await fallback();
          } catch (e2, st2) {
            lastError = e2;
            AppLog.w('valhalla.request failed', error: e2, stackTrace: st2, props: {'attempt': attempt + 1});
          }
        } else {
          AppLog.w('valhalla.request failed', error: e, stackTrace: st, props: {'attempt': attempt + 1});
        }
        if (attempt < _maxAttempts - 1) {
          final backoffMs = 250 * (1 << attempt);
          await Future.delayed(Duration(milliseconds: backoffMs));
        }
      }
    }
    throw RemoteServiceException(
      service: 'Valhalla',
      message: 'Service de routage indisponible.',
    );
  }

  String? _extractValhallaErrorMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded as Map);
      final err = m['error'];
      if (err is String && err.trim().isNotEmpty) return err;
      final msg = m['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
      return null;
    } catch (_) {
      return null;
    }
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

    coordinates.add(LatLng(lat / HorizonConstants.polyline6Precision, lng / HorizonConstants.polyline6Precision));
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
