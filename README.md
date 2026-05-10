# intercepted_http

A composable interceptor layer for [`package:http`](https://pub.dev/packages/http).  
Add auth headers, logging, token refresh, and retry logic — without replacing your HTTP client.

```dart
final client = InterceptedHttp(
  interceptors: [LoggingInterceptor(), AuthInterceptor()],
);

// Use it like any http.Client
final response = await client.get(Uri.parse('https://api.example.com/users'));
```

## Why

`package:http` is the standard Dart HTTP client, but it has no built-in way to intercept requests. Every project ends up copy-pasting the same boilerplate for auth headers, token refresh, and logging.

`intercepted_http` solves this once with a clean interceptor API that works for Flutter, server-side Dart, and CLI tools — no framework lock-in.

## Installation

```yaml
dependencies:
  intercepted_http: ^0.1.0
```

## Quick start

```dart
import 'package:intercepted_http/intercepted_http.dart';

final client = InterceptedHttp(
  interceptors: [MyInterceptor()],
  timeout: Duration(seconds: 30),
);

final response = await client.get(Uri.parse('https://api.example.com/todos'));
print(response.statusCode);

client.close();
```

## Writing interceptors

Extend `HttpInterceptor` and override only the hooks you need:

```dart
class AuthInterceptor extends HttpInterceptor {
  @override
  Future<void> onRequest(http.Request request) async {
    request.headers['Authorization'] = 'Bearer ${await getToken()}';
  }
}
```

### Available hooks

| Hook | When it runs |
|------|-------------|
| `onRequest` | Before the request is sent. Mutate headers, sign the request. |
| `onResponse` | After every response — any status code. |
| `onError` | Only when `statusCode >= 400`. |
| `shouldRetry` | On network exceptions **or** after `onError`. Return `true` to retry. |

### Token refresh on 401

```dart
class TokenRefreshInterceptor extends HttpInterceptor {
  bool _refreshed = false;

  @override
  Future<void> onError(http.Response response, http.Request request) async {
    if (response.statusCode == 401) {
      final newToken = await refreshToken();         // your refresh logic
      request.headers['Authorization'] = 'Bearer $newToken';
      _refreshed = true;
    }
  }

  @override
  Future<bool> shouldRetry(Object error, StackTrace st, http.Request request,
      {http.Response? response}) async {
    if (response?.statusCode == 401 && _refreshed) {
      _refreshed = false;
      return true;                                   // retry with new token
    }
    return false;
  }
}
```

### Retry on network errors

```dart
class NetworkRetryInterceptor extends HttpInterceptor {
  @override
  Future<bool> shouldRetry(Object error, StackTrace st, http.Request request,
      {http.Response? response}) async {
    return response == null; // only on exceptions, not HTTP errors
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
  Future<void> onResponse(http.Response response, http.Request request) async {
    print('← ${response.statusCode} ${request.url}');
  }
}
```

## Configuration

```dart
InterceptedHttp(
  interceptors: [...],

  // Inner client — use IOClient for mTLS, MockClient for tests
  client: IOClient(),

  // Per-request timeout (default: 30s)
  timeout: Duration(seconds: 30),

  // Max retry attempts per request (default: 1)
  maxRetries: 1,

  // Throw HttpClientException on 4xx/5xx (default: true)
  throwOnError: true,
)
```

## Error handling

When `throwOnError: true` (default), 4xx/5xx responses throw `HttpClientException`:

```dart
try {
  await client.get(Uri.parse('https://api.example.com/users'));
} on HttpClientException catch (e) {
  print(e.statusCode);       // 404
  print(e.message);          // extracted from {"message": "..."}
  print(e.isUnauthorized);   // true if 401
  print(e.isServerError);    // true if >= 500
}
```

Set `throwOnError: false` to handle errors manually via `onError` interceptor.

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

Interceptors run in the order they are listed in the `interceptors` list:

```
[LoggingInterceptor, AuthInterceptor, RetryInterceptor]
     onRequest:  Logging → Auth → Retry
     onResponse: Logging → Auth → Retry
     onError:    Logging → Auth → Retry
     shouldRetry: Logging → Auth → Retry  (first true wins)
```

## License

MIT
