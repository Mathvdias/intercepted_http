import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intercepted_http/intercepted_http.dart';
import 'package:test/test.dart';

import 'helpers/mock_interceptor.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

InterceptedHttp _build({
  required http.Client inner,
  List<HttpInterceptor> interceptors = const [],
  int maxRetries = 1,
  bool throwOnError = true,
}) =>
    InterceptedHttp(
      client: inner,
      interceptors: interceptors,
      timeout: const Duration(seconds: 5),
      maxRetries: maxRetries,
      throwOnError: throwOnError,
    );

http.Client _stub(int statusCode, {String body = ''}) =>
    MockClient((_) async => http.Response(body, statusCode));

/// Interceptor that only overrides [onRequest] — leaving [onError] and
/// [shouldRetry] as the base no-op defaults. Used to cover default bodies.
class _RequestOnlyInterceptor extends HttpInterceptor {
  const _RequestOnlyInterceptor();

  @override
  Future<void> onRequest(http.Request request) async {
    request.headers['X-Custom'] = 'yes';
  }
}

class _CloseTrackingClient extends http.BaseClient {
  _CloseTrackingClient({required this.onClose});

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw UnimplementedError();

  @override
  void close() {
    onClose();
    super.close();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── HttpInterceptor default implementations ─────────────────────────────────
  group('HttpInterceptor defaults', () {
    test('onError default is a no-op', () async {
      const interceptor = _RequestOnlyInterceptor();
      await expectLater(
        interceptor.onError(
          http.Response('', 400),
          http.Request('GET', Uri.parse('https://example.com/')),
        ),
        completes,
      );
    });

    test('shouldRetry default returns false', () async {
      const interceptor = _RequestOnlyInterceptor();
      final result = await interceptor.shouldRetry(
        Exception('test'),
        StackTrace.empty,
        http.Request('GET', Uri.parse('https://example.com/')),
      );
      expect(result, isFalse);
    });
  });

  // ── HttpClientException ─────────────────────────────────────────────────────
  group('HttpClientException', () {
    test('isUnauthorized for 401', () {
      expect(const HttpClientException(statusCode: 401).isUnauthorized, isTrue);
      expect(
        const HttpClientException(statusCode: 403).isUnauthorized,
        isFalse,
      );
    });

    test('isForbidden for 403', () {
      expect(const HttpClientException(statusCode: 403).isForbidden, isTrue);
      expect(const HttpClientException(statusCode: 401).isForbidden, isFalse);
    });

    test('isNotFound for 404', () {
      expect(const HttpClientException(statusCode: 404).isNotFound, isTrue);
      expect(const HttpClientException(statusCode: 403).isNotFound, isFalse);
    });

    test('isServerError for 5xx', () {
      expect(const HttpClientException(statusCode: 500).isServerError, isTrue);
      expect(const HttpClientException(statusCode: 503).isServerError, isTrue);
      expect(const HttpClientException(statusCode: 400).isServerError, isFalse);
    });

    test('toString includes statusCode and message', () {
      const e = HttpClientException(statusCode: 422, message: 'Unprocessable');
      expect(e.toString(), contains('422'));
      expect(e.toString(), contains('Unprocessable'));
    });

    test('thrown on 4xx when throwOnError is true', () async {
      final client = _build(inner: _stub(404));
      await expectLater(
        client.get(Uri.parse('https://example.com/')),
        throwsA(
          isA<HttpClientException>()
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('extracts message from JSON body', () async {
      final body = jsonEncode({'message': 'Not found'});
      final client = _build(inner: _stub(404, body: body));
      await expectLater(
        client.get(Uri.parse('https://example.com/')),
        throwsA(
          isA<HttpClientException>()
              .having((e) => e.message, 'message', 'Not found'),
        ),
      );
    });

    test('null message when body is not JSON', () async {
      final client = _build(inner: _stub(400, body: 'plain-text-error'));
      await expectLater(
        client.get(Uri.parse('https://example.com/')),
        throwsA(
          isA<HttpClientException>()
              .having((e) => e.message, 'message', isNull),
        ),
      );
    });

    test('no exception when throwOnError is false', () async {
      final response = await _build(inner: _stub(500), throwOnError: false).get(
        Uri.parse('https://example.com/'),
      );
      expect(response.statusCode, 500);
    });
  });

  // ── InterceptedHttp constructor ─────────────────────────────────────────────
  group('InterceptedHttp constructor', () {
    test('defaults to empty interceptors and http.Client()', () {
      final client = InterceptedHttp();
      expect(client.interceptors, isEmpty);
      client.close();
    });
  });

  // ── send() passthrough for non-http.Request ─────────────────────────────────
  group('send() with non-http.Request', () {
    test('delegates non-http.Request without running interceptors', () async {
      var serverCalled = false;
      final inner = MockClient((_) async {
        serverCalled = true;
        return http.Response('', 200);
      });
      final recorder = RecordingInterceptor();
      final client = _build(inner: inner, interceptors: [recorder]);

      // MultipartRequest is a BaseRequest but not an http.Request
      await client.send(
        http.MultipartRequest('POST', Uri.parse('https://example.com/')),
      );

      expect(serverCalled, isTrue);
      expect(recorder.requests, isEmpty); // interceptors must NOT run
    });
  });

  // ── onRequest ──────────────────────────────────────────────────────────────
  group('onRequest', () {
    test('is called before request is sent', () async {
      final recorder = RecordingInterceptor();
      await _build(
        inner: _stub(200),
        interceptors: [recorder],
      ).get(Uri.parse('https://example.com/'));

      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.first.url.host, 'example.com');
    });

    test('headers mutated in onRequest reach the server', () async {
      http.Request? captured;
      final inner = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      await _build(
        inner: inner,
        interceptors: [HeaderInterceptor('X-Api-Key', 'secret')],
      ).get(Uri.parse('https://example.com/'));

      expect(captured?.headers['X-Api-Key'], 'secret');
    });

    test('multiple interceptors run in list order', () async {
      final order = <String>[];
      final client = _build(
        inner: _stub(200),
        interceptors: [
          _OrderInterceptor('a', order),
          _OrderInterceptor('b', order),
          _OrderInterceptor('c', order),
        ],
      );
      await client.get(Uri.parse('https://example.com/'));
      expect(order, ['a', 'b', 'c']);
    });
  });

  // ── onResponse ─────────────────────────────────────────────────────────────
  group('onResponse', () {
    test('is called for 2xx responses', () async {
      final recorder = RecordingInterceptor();
      await _build(
        inner: _stub(200, body: '{"ok":true}'),
        interceptors: [recorder],
      ).get(Uri.parse('https://example.com/'));

      expect(recorder.responses.single.statusCode, 200);
    });

    test('is called even for 4xx (before onError and before throw)', () async {
      final recorder = RecordingInterceptor();
      await expectLater(
        _build(
          inner: _stub(404),
          interceptors: [recorder],
        ).get(Uri.parse('https://example.com/')),
        throwsA(isA<HttpClientException>()),
      );
      expect(recorder.responses.single.statusCode, 404);
    });
  });

  // ── onError ────────────────────────────────────────────────────────────────
  group('onError', () {
    test('is called for 4xx responses', () async {
      final recorder = RecordingInterceptor();
      await _build(
        inner: _stub(400),
        interceptors: [recorder],
        throwOnError: false,
      ).get(Uri.parse('https://example.com/'));

      expect(recorder.errors.single.statusCode, 400);
    });

    test('is NOT called for 2xx responses', () async {
      final recorder = RecordingInterceptor();
      await _build(
        inner: _stub(200),
        interceptors: [recorder],
      ).get(Uri.parse('https://example.com/'));

      expect(recorder.errors, isEmpty);
    });
  });

  // ── Retry on HTTP errors ────────────────────────────────────────────────────
  group('retry on HTTP errors', () {
    test('retries once when shouldRetry returns true', () async {
      var calls = 0;
      final inner = MockClient((_) async {
        calls++;
        return http.Response('', calls == 1 ? 503 : 200);
      });
      final recorder = RecordingInterceptor()..retryResponse = true;
      final response = await _build(
        inner: inner,
        interceptors: [recorder],
        throwOnError: false,
      ).get(Uri.parse('https://example.com/'));

      expect(calls, 2);
      expect(response.statusCode, 200);
    });

    test('stops retrying after maxRetries', () async {
      var calls = 0;
      final inner = MockClient((_) async {
        calls++;
        return http.Response('', 503);
      });
      await _build(
        inner: inner,
        interceptors: [RecordingInterceptor()..retryResponse = true],
        maxRetries: 2,
        throwOnError: false,
      ).get(Uri.parse('https://example.com/'));

      expect(calls, 3); // 1 original + 2 retries
    });

    test('token refresh — retries 401 with refreshed token in header',
        () async {
      var calls = 0;
      http.Request? lastRequest;
      final inner = MockClient((req) async {
        lastRequest = req;
        calls++;
        return http.Response('', calls == 1 ? 401 : 200);
      });

      await _build(
        inner: inner,
        interceptors: [TokenRefreshInterceptor(newToken: 'new-token-xyz')],
        throwOnError: false,
      ).get(Uri.parse('https://example.com/'));

      expect(calls, 2);
      expect(lastRequest?.headers['Authorization'], 'Bearer new-token-xyz');
    });
  });

  // ── Retry on network exceptions ─────────────────────────────────────────────
  group('retry on network exceptions', () {
    test('retries when shouldRetry returns true after exception', () async {
      var calls = 0;
      final inner = MockClient((_) async {
        calls++;
        if (calls == 1) throw const SocketException('Connection refused');
        return http.Response('ok', 200);
      });
      final recorder = RecordingInterceptor()..retryResponse = true;
      final response = await _build(
        inner: inner,
        interceptors: [recorder],
        throwOnError: false,
      ).get(Uri.parse('https://example.com/'));

      expect(calls, 2);
      expect(response.statusCode, 200);
    });

    test('rethrows exception when shouldRetry returns false', () async {
      final inner =
          MockClient((_) async => throw const SocketException('No network'));
      final client = _build(
        inner: inner,
        interceptors: [RecordingInterceptor()],
      );

      await expectLater(
        client.get(Uri.parse('https://example.com/')),
        throwsA(isA<SocketException>()),
      );
    });
  });

  // ── close() ────────────────────────────────────────────────────────────────
  group('close()', () {
    test('closes the inner client', () {
      var closed = false;
      final client = InterceptedHttp(
        client: _CloseTrackingClient(
          onClose: () {
            closed = true;
          },
        ),
      );
      client.close();
      expect(closed, isTrue);
    });
  });
}

// ── Inline helpers ────────────────────────────────────────────────────────────

class _OrderInterceptor extends HttpInterceptor {
  _OrderInterceptor(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<void> onRequest(http.Request request) async => log.add(name);
}
