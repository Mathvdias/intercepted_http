/// Thrown by [InterceptedHttp] when the server returns a 4xx or 5xx status.
final class HttpClientException implements Exception {
  const HttpClientException({
    required this.statusCode,
    this.message,
    this.body,
    this.data,
  });

  final int statusCode;
  final String? message;
  final String? body;

  /// Decoded JSON body, if the response was JSON. Null otherwise.
  final Object? data;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;

  @override
  String toString() =>
      'HttpClientException(statusCode: $statusCode, message: $message)';
}
