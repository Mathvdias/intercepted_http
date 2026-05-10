import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:intercepted_http/intercepted_http.dart';

// ── 1. Auth interceptor — adds Bearer token, refreshes on 401 ────────────────

class AuthInterceptor extends HttpInterceptor {
  AuthInterceptor({required this.tokenProvider, required this.onRefresh});

  final Future<String> Function() tokenProvider;
  final Future<String> Function() onRefresh;
  bool _refreshed = false;

  @override
  Future<void> onRequest(http.Request request) async {
    final token = await tokenProvider();
    request.headers['Authorization'] = 'Bearer $token';
  }

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    if (response.statusCode == 401) {
      final newToken = await onRefresh();
      request.headers['Authorization'] = 'Bearer $newToken';
      _refreshed = true;
    }
  }

  @override
  Future<bool> shouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async {
    if (response?.statusCode == 401 && _refreshed) {
      _refreshed = false;
      return true;
    }
    return false;
  }
}

// ── 2. Logging interceptor ────────────────────────────────────────────────────

class LoggingInterceptor extends HttpInterceptor {
  @override
  Future<void> onRequest(http.Request request) async {
    log('→ ${request.method} ${request.url}');
  }

  @override
  Future<void> onResponse(http.Response response, http.Request request) async {
    log('← ${response.statusCode} ${request.url}');
  }

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    log('✗ ${response.statusCode} ${request.url} — ${response.body}');
  }
}

// ── 3. Retry on network errors ────────────────────────────────────────────────

class NetworkRetryInterceptor extends HttpInterceptor {
  @override
  Future<bool> shouldRetry(
    Object error,
    StackTrace stackTrace,
    http.Request request, {
    http.Response? response,
  }) async {
    // Retry on timeouts and connection errors, never on HTTP errors
    return response == null;
  }
}

// ── Usage ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  String token = 'initial-token';

  final client = InterceptedHttp(
    interceptors: [
      LoggingInterceptor(),
      AuthInterceptor(
        tokenProvider: () async => token,
        onRefresh: () async {
          token = 'refreshed-token';
          return token;
        },
      ),
      NetworkRetryInterceptor(),
    ],
  );

  try {
    // Works exactly like http.Client
    final response = await client.get(
      Uri.parse('https://jsonplaceholder.typicode.com/todos/1'),
    );

    final data = jsonDecode(response.body);
    log('Got: $data');
  } on HttpClientException catch (e) {
    log('HTTP error ${e.statusCode}: ${e.message}');
  } finally {
    client.close();
  }
}
