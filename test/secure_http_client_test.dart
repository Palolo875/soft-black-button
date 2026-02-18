import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/secure_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
