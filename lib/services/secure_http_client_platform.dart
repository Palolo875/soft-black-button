Object buildPinnedHttpClient({
  required Duration connectTimeout,
  required List<String> pinnedServerCertificatesPem,
}) {
  throw UnsupportedError('TLS pinning is only supported on IO platforms.');
}
