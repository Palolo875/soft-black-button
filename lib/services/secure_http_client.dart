import 'dart:async';

import 'package:http/http.dart' as http;

class SecureHttpConfig {
  final Duration connectTimeout;
  final Duration requestTimeout;
  final bool allowHttp;

  const SecureHttpConfig({
    this.connectTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(seconds: 12),
    this.allowHttp = false,
  });
}

class SecureHttpClient {
  final SecureHttpConfig config;
  final http.Client _inner;

  SecureHttpClient({
    this.config = const SecureHttpConfig(),
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

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

    final f = _inner.get(validated, headers: h);
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

    final f = _inner.send(newReq);
    return f.timeout(cfg.requestTimeout);
  }

  void close() {
    _inner.close();
  }
}
