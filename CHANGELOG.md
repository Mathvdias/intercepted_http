# Changelog

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
