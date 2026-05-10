# intercepted_http

A composable interceptor layer for [`package:http`](https://pub.dev/packages/http).  
Add auth headers, logging, token refresh, and retry logic — without replacing your HTTP client.

```dart
final client = InterceptedHttp(
  interceptors: [LoggingInterceptor(), AuthInterceptor()],
);

// Works exactly like http.Client
final response = await client.get(Uri.parse('https://api.example.com/users'));
```

## Why

`package:http` is the standard Dart HTTP client, but it has no built-in way to intercept requests. Every project ends up copy-pasting the same boilerplate for auth headers, token refresh, and logging.

`intercepted_http` solves this once with a clean interceptor API that works for Flutter, server-side Dart, and CLI tools — no framework lock-in.

## Installation

```yaml
dependencies:
  intercepted_http: ^0.2.0
```

## Quick start

```dart
import 'package:intercepted_http/intercepted_http.dart';

final client = InterceptedHttp(
  interceptors: [MyInterceptor()],
  timeout: const Duration(seconds: 30),
);

final response = await client.get(Uri.parse('https://api.example.com/todos'));
print(response.statusCode);

client.close();
```

## Writing interceptors

Extend `HttpInterceptor` and override only the hooks you need. Every hook has a no-op default, so you never have to call `super`.

```dart
class AuthInterceptor extends HttpInterceptor {
  @override
  Future<void> onRequest(http.Request request) async {
    request.headers['Authorization'] = 'Bearer ${await getToken()}';
  }
}
```

### Available hooks

| Hook | When it runs | Return |
|------|-------------|--------|
| `onRequest` | Before the request is sent. Mutate headers, sign the request. | `void` |
| `onResponse` | After every response — any status code. Can transform the response. | `http.Response` |
| `onError` | Only when `statusCode >= 400`. Refresh tokens, fire analytics. | `void` |
| `shouldRetry` | On network exceptions **or** after `onError`. Return a `Duration` to retry after that delay, `null` to skip. | `Duration?` |

### Token refresh on 401

```dart
class TokenRefreshInterceptor extends HttpInterceptor {
  bool _refreshed = false;

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    if (response.statusCode == HttpStatusCode.unauthorized) {
      final newToken = await refreshToken();
      request.headers['Authorization'] = 'Bearer $newToken';
      _refreshed = true;
    }
  }

  @override
  Future<Duration?> shouldRetry(
    Object error,
    StackTrace st,
    http.Request request, {
    http.Response? response,
  }) async {
    if (response?.statusCode == HttpStatusCode.unauthorized && _refreshed) {
      _refreshed = false;
      return Duration.zero; // retry immediately with the new token
    }
    return null;
  }
}
```

### Retry with exponential backoff

```dart
class NetworkRetryInterceptor extends HttpInterceptor {
  int _attempt = 0;

  @override
  Future<Duration?> shouldRetry(
    Object error,
    StackTrace st,
    http.Request request, {
    http.Response? response,
  }) async {
    if (response != null) return null; // don't retry HTTP errors, only exceptions
    final delay = Duration(milliseconds: 200 * (1 << _attempt));
    _attempt++;
    return delay; // 200ms, 400ms, 800ms, …
  }
}
```

### Response transformation

`onResponse` returns `http.Response`, so interceptors can rewrite the response body. Each interceptor receives the output of the previous one, so transformations compose.

```dart
class UnwrapInterceptor extends HttpInterceptor {
  @override
  Future<http.Response> onResponse(
    http.Response response,
    http.Request request,
  ) async {
    // Unwrap {"data": {...}} envelope from every successful response
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map;
      return http.Response(jsonEncode(json['data']), response.statusCode);
    }
    return response;
  }
}
```

### Logging

```dart
class LoggingInterceptor extends HttpInterceptor {
  @override
  Future<void> onRequest(http.Request request) async {
    print('→ ${request.method} ${request.url}');
  }

  @override
  Future<http.Response> onResponse(
    http.Response response,
    http.Request request,
  ) async {
    print('← ${response.statusCode} ${request.url}');
    return response; // pass through unchanged
  }

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    print('✗ ${response.statusCode} ${request.url} — ${response.body}');
  }
}
```

## Error handling

When `throwOnError: true` (default), 4xx/5xx responses throw `HttpClientException`:

```dart
try {
  await client.get(Uri.parse('https://api.example.com/users'));
} on HttpClientException catch (e) {
  print(e.statusCode);       // 404
  print(e.message);          // extracted from {"message": "..."}
  print(e.body);             // raw response body
  print(e.data);             // decoded JSON body, if any
  print(e.isUnauthorized);   // true if 401
  print(e.isForbidden);      // true if 403
  print(e.isNotFound);       // true if 404
  print(e.isServerError);    // true if >= 500
}
```

Set `throwOnError: false` to handle errors manually via the `onError` hook.

## HTTP status constants

Use `HttpStatusCode` instead of magic numbers:

```dart
if (e.statusCode == HttpStatusCode.unauthorized) { ... }
if (e.statusCode == HttpStatusCode.tooManyRequests) { ... }
```

All common codes from 2xx to 5xx are included.

## Configuration

```dart
InterceptedHttp(
  interceptors: [...],

  // Inner client — use IOClient for mTLS, MockClient for tests
  client: IOClient(),

  // Per-request timeout (default: 30s)
  timeout: const Duration(seconds: 30),

  // Max retry attempts per request (default: 1)
  maxRetries: 3,

  // Throw HttpClientException on 4xx/5xx (default: true)
  throwOnError: true,
)
```

## Using a custom inner client

`InterceptedHttp` wraps any `http.Client`, so you can combine it with mTLS, proxies, or mocks:

```dart
// mTLS
final client = InterceptedHttp(
  client: IOClient(mySecureHttpClient),
  interceptors: [AuthInterceptor()],
);

// Tests
final client = InterceptedHttp(
  client: MockClient((request) async => http.Response('{}', 200)),
  interceptors: [AuthInterceptor()],
);
```

## Interceptor execution order

Interceptors run in the order they are listed:

```
[LoggingInterceptor, AuthInterceptor, RetryInterceptor]

  onRequest:   Logging → Auth → Retry
  onResponse:  Logging → Auth → Retry  (each can transform the response)
  onError:     Logging → Auth → Retry
  shouldRetry: Logging → Auth → Retry  (first non-null Duration wins)
```

## License

MIT
