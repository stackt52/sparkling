import '../models/json.dart';

/// Error parsed from the API-004 envelope
/// `{ "error": { "code", "message", "details", "correlation_id" } }`.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const [],
    this.correlationId,
    this.data,
  });

  /// `unauthenticated` 401, `forbidden` 403, `not_found` 404,
  /// `validation_error` 400, `conflict` 409, `invalid_transition` 409,
  /// `rate_limited` 429, `internal` 500, plus client-side `network` / `timeout`
  /// / `cancelled` / `parse_error`.
  final String code;
  final String message;
  final int? statusCode;
  final List<dynamic> details;
  final String? correlationId;

  /// Raw `error` object (e.g. carries `existing_vehicle_id` on duplicates).
  final Json? data;

  bool get isUnauthenticated => code == 'unauthenticated' || statusCode == 401;
  bool get isForbidden => code == 'forbidden' || statusCode == 403;
  bool get isNotFound => code == 'not_found' || statusCode == 404;
  bool get isValidation => code == 'validation_error';
  bool get isConflict =>
      code == 'conflict' || code == 'invalid_transition' || statusCode == 409;
  bool get isRateLimited => code == 'rate_limited' || statusCode == 429;
  bool get isNetwork => code == 'network' || code == 'timeout';

  /// Safe to retry later (offline queue backoff).
  bool get isRetryable =>
      isNetwork || isRateLimited || (statusCode != null && statusCode! >= 500);

  /// `existing_vehicle_id` on a 409 from `POST /vehicles` (CUS-015).
  String? get existingVehicleId => data?['existing_vehicle_id']?.toString();

  factory ApiException.fromEnvelope(
    dynamic body, {
    int? statusCode,
    String? correlationHeader,
  }) {
    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    final err = map['error'] is Map
        ? Map<String, dynamic>.from(map['error'] as Map)
        : map;
    final code = err['code']?.toString() ?? _codeForStatus(statusCode);
    return ApiException(
      code: code,
      message: err['message']?.toString() ?? _defaultMessage(code),
      statusCode: statusCode,
      details: err['details'] is List
          ? List<dynamic>.from(err['details'] as List)
          : const [],
      correlationId: err['correlation_id']?.toString() ?? correlationHeader,
      data: err,
    );
  }

  factory ApiException.network([String? message]) => ApiException(
    code: 'network',
    message: message ?? 'No connection. Check your network and try again.',
  );

  /// The Sparkling API could not be reached at all (no base URL configured,
  /// connection refused, DNS failure, timeout). Code is always `network` so
  /// apps can show "Couldn't reach Sparkling servers" and offer a retry.
  factory ApiException.unreachable([String? message]) => ApiException(
    code: 'network',
    message: message ?? "Couldn't reach Sparkling servers. Check your connection and try again.",
  );

  factory ApiException.timeout() => const ApiException(
    code: 'timeout',
    message: 'The server took too long to respond. Please try again.',
  );

  factory ApiException.cancelled() =>
      const ApiException(code: 'cancelled', message: 'Request cancelled.');

  static String _codeForStatus(int? status) => switch (status) {
    400 => 'validation_error',
    401 => 'unauthenticated',
    403 => 'forbidden',
    404 => 'not_found',
    409 => 'conflict',
    429 => 'rate_limited',
    _ => status != null && status >= 500 ? 'internal' : 'unknown',
  };

  static String _defaultMessage(String code) => switch (code) {
    'unauthenticated' => 'Please sign in again.',
    'forbidden' => "You don't have permission to do that.",
    'not_found' => 'Not found.',
    'validation_error' => 'Please check the details and try again.',
    'conflict' => 'That change conflicts with the current state.',
    'invalid_transition' => 'That action is not allowed in the current state.',
    'rate_limited' => 'Too many requests. Please slow down.',
    'internal' => 'Something went wrong on our side. Please try again.',
    _ => 'Something went wrong.',
  };

  @override
  String toString() =>
      'ApiException($code${statusCode == null ? '' : ' $statusCode'}): $message';
}
