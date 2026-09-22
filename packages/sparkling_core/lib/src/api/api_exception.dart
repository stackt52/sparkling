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

  /// 409 `validation_error` `{ reason: 'stale_session' }` from
  /// `POST /auth/password-changed`: the ID token's `auth_time` is older than
  /// 15 minutes — sign in again with the new password and retry.
  bool get isStaleSession {
    final reason = data?['reason'] ?? _detail('reason');
    return reason == 'stale_session';
  }

  /// 409 `validation_error` `{ reason: 'by_quote' }` from `POST /bookings`:
  /// the service is quote-only — route to a quotation request instead.
  bool get isByQuote {
    final reason = data?['reason'] ?? _detail('reason');
    return reason == 'by_quote';
  }

  /// 409 `validation_error` `{ reason: 'cash_disabled' }` from
  /// `POST /bookings`: the `cash_on_collection` flag is off — offer card /
  /// instant EFT instead.
  bool get isCashDisabled => _reason == 'cash_disabled';

  /// 409 `validation_error` `{ reason: 'payment_due', amount_cents,
  /// booking_id, method: 'cash' }` from `POST /work-orders/:id/pickup/verify`:
  /// the cash-on-collection booking is unpaid — record the cash first.
  bool get isPaymentDue => _reason == 'payment_due';

  /// 409 `validation_error` `{ reason: 'not_checked_in', work_order_id }`
  /// from `POST /tasks/:id/assign`: the vehicle has not been checked in yet
  /// — confirm the check-in (`POST /work-orders/:id/checkin`) first.
  bool get isNotCheckedIn => _reason == 'not_checked_in';

  /// `work_order_id` carried by a [isNotCheckedIn] error.
  String? get notCheckedInWorkOrderId =>
      (_detail('work_order_id') ?? data?['work_order_id'])?.toString();

  /// `amount_cents` carried by a [isPaymentDue] error.
  int? get paymentDueCents {
    final v = _detail('amount_cents') ?? data?['amount_cents'];
    return v == null ? null : int.tryParse(v.toString());
  }

  /// `booking_id` carried by a [isPaymentDue] error.
  String? get paymentDueBookingId =>
      (_detail('booking_id') ?? data?['booking_id'])?.toString();

  String? get _reason => (data?['reason'] ?? _detail('reason'))?.toString();

  /// `existing_vehicle_id` on a 409 from `POST /vehicles` (CUS-015).
  String? get existingVehicleId =>
      data?['existing_vehicle_id']?.toString() ??
      _detail('existing_vehicle_id')?.toString();

  /// `details.existing_customer` on a 409 from `POST /staff/customers` — the
  /// customer already registered with that phone / e-mail (STF-012).
  Json? get existingCustomer {
    final raw = _detail('existing_customer') ?? data?['existing_customer'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// Looks [key] up in `details` whether the API sent it as an object
  /// (`details: {existing_customer: …}`) or a list of objects.
  Object? _detail(String key) {
    final d = data?['details'];
    if (d is Map && d[key] != null) return d[key];
    for (final item in details) {
      if (item is Map && item[key] != null) return item[key];
    }
    return null;
  }

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
