import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intercepted_http/src/extensions/request_extension.dart';
import 'package:intercepted_http/src/http_exception.dart';
import 'package:intercepted_http/src/http_interceptor.dart';

/// An [http.BaseClient] that pipes every request through a list of
/// [HttpInterceptor]s before and after network I/O.
///
/// Drop-in replacement for [http.Client]: pass it to any code that already
/// accepts an [http.Client].
///
/// ```dart
/// final client = InterceptedHttp(
///   interceptors: [AuthInterceptor(), LoggingInterceptor()],
///   timeout: Duration(seconds: 30),
/// );
///
/// final response = await client.get(Uri.parse('https://api.example.com/users'));
/// ```
final class InterceptedHttp extends http.BaseClient {
  InterceptedHttp({
    List<HttpInterceptor>? interceptors,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 1,
    this.throwOnError = true,
  })  : interceptors = interceptors ?? const [],
        _inner = client ?? http.Client();

  final List<HttpInterceptor> interceptors;
  final http.Client _inner;

  /// Request timeout. Defaults to 30 seconds.
  final Duration timeout;

  /// Maximum number of retries when an interceptor's [shouldRetry] returns
  /// true. Defaults to 1 to prevent runaway loops.
  final int maxRetries;

  /// When true (default), throws [HttpClientException] on 4xx/5xx responses.
  /// Set to false to handle error responses manually.
  final bool throwOnError;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      return _inner.send(request);
    }
    return _sendWithRetry(request, retryCount: 0);
  }

  Future<http.StreamedResponse> _sendWithRetry(
    http.Request request, {
    required int retryCount,
  }) async {
    final snapshot = request.copyWith();
    http.Response? response;

    try {
      for (final interceptor in interceptors) {
        await interceptor.onRequest(request);
      }

      final streamed = await _inner.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);

      for (final interceptor in interceptors) {
        await interceptor.onResponse(response, request);
      }

      if (response.statusCode >= 400) {
        for (final interceptor in interceptors) {
          await interceptor.onError(response, request);
        }

        if (retryCount < maxRetries) {
          final shouldRetry = await _checkShouldRetry(
            HttpClientException(
              statusCode: response.statusCode,
              body: response.body,
            ),
            StackTrace.current,
            request,
            response: response,
          );
          if (shouldRetry) {
            // Use the current request: onError interceptors may have mutated
            // headers (e.g. new auth token) that must reach the server.
            return _sendWithRetry(request.copyWith(),
                retryCount: retryCount + 1,);
          }
        }

        if (throwOnError) {
          throw HttpClientException(
            statusCode: response.statusCode,
            body: response.body,
            data: _tryDecodeJson(response.body),
            message: _tryExtractMessage(response.body),
          );
        }
      }

      return _responseToStreamed(response);
    } catch (error, stackTrace) {
      if (error is HttpClientException) rethrow;

      if (retryCount < maxRetries) {
        final shouldRetry = await _checkShouldRetry(
          error,
          stackTrace,
          snapshot,
          response: response,
        );
        if (shouldRetry) {
          return _sendWithRetry(snapshot.copyWith(),
              retryCount: retryCount + 1,);
        }
      }

      rethrow;
    }
  }

  Future<bool> _checkShouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async {
    for (final interceptor in interceptors) {
      if (await interceptor.shouldRetry(
        error,
        stackTrace,
        request,
        response: response,
      )) {
        return true;
      }
    }
    return false;
  }

  static http.StreamedResponse _responseToStreamed(http.Response response) {
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
      contentLength: response.contentLength,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
    );
  }

  static Object? _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String? _tryExtractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded['message']?.toString();
    } catch (_) {}
    return null;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
