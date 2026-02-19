import 'package:flutter_test/flutter_test.dart';
import 'package:horizon/services/secure_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _CapturingClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final bytes = await request.finalize().toBytes();
    return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
  }
}

void main() {
  test('blocks non-https by default', () {
    final client = SecureHttpClient(
      inner: MockClient((request) async {
        return http.Response('ok', 200);
      }),
    );

    expect(
      () => client.get(Uri.parse('http://example.com')),
      throwsException,
    );
  });

  test('adds Accept header and preserves custom headers', () async {
    http.BaseRequest? captured;
    final client = SecureHttpClient(
      config: const SecureHttpConfig(allowHttp: true),
      inner: MockClient((request) async {
        captured = request;
        return http.Response('ok', 200);
      }),
    );

    await client.get(
      Uri.parse('http://example.com'),
      headers: const {'X-Test': '1'},
    );

    expect(captured, isNotNull);
    expect(captured!.headers['Accept'], 'application/json');
    expect(captured!.headers['X-Test'], '1');
  });

  test('send() blocks non-https by default', () {
    final inner = _CapturingClient();
    final client = SecureHttpClient(inner: inner);

    final req = http.Request('POST', Uri.parse('http://example.com'))..body = 'hello';
    expect(
      () => client.send(req),
      throwsException,
    );
  });

  test('send() preserves streamed request body and injects Accept header', () async {
    final inner = _CapturingClient();
    final client = SecureHttpClient(
      config: const SecureHttpConfig(allowHttp: true),
      inner: inner,
    );

    final req = http.StreamedRequest('POST', Uri.parse('http://example.com'));
    req.headers['X-Test'] = '1';
    req.sink.add('payload'.codeUnits);
    await req.sink.close();

    final resp = await client.send(req);
    expect(resp.statusCode, 200);
    expect(inner.lastRequest, same(req));
    expect(req.headers['Accept'], 'application/json');
    expect(req.headers['X-Test'], '1');

    final bodyBytes = await resp.stream.toBytes();
    expect(String.fromCharCodes(bodyBytes), 'payload');
  });

  test('send() preserves multipart request body', () async {
    final inner = _CapturingClient();
    final client = SecureHttpClient(
      config: const SecureHttpConfig(allowHttp: true),
      inner: inner,
    );

    final req = http.MultipartRequest('POST', Uri.parse('http://example.com'));
    req.fields['a'] = '1';

    final resp = await client.send(req);
    expect(resp.statusCode, 200);
    expect(inner.lastRequest, same(req));
    expect(req.headers['Accept'], 'application/json');

    final body = String.fromCharCodes(await resp.stream.toBytes());
    expect(body, contains('name="a"'));
    expect(body, contains('1'));
  });
}
