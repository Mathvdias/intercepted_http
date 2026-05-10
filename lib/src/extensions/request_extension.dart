import 'package:http/http.dart' as http;

extension RequestCopyExtension on http.Request {
  /// Returns a deep copy of this request so it can be safely retried.
  http.Request copyWith() {
    return http.Request(method, url)
      ..encoding = encoding
      ..bodyBytes = bodyBytes
      ..persistentConnection = persistentConnection
      ..followRedirects = followRedirects
      ..maxRedirects = maxRedirects
      ..headers.addAll(headers);
  }
}
