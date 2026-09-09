import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/json.dart' as j;
import 'api_exception.dart';

/// Supplies the Firebase ID token for `Authorization: Bearer`.
typedef TokenProvider = Future<String?> Function();

/// Typed dio client for the Sparkling REST API v1 (docs/API.md).
///
/// Every request carries `Authorization`, `X-Correlation-Id`,
/// `X-Client-App` and `X-Client-Version`; mutating helpers add
/// `Idempotency-Key` when given. Errors surface as [ApiException].
class SparklingApi {
  SparklingApi({
    required String baseUrl,
    required TokenProvider tokenProvider,
    required String clientApp,
    required String clientVersion,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 20),
    this.onUnauthenticated,
  }) : dio = dio ?? Dio() {
    _tokenProvider = tokenProvider;
    this.dio.options
      ..baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl
      ..connectTimeout = connectTimeout
      ..receiveTimeout = receiveTimeout
      ..responseType = ResponseType.json
      ..headers = {
        'Accept': 'application/json',
        'X-Client-App': clientApp,
        'X-Client-Version': clientVersion,
      }
      ..validateStatus = (s) => s != null && s >= 200 && s < 300;
    this.dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final Dio dio;
  late final TokenProvider _tokenProvider;

  /// Called on 401 so the app can route to sign-in.
  final void Function()? onUnauthenticated;

  static const Uuid _uuid = Uuid();

  /// New UUID v4 for `client_op_id` / `Idempotency-Key`.
  static String newOpId() => _uuid.v4();

  // ---------------------------------------------------------------------------
  // Interceptors
  // ---------------------------------------------------------------------------

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] != true) {
      final token = await _tokenProvider();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    options.headers.putIfAbsent('X-Correlation-Id', () => _uuid.v4());
    handler.next(options);
  }

  void _onError(DioException e, ErrorInterceptorHandler handler) {
    final ex = _toApiException(e);
    if (ex.isUnauthenticated) onUnauthenticated?.call();
    handler.reject(
      DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        type: e.type,
        error: ex,
        message: ex.message,
      ),
    );
  }

  static ApiException _toApiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException.timeout();
      case DioExceptionType.connectionError:
        return ApiException.network();
      case DioExceptionType.cancel:
        return ApiException.cancelled();
      case DioExceptionType.badCertificate:
        return ApiException.network('Secure connection failed.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final res = e.response;
        if (res == null) return ApiException.network(e.message);
        return ApiException.fromEnvelope(
          res.data,
          statusCode: res.statusCode,
          correlationHeader: res.headers.value('x-correlation-id'),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Low-level helpers
  // ---------------------------------------------------------------------------

  Future<T> _run<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) map,
  ) async {
    try {
      final res = await call();
      return map(res.data);
    } on DioException catch (e) {
      final err = e.error;
      throw err is ApiException ? err : _toApiException(e);
    } on FormatException catch (e) {
      throw ApiException(
        code: 'parse_error',
        message: 'Unexpected response: ${e.message}',
      );
    }
  }

  Options _opts({String? idempotencyKey, bool skipAuth = false}) => Options(
    headers: {'Idempotency-Key': ?idempotencyKey},
    extra: {'skipAuth': skipAuth},
  );

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic) map,
    bool skipAuth = false,
  }) => _run(
    () => dio.get(
      path,
      queryParameters: _clean(query),
      options: _opts(skipAuth: skipAuth),
    ),
    map,
  );

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required T Function(dynamic) map,
    String? idempotencyKey,
    bool skipAuth = false,
  }) => _run(
    () => dio.post(
      path,
      data: body,
      queryParameters: _clean(query),
      options: _opts(idempotencyKey: idempotencyKey, skipAuth: skipAuth),
    ),
    map,
  );

  Future<T> patch<T>(
    String path, {
    Object? body,
    required T Function(dynamic) map,
    String? idempotencyKey,
  }) => _run(
    () => dio.patch(
      path,
      data: body,
      options: _opts(idempotencyKey: idempotencyKey),
    ),
    map,
  );

  Future<T> put<T>(
    String path, {
    Object? body,
    required T Function(dynamic) map,
    String? idempotencyKey,
  }) => _run(
    () => dio.put(
      path,
      data: body,
      options: _opts(idempotencyKey: idempotencyKey),
    ),
    map,
  );

  Future<T> delete<T>(String path, {required T Function(dynamic) map}) =>
      _run(() => dio.delete(path, options: _opts()), map);

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      out[k] = v is bool ? v.toString() : v;
    });
    return out.isEmpty ? null : out;
  }

  static j.Json _obj(dynamic d) => j.asJson(d);
  static List<j.Json> _list(dynamic d) =>
      d is Map && d['data'] is List ? j.asJsonList(d['data']) : j.asJsonList(d);
  static void _void(dynamic _) {}

  // ---------------------------------------------------------------------------
  // Health
  // ---------------------------------------------------------------------------

  Future<j.Json> health() => get('/health', map: _obj, skipAuth: true);

  // ---------------------------------------------------------------------------
  // Auth & profile
  // ---------------------------------------------------------------------------

  /// `POST /auth/session`
  Future<SessionResponse> createSession({
    required String app,
    String? fullName,
    String? phone,
  }) => post(
    '/auth/session',
    body: j.compact({'app': app, 'full_name': fullName, 'phone': phone}),
    map: (d) => SessionResponse.fromJson(_obj(d)),
  );

  /// `GET /me`
  Future<MeResponse> me() =>
      get('/me', map: (d) => MeResponse.fromJson(_obj(d)));

  /// `PATCH /me`
  Future<Profile> updateMe(ProfileUpdate update) => patch(
    '/me',
    body: update.toJson(),
    map: (d) {
      final m = _obj(d);
      return Profile.fromJson(m['profile'] is Map ? _obj(m['profile']) : m);
    },
  );

  /// `POST /devices`
  Future<void> registerDevice(DeviceTokenInput input) =>
      post('/devices', body: input.toJson(), map: _void);

  /// `DELETE /devices/:token`
  Future<void> unregisterDevice(String token) =>
      delete('/devices/${Uri.encodeComponent(token)}', map: _void);

  // ---------------------------------------------------------------------------
  // Catalogue
  // ---------------------------------------------------------------------------

  /// `GET /outlets`
  Future<List<Outlet>> outlets({double? lat, double? lng}) => get(
    '/outlets',
    query: {'lat': lat, 'lng': lng},
    map: (d) => _list(d).map(Outlet.fromJson).toList(),
  );

  /// `GET /outlets/:id/services`
  Future<List<OutletService>> outletServices(String outletId) => get(
    '/outlets/$outletId/services',
    map: (d) {
      final list = _list(d);
      return list
          .map(
            (m) => OutletService.fromJson({
              ...m,
              'outlet_id': m['outlet_id'] ?? outletId,
            }),
          )
          .toList();
    },
  );

  /// `GET /availability?outlet_id&service_id&date`
  Future<List<AvailabilitySlot>> availability({
    required String outletId,
    required String serviceId,
    required DateTime date,
  }) => get(
    '/availability',
    query: {
      'outlet_id': outletId,
      'service_id': serviceId,
      'date': j.isoDate(date),
    },
    map: (d) => _list(d).map(AvailabilitySlot.fromJson).toList(),
  );

  // ---------------------------------------------------------------------------
  // Vehicles
  // ---------------------------------------------------------------------------

  Future<List<Vehicle>> vehicles() =>
      get('/vehicles', map: (d) => _list(d).map(Vehicle.fromJson).toList());

  /// `POST /vehicles` — 409 `conflict` with `existing_vehicle_id` on duplicates (CUS-015).
  Future<Vehicle> createVehicle(VehicleInput input, {String? idempotencyKey}) =>
      post(
        '/vehicles',
        body: input.toJson(),
        idempotencyKey: idempotencyKey,
        map: (d) => Vehicle.fromJson(_obj(d)),
      );

  Future<Vehicle> updateVehicle(String id, VehicleInput input) => patch(
    '/vehicles/$id',
    body: input.toJson(),
    map: (d) => Vehicle.fromJson(_obj(d)),
  );

  /// Soft delete.
  Future<void> deleteVehicle(String id) => delete('/vehicles/$id', map: _void);

  /// `POST /vehicles/parse-disc` (server-side validation; on-device parser is primary).
  Future<j.Json> parseDisc(String raw) =>
      post('/vehicles/parse-disc', body: {'raw': raw}, map: _obj);

  // ---------------------------------------------------------------------------
  // Bookings
  // ---------------------------------------------------------------------------

  Future<Page<Booking>> bookings({
    BookingStatus? status,
    int? limit,
    String? cursor,
    String? outletId,
  }) => get(
    '/bookings',
    query: {
      'status': status?.db,
      'limit': limit,
      'cursor': cursor,
      'outlet_id': outletId,
    },
    map: (d) => Page.fromJson(d, Booking.fromJson),
  );

  Future<Booking> booking(String id) =>
      get('/bookings/$id', map: (d) => Booking.fromJson(_obj(d)));

  /// `POST /bookings` — 409 when the slot is full (CUS-022).
  Future<Booking> createBooking(BookingInput input) => post(
    '/bookings',
    body: input.toJson(),
    idempotencyKey: input.clientOpId,
    map: (d) => Booking.fromJson(_obj(d)),
  );

  Future<Booking> cancelBooking(
    String id, {
    String? reason,
    String? idempotencyKey,
  }) => post(
    '/bookings/$id/cancel',
    body: j.compact({'reason': reason}),
    idempotencyKey: idempotencyKey,
    map: (d) => Booking.fromJson(_obj(d)),
  );

  Future<Booking> rescheduleBooking(
    String id,
    DateTime slotStart, {
    String? idempotencyKey,
  }) => post(
    '/bookings/$id/reschedule',
    body: {'slot_start': j.iso(slotStart)},
    idempotencyKey: idempotencyKey,
    map: (d) => Booking.fromJson(_obj(d)),
  );

  /// `POST /bookings/:id/checkin` (staff) — creates the work order + task.
  Future<Booking> checkinBooking(
    String id, {
    String? bay,
    int? priority,
    String? idempotencyKey,
  }) => post(
    '/bookings/$id/checkin',
    body: j.compact({'bay': bay, 'priority': priority}),
    idempotencyKey: idempotencyKey,
    map: (d) => Booking.fromJson(_obj(d)),
  );

  // ---------------------------------------------------------------------------
  // Quotations
  // ---------------------------------------------------------------------------

  Future<Page<Quotation>> quotations({
    QuotationStatus? status,
    int? limit,
    String? cursor,
    String? outletId,
  }) => get(
    '/quotations',
    query: {
      'status': status?.db,
      'limit': limit,
      'cursor': cursor,
      'outlet_id': outletId,
    },
    map: (d) => Page.fromJson(d, Quotation.fromJson),
  );

  Future<Quotation> quotation(String id) =>
      get('/quotations/$id', map: (d) => Quotation.fromJson(_obj(d)));

  Future<Quotation> createQuotation(QuotationInput input) => post(
    '/quotations',
    body: input.toJson(),
    idempotencyKey: input.clientOpId,
    map: (d) => Quotation.fromJson(_obj(d)),
  );

  Future<Attachment> addQuotationAttachment(String id, AttachmentInput input) =>
      post(
        '/quotations/$id/attachments',
        body: input.toJson(),
        map: (d) => Attachment.fromJson(_obj(d)),
      );

  /// `POST /quotations/:id/quote` (supervisor/manager)
  Future<Quotation> quoteQuotation(
    String id,
    QuoteInput input, {
    String? idempotencyKey,
  }) => post(
    '/quotations/$id/quote',
    body: input.toJson(),
    idempotencyKey: idempotencyKey,
    map: (d) => Quotation.fromJson(_obj(d)),
  );

  /// `POST /quotations/:id/decision` (CUS-033)
  Future<Quotation> decideQuotation(
    String id, {
    required bool accept,
    String? note,
    String? idempotencyKey,
  }) => post(
    '/quotations/$id/decision',
    body: j.compact({'decision': accept ? 'accept' : 'decline', 'note': note}),
    idempotencyKey: idempotencyKey,
    map: (d) => Quotation.fromJson(_obj(d)),
  );

  /// `POST /quotations/:id/convert` (CUS-034)
  Future<Quotation> convertQuotation(String id, {String? idempotencyKey}) =>
      post(
        '/quotations/$id/convert',
        idempotencyKey: idempotencyKey,
        map: (d) => Quotation.fromJson(_obj(d)),
      );

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  Future<List<PaymentMethod>> paymentMethods() => get(
    '/payments/methods',
    map: (d) => _list(d).map(PaymentMethod.fromJson).toList(),
  );

  Future<PaymentMethod> addPaymentMethod(PaymentMethodInput input) => post(
    '/payments/methods',
    body: input.toJson(),
    map: (d) => PaymentMethod.fromJson(_obj(d)),
  );

  /// `POST /payments/intents` → status `pending`.
  Future<PaymentIntentResult> createPaymentIntent({
    required String bookingId,
    String? methodId,
    required String idempotencyKey,
  }) => post(
    '/payments/intents',
    body: j.compact({
      'booking_id': bookingId,
      'method_id': methodId,
      'idempotency_key': idempotencyKey,
    }),
    idempotencyKey: idempotencyKey,
    map: (d) => PaymentIntentResult.fromJson(_obj(d)),
  );

  /// `POST /payments/:id/sandbox-confirm` (flag `payments_sandbox`).
  Future<Payment> sandboxConfirmPayment(String id) => post(
    '/payments/$id/sandbox-confirm',
    map: (d) {
      final m = _obj(d);
      return Payment.fromJson(m['payment'] is Map ? _obj(m['payment']) : m);
    },
  );

  Future<Payment> payment(String id) =>
      get('/payments/$id', map: (d) => Payment.fromJson(_obj(d)));

  // ---------------------------------------------------------------------------
  // Loyalty
  // ---------------------------------------------------------------------------

  Future<LoyaltyAccountSummary> loyaltyAccount() => get(
    '/loyalty/account',
    map: (d) => LoyaltyAccountSummary.fromJson(_obj(d)),
  );

  Future<Page<LedgerEntry>> loyaltyLedger({int? limit, String? cursor}) => get(
    '/loyalty/ledger',
    query: {'limit': limit, 'cursor': cursor},
    map: (d) => Page.fromJson(d, LedgerEntry.fromJson),
  );

  Future<List<Reward>> rewards() => get(
    '/loyalty/rewards',
    map: (d) => _list(d).map(Reward.fromJson).toList(),
  );

  /// `POST /loyalty/rewards/:id/redeem` — idempotent by `Idempotency-Key`.
  Future<RewardRedemption> redeemReward(
    String rewardId, {
    required String idempotencyKey,
  }) => post(
    '/loyalty/rewards/$rewardId/redeem',
    idempotencyKey: idempotencyKey,
    map: (d) => RewardRedemption.fromJson(_obj(d)),
  );

  // ---------------------------------------------------------------------------
  // Staff — tasks & checklists
  // ---------------------------------------------------------------------------

  Future<List<Task>> tasks({required TaskScope scope, String? outletId}) => get(
    '/tasks',
    query: {'scope': scope.name, 'outlet_id': outletId},
    map: (d) => _list(d).map(Task.fromJson).toList(),
  );

  Future<WorkOrderDetail> workOrder(String id) =>
      get('/work-orders/$id', map: (d) => WorkOrderDetail.fromJson(_obj(d)));

  /// `POST /tasks/:id/transition` (STF-023/033)
  Future<Task> transitionTask(String taskId, TaskTransitionInput input) => post(
    '/tasks/$taskId/transition',
    body: input.toJson(),
    idempotencyKey: input.clientOpId,
    map: (d) => Task.fromJson(_obj(d)),
  );

  /// `POST /tasks/:id/assign` (STF-021)
  Future<Task> assignTask(
    String taskId, {
    required String assigneeId,
    String? reason,
    String? idempotencyKey,
  }) => post(
    '/tasks/$taskId/assign',
    body: j.compact({'assignee_id': assigneeId, 'reason': reason}),
    idempotencyKey: idempotencyKey,
    map: (d) => Task.fromJson(_obj(d)),
  );

  /// `POST /work-orders/:id/steps/:key`
  Future<StepResult> submitStep(
    String workOrderId,
    String stepKey,
    StepResultInput input,
  ) => post(
    '/work-orders/$workOrderId/steps/$stepKey',
    body: input.toJson(),
    idempotencyKey: input.clientOpId,
    map: (d) => StepResult.fromJson({
      ..._obj(d),
      'work_order_id': _obj(d)['work_order_id'] ?? workOrderId,
      'step_key': _obj(d)['step_key'] ?? stepKey,
    }),
  );

  /// `POST /sync/batch` (ARC-004)
  Future<List<SyncOperationResult>> syncBatch(List<j.Json> operations) => post(
    '/sync/batch',
    body: {'operations': operations},
    map: (d) {
      final m = d is Map ? _obj(d) : {'results': d};
      final raw = m['results'] ?? m['operations'] ?? m['data'] ?? const [];
      return j.asJsonList(raw).map(SyncOperationResult.fromJson).toList();
    },
  );

  // ---------------------------------------------------------------------------
  // Staff — ops, inventory, gamification
  // ---------------------------------------------------------------------------

  Future<OpsSummary> opsSummary({required String outletId, DateTime? date}) =>
      get(
        '/staff/ops-summary',
        query: {
          'outlet_id': outletId,
          'date': date == null ? null : j.isoDate(date),
        },
        map: (d) => OpsSummary.fromJson(_obj(d)),
      );

  Future<List<StaffMember>> team({required String outletId}) => get(
    '/staff/team',
    query: {'outlet_id': outletId},
    map: (d) => _list(d).map(StaffMember.fromJson).toList(),
  );

  Future<LeaderboardResult> leaderboard({
    required String outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  }) => get(
    '/staff/leaderboard',
    query: {'outlet_id': outletId, 'period': period.name},
    map: (d) => LeaderboardResult.fromJson(_obj(d)),
  );

  Future<List<InventoryItem>> inventory({required String outletId}) => get(
    '/inventory',
    query: {'outlet_id': outletId},
    map: (d) => _list(d).map(InventoryItem.fromJson).toList(),
  );

  /// `POST /inventory/:id/movements` (STF-042/043)
  Future<InventoryItem> addInventoryMovement(
    String itemId,
    InventoryMovementInput input,
  ) => post(
    '/inventory/$itemId/movements',
    body: input.toJson(),
    idempotencyKey: input.clientOpId,
    map: (d) {
      final m = _obj(d);
      return InventoryItem.fromJson(m['item'] is Map ? _obj(m['item']) : m);
    },
  );

  /// `PATCH /inventory/:id` (manager)
  Future<InventoryItem> updateInventoryItem(
    String itemId, {
    double? reorderThreshold,
    String? name,
    String? unit,
  }) => patch(
    '/inventory/$itemId',
    body: j.compact({
      'reorder_threshold': reorderThreshold,
      'name': name,
      'unit': unit,
    }),
    map: (d) => InventoryItem.fromJson(_obj(d)),
  );

  // ---------------------------------------------------------------------------
  // Admin
  // ---------------------------------------------------------------------------

  Future<AdminKpis> adminKpis({
    String? outletId,
    DateTime? from,
    DateTime? to,
  }) => get(
    '/admin/kpis',
    query: {
      'outlet_id': outletId,
      'from': j.isoDate(from),
      'to': j.isoDate(to),
    },
    map: (d) => AdminKpis.fromJson(_obj(d)),
  );

  Future<List<AttentionItem>> adminExceptions({String? outletId}) => get(
    '/admin/exceptions',
    query: {'outlet_id': outletId},
    map: (d) => _list(d).map(AttentionItem.fromJson).toList(),
  );

  Future<List<ActivityItem>> adminActivity({String? outletId, int? limit}) =>
      get(
        '/admin/activity',
        query: {'outlet_id': outletId, 'limit': limit},
        map: (d) => _list(d).map(ActivityItem.fromJson).toList(),
      );

  Future<Page<Booking>> adminBookings({
    String? outletId,
    DateTime? date,
    BookingStatus? status,
    int? limit,
    String? cursor,
  }) => get(
    '/admin/bookings',
    query: {
      'outlet_id': outletId,
      'date': j.isoDate(date),
      'status': status?.db,
      'limit': limit,
      'cursor': cursor,
    },
    map: (d) => Page.fromJson(d, Booking.fromJson),
  );

  Future<List<Outlet>> adminOutlets() =>
      get('/admin/outlets', map: (d) => _list(d).map(Outlet.fromJson).toList());
  Future<Outlet> adminCreateOutlet(j.Json body) =>
      post('/admin/outlets', body: body, map: (d) => Outlet.fromJson(_obj(d)));
  Future<Outlet> adminUpdateOutlet(String id, j.Json body) => patch(
    '/admin/outlets/$id',
    body: body,
    map: (d) => Outlet.fromJson(_obj(d)),
  );

  Future<List<Service>> adminServices() => get(
    '/admin/services',
    map: (d) => _list(d).map(Service.fromJson).toList(),
  );
  Future<Service> adminCreateService(j.Json body) => post(
    '/admin/services',
    body: body,
    map: (d) => Service.fromJson(_obj(d)),
  );
  Future<Service> adminUpdateService(String id, j.Json body) => patch(
    '/admin/services/$id',
    body: body,
    map: (d) => Service.fromJson(_obj(d)),
  );

  /// `PUT /admin/outlets/:id/services/:serviceId` — `{ price_cents?, is_available? }`
  Future<OutletService> adminSetOutletService(
    String outletId,
    String serviceId, {
    int? priceCents,
    bool? isAvailable,
  }) => put(
    '/admin/outlets/$outletId/services/$serviceId',
    body: j.compact({'price_cents': priceCents, 'is_available': isAvailable}),
    map: (d) => OutletService.fromJson({..._obj(d), 'outlet_id': outletId}),
  );

  Future<Page<Profile>> adminUsers({
    UserRole? role,
    String? outletId,
    int? limit,
    String? cursor,
  }) => get(
    '/admin/users',
    query: {
      'role': role?.db,
      'outlet_id': outletId,
      'limit': limit,
      'cursor': cursor,
    },
    map: (d) => Page.fromJson(d, Profile.fromJson),
  );
  Future<Profile> adminInviteUser(AdminUserInput input) => post(
    '/admin/users',
    body: input.toJson(),
    map: (d) => Profile.fromJson(_obj(d)),
  );
  Future<Profile> adminUpdateUser(String id, AdminUserInput input) => patch(
    '/admin/users/$id',
    body: input.toJson(),
    map: (d) => Profile.fromJson(_obj(d)),
  );

  Future<Page<Profile>> adminCustomers({
    String? search,
    int? limit,
    String? cursor,
  }) => get(
    '/admin/customers',
    query: {'search': search, 'limit': limit, 'cursor': cursor},
    map: (d) => Page.fromJson(d, Profile.fromJson),
  );

  /// Access is logged server-side (ADM-024/041). Returns the raw record
  /// (`profile`, `vehicles`, `bookings`, `loyalty_account` …).
  Future<j.Json> adminCustomer(String id) =>
      get('/admin/customers/$id', map: _obj);

  Future<LoyaltyConfigBundle> adminLoyaltyConfig() => get(
    '/admin/loyalty/config',
    map: (d) => LoyaltyConfigBundle.fromJson(_obj(d)),
  );
  Future<LoyaltyConfig> adminSaveLoyaltyDraft(
    LoyaltyConfig draft, {
    String? changeNote,
  }) => put(
    '/admin/loyalty/config/draft',
    body: draft.toDraftJson(changeNote: changeNote),
    map: (d) => LoyaltyConfig.fromJson(_obj(d)),
  );
  Future<LoyaltyConfig> adminPublishLoyaltyConfig({String? idempotencyKey}) =>
      post(
        '/admin/loyalty/config/publish',
        idempotencyKey: idempotencyKey,
        map: (d) => LoyaltyConfig.fromJson(_obj(d)),
      );
  Future<void> adminDiscardLoyaltyDraft() =>
      post('/admin/loyalty/config/discard', map: _void);

  Future<List<InventoryItem>> adminInventory({
    String? outletId,
    bool alertsFirst = true,
  }) => get(
    '/admin/inventory',
    query: {'outlet_id': outletId, 'alerts_first': alertsFirst},
    map: (d) => _list(d).map(InventoryItem.fromJson).toList(),
  );

  Future<List<StaffPerformanceRow>> adminStaffPerformance({
    String? outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  }) => get(
    '/admin/staff/performance',
    query: {'outlet_id': outletId, 'period': period.name},
    map: (d) => _list(d).map(StaffPerformanceRow.fromJson).toList(),
  );

  Future<List<ChecklistTemplate>> adminTemplates() => get(
    '/admin/templates',
    map: (d) => _list(d).map(ChecklistTemplate.fromJson).toList(),
  );
  Future<ChecklistTemplate> adminCreateTemplate(ChecklistTemplate t) => post(
    '/admin/templates',
    body: t.toJson(),
    map: (d) => ChecklistTemplate.fromJson(_obj(d)),
  );
  Future<ChecklistTemplate> adminUpdateTemplate(
    String id,
    ChecklistTemplate t,
  ) => put(
    '/admin/templates/$id',
    body: t.toJson(),
    map: (d) => ChecklistTemplate.fromJson(_obj(d)),
  );

  Future<Page<AuditEvent>> adminAudit({
    String? entityType,
    String? entityId,
    int? limit,
    String? cursor,
  }) => get(
    '/admin/audit',
    query: {
      'entity_type': entityType,
      'entity_id': entityId,
      'limit': limit,
      'cursor': cursor,
    },
    map: (d) => Page.fromJson(d, AuditEvent.fromJson),
  );

  /// `GET /admin/exports/:report.csv` — returns the CSV text (REP-007).
  /// `report ∈ bookings|payments|inventory|staff_performance|loyalty`.
  Future<String> adminExportCsv(
    String report, {
    Map<String, dynamic>? filters,
  }) => _run(
    () => dio.get(
      '/admin/exports/$report.csv',
      queryParameters: _clean(filters),
      options: Options(responseType: ResponseType.plain),
    ),
    (d) => d.toString(),
  );

  Future<List<FeatureFlag>> adminFlags() => get(
    '/admin/flags',
    map: (d) => _list(d).map(FeatureFlag.fromJson).toList(),
  );
  Future<FeatureFlag> adminSetFlag(String key, {required bool enabled}) =>
      patch(
        '/admin/flags/$key',
        body: {'enabled': enabled},
        map: (d) => FeatureFlag.fromJson(_obj(d)),
      );

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<Page<AppNotification>> notifications({int? limit, String? cursor}) =>
      get(
        '/notifications',
        query: {'limit': limit, 'cursor': cursor},
        map: (d) => Page.fromJson(d, AppNotification.fromJson),
      );

  Future<void> markNotificationRead(String id) =>
      post('/notifications/$id/read', map: _void);
}
