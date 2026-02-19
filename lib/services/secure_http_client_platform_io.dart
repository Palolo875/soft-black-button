import 'dart:io';

HttpClient buildPinnedHttpClient({
  required Duration connectTimeout,
  required List<String> pinnedServerCertificatesPem,
}) {
  final ctx = SecurityContext(withTrustedRoots: false);
  for (final pem in pinnedServerCertificatesPem) {
    ctx.setTrustedCertificatesBytes(pem.codeUnits);
  }

  final c = HttpClient(context: ctx);
  c.connectionTimeout = connectTimeout;
  return c;
}
