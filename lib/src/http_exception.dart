import 'package:intercepted_http/src/http_status_code.dart';

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

  bool get isUnauthorized => statusCode == HttpStatusCode.unauthorized;
  bool get isForbidden => statusCode == HttpStatusCode.forbidden;
  bool get isNotFound => statusCode == HttpStatusCode.notFound;
  bool get isServerError => statusCode >= HttpStatusCode.internalServerError;

  @override
  String toString() =>
      'HttpClientException(statusCode: $statusCode, message: $message)';
}
