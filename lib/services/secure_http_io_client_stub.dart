import 'package:http/http.dart' as http;

http.Client createIoClient(Object httpClient) {
  throw UnsupportedError('IOClient is only available on IO platforms.');
}
