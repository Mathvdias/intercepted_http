# Changelog

## 0.1.0

- Initial release.
- `InterceptedHttp` — drop-in `http.Client` wrapper with interceptor support.
- `HttpInterceptor` — base class with `onRequest`, `onResponse`, `onError`, `shouldRetry`.
- `HttpClientException` — typed exception for 4xx/5xx responses with JSON message extraction.
- Configurable timeout, max retries, and inner client.
