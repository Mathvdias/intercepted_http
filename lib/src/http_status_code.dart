/// HTTP status code constants.
///
/// Use these instead of magic numbers when working with [HttpClientException]:
///
/// ```dart
/// } on HttpClientException catch (e) {
///   if (e.statusCode == HttpStatusCode.unauthorized) { ... }
/// }
/// ```
abstract final class HttpStatusCode {
  // 2xx — Success
  static const int ok = 200;
  static const int created = 201;
  static const int accepted = 202;
  static const int noContent = 204;

  // 3xx — Redirection
  static const int movedPermanently = 301;
  static const int found = 302;
  static const int notModified = 304;

  // 4xx — Client errors
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int conflict = 409;
  static const int gone = 410;
  static const int unprocessableEntity = 422;
  static const int tooManyRequests = 429;

  // 5xx — Server errors
  static const int internalServerError = 500;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
  static const int gatewayTimeout = 504;
}
