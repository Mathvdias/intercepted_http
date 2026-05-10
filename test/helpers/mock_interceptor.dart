import 'package:http/http.dart' as http;
import 'package:intercepted_http/intercepted_http.dart';

/// Records every call so tests can assert on it.
class RecordingInterceptor extends HttpInterceptor {
  final List<http.Request> requests = [];
  final List<http.Response> responses = [];
  final List<http.Response> errors = [];
  int retryCallCount = 0;
  bool retryResponse = false;

  @override
  Future<void> onRequest(http.Request request) async {
    requests.add(request);
  }

  @override
  Future<void> onResponse(http.Response response, http.Request request) async {
    responses.add(response);
  }

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    errors.add(response);
  }

  @override
  Future<bool> shouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async {
    retryCallCount++;
    return retryResponse;
  }
}

/// Adds a fixed header to every outgoing request.
class HeaderInterceptor extends HttpInterceptor {
  HeaderInterceptor(this.key, this.value);
  final String key;
  final String value;

  @override
  Future<void> onRequest(http.Request request) async {
    request.headers[key] = value;
  }
}

/// Simulates a token refresh on 401.
class TokenRefreshInterceptor extends HttpInterceptor {
  TokenRefreshInterceptor({required this.newToken});
  final String newToken;
  bool refreshed = false;

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    if (response.statusCode == 401) {
      refreshed = true;
      request.headers['Authorization'] = 'Bearer $newToken';
    }
  }

  @override
  Future<bool> shouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async {
    return response?.statusCode == 401 && refreshed;
  }
}
