import 'package:http/http.dart' as http;

/// Base class for all interceptors.
///
/// Override only the hooks you need. Every method has a no-op default,
/// so you never need to call `super`.
///
/// Execution order:
/// 1. [onRequest]  — before the request is sent
/// 2. [onResponse] — after every response (including 4xx/5xx)
/// 3. [onError]    — only for 4xx/5xx status codes
/// 4. [shouldRetry] — on network/timeout exceptions, or after [onError]
///    returned and you want a second chance
abstract class HttpInterceptor {
  const HttpInterceptor();

  /// Mutate [request] in-place to add headers, sign the request, etc.
  Future<void> onRequest(http.Request request) async {}

  /// Inspect or log the [response]. Called for every status code.
  Future<void> onResponse(
    http.Response response,
    http.Request request,
  ) async {}

  /// Called only when [response.statusCode] >= 400.
  /// Use this to refresh tokens, fire analytics, or update local state.
  Future<void> onError(
    http.Response response,
    http.Request request,
  ) async {}

  /// Return `true` to have [InterceptedHttp] retry the request.
  ///
  /// [response] is non-null when the failure came from a 4xx/5xx.
  /// [response] is null when the failure came from a thrown exception
  /// (e.g. [SocketException], [TimeoutException]).
  Future<bool> shouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async =>
      false;
}
