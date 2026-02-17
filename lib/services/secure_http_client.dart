import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'secure_http_client_platform.dart'
    if (dart.library.io) 'secure_http_client_platform_io.dart';
import 'secure_http_io_client_stub.dart'
    if (dart.library.io) 'secure_http_io_client_io.dart';

class SecureHttpConfig {
  final Duration connectTimeout;
  final Duration requestTimeout;
  final bool allowHttp;
  final List<String> pinnedServerCertificatesPem;

  const SecureHttpConfig({
    this.connectTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(seconds: 12),
    this.allowHttp = false,
    this.pinnedServerCertificatesPem = const [],
  });

  bool get pinningEnabled => pinnedServerCertificatesPem.isNotEmpty;
}

class SecureHttpClient {
  final SecureHttpConfig config;
  final http.Client _inner;
  final Map<String, http.Client> _clients = {};

  SecureHttpClient({
    this.config = const SecureHttpConfig(),
    http.Client? inner,
  }) : _inner = inner ?? _defaultInner(config);

  static http.Client _defaultInner(SecureHttpConfig cfg) {
    if (kIsWeb) {
      return http.Client();
    }

    if (!cfg.pinningEnabled) {
      return http.Client();
    }

    final httpClient = buildPinnedHttpClient(
      connectTimeout: cfg.connectTimeout,
      pinnedServerCertificatesPem: cfg.pinnedServerCertificatesPem,
    );
    return createIoClient(httpClient);
  }

  http.Client _clientFor(SecureHttpConfig cfg) {
    if (kIsWeb) {
      return _inner;
    }

    if (!cfg.pinningEnabled) {
      return _inner;
    }

    final key = cfg.pinnedServerCertificatesPem.join('\n---\n');
    final existing = _clients[key];
    if (existing != null) return existing;

    final httpClient = buildPinnedHttpClient(
      connectTimeout: cfg.connectTimeout,
      pinnedServerCertificatesPem: cfg.pinnedServerCertificatesPem,
    );
    final c = createIoClient(httpClient);
    _clients[key] = c;
    return c;
  }

  Uri _validate(Uri uri, SecureHttpConfig cfg) {
    if (!cfg.allowHttp && uri.scheme.toLowerCase() != 'https') {
      throw Exception('Blocked non-HTTPS request: $uri');
    }
    return uri;
  }

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    SecureHttpConfig? config,
  }) async {
    final cfg = config ?? this.config;
    final validated = _validate(uri, cfg);
    final h = <String, String>{
      'Accept': 'application/json',
      ...?headers,
    };

    final client = _clientFor(cfg);
    final f = client.get(validated, headers: h);
    return f.timeout(cfg.requestTimeout);
  }

  Future<http.StreamedResponse> send(http.BaseRequest request, {SecureHttpConfig? config}) async {
    final cfg = config ?? this.config;
    final validated = _validate(request.url, cfg);
    final newReq = http.Request(request.method, validated)
      ..headers.addAll(request.headers)
      ..followRedirects = true
      ..maxRedirects = 5;

    if (request is http.Request) {
      newReq.bodyBytes = request.bodyBytes;
    }

    final client = _clientFor(cfg);
    final f = client.send(newReq);
    return f.timeout(cfg.requestTimeout);
  }

  void close() {
    _inner.close();
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
  }
}
