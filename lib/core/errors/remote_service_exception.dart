class RemoteServiceException implements Exception {
  final String service;
  final int? statusCode;
  final String message;

  const RemoteServiceException({
    required this.service,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() {
    final sc = statusCode;
    if (sc != null) {
      return '$service ($sc): $message';
    }
    return '$service: $message';
  }
}
