# Changelog

## 0.2.1

- README updated to reflect v0.2.0 API (`Duration?` shouldRetry, `http.Response` onResponse, `HttpStatusCode` constants, response transformation and exponential backoff examples).

## 0.2.0

**Breaking changes**

- `HttpInterceptor.shouldRetry` now returns `Future<Duration?>` instead of
  `Future<bool>`. Return `null` to skip retry, `Duration.zero` to retry
  immediately, or any positive `Duration` to retry after a delay. This enables
  exponential backoff and other delay strategies without extra packages.
- `HttpInterceptor.onResponse` now returns `Future<http.Response>` instead of
  `Future<void>`. The default implementation returns the response unchanged.
  Interceptors can now replace the response (e.g. unwrap API envelopes) and
  each interceptor in the list receives the output of the previous one.

**Other changes**

- `InterceptedHttp` maxRetries doc updated to reflect `Duration?` semantics.
- Example updated with exponential backoff and response logging patterns.
- All magic status numbers in library code replaced with `HttpStatusCode` constants.

## 0.1.1

- Added `HttpStatusCode` — named constants for all common HTTP status codes (2xx–5xx).
- `HttpClientException` getters (`isUnauthorized`, `isForbidden`, `isNotFound`, `isServerError`) now reference `HttpStatusCode` instead of magic numbers.
- `HttpStatusCode` is exported from the main barrel so consumers can use it directly.

## 0.1.0

- Initial release.
- `InterceptedHttp` — drop-in `http.Client` wrapper with interceptor support.
- `HttpInterceptor` — base class with `onRequest`, `onResponse`, `onError`, `shouldRetry`.
- `HttpClientException` — typed exception for 4xx/5xx responses with JSON message extraction.
- Configurable timeout, max retries, and inner client.
