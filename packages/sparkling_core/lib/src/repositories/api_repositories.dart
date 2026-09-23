import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../api/api_exception.dart';
import '../api/sparkling_api.dart';
import '../models/models.dart';
import '../offline/connectivity_service.dart';
import '../offline/local_cache.dart';
import '../offline/offline_queue.dart';
import '../realtime/realtime_service.dart';
import 'repositories.dart';

/// Shared plumbing for the API-backed repositories.
abstract class _ApiRepositoryBase {
  _ApiRepositoryBase({
    required this.api,
    this.realtime,
    this.cache,
    this.queue,
    this.connectivity,
    required this.uidProvider,
  });

  final SparklingApi api;
  final RealtimeService? realtime;
  final LocalCache? cache;
  final OfflineQueue? queue;
  final ConnectivityService? connectivity;

  /// Current user id (for realtime filters).
  final String? Function() uidProvider;

  String get uid => uidProvider() ?? '';

  bool get offline => connectivity?.isOffline ?? false;

  /// Emits `fetch()` immediately, then again after every change on [trigger]
  /// (debounced). Falls back to a single emission when realtime is unavailable.
  Stream<T> refetchOn<T>(
    Stream<RealtimeChange>? trigger,
    Future<T> Function() fetch, {
    Duration debounce = const Duration(milliseconds: 250),
  }) {
    late StreamController<T> controller;
    StreamSubscription<RealtimeChange>? sub;
    Timer? timer;

    Future<void> emit() async {
      try {
        final value = await fetch();
        if (!controller.isClosed) controller.add(value);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        unawaited(emit());
        sub = trigger?.listen(
          (_) {
            timer?.cancel();
            timer = Timer(debounce, () => unawaited(emit()));
          },
          onError: (Object e) {
            // Realtime failures must not kill the data stream.
          },
        );
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Runs [call]; on cache hit failure returns cached data. Caches on success.
  Future<T> cached<T>(
    String key,
    Future<T> Function() call, {
    required Object? Function(T) encode,
    required T Function(dynamic) decode,
  }) {
    final c = cache;
    if (c == null) return call();
    return c.remember<T>(key, fetch: call, encode: encode, decode: decode);
  }

  /// Executes [call]; if the device is offline or the call fails with a
  /// retryable network error, enqueues [kind]/[payload] and returns
  /// [optimistic] instead.
  Future<T> queueIfOffline<T>({
    required Future<T> Function() call,
    required String kind,
    required Json payload,
    required String clientOpId,
    required T optimistic,
    String? label,
  }) async {
    final q = queue;
    if (q == null) return call();
    if (offline) {
      await q.enqueue(kind, payload, clientOpId: clientOpId, label: label);
      return optimistic;
    }
    try {
      return await call();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      connectivity?.report(false);
      await q.enqueue(kind, payload, clientOpId: clientOpId, label: label);
      return optimistic;
    }
  }
}

/// Attachment bytes via the API (bearer auth). `demo://` urls only exist on
/// demo data and cannot be fetched live.
Future<Uint8List> _photoBytes(SparklingApi api, String url) {
  if (url.startsWith('demo://')) {
    return Future.error(
      const ApiException(
        code: 'not_found',
        message: 'Demo photo not available in live mode.',
        statusCode: 404,
      ),
    );
  }
  return api.quotationPhotoBytes(url);
}

class ApiCustomerRepository extends _ApiRepositoryBase
    implements CustomerRepository {
  ApiCustomerRepository({
    required super.api,
    super.realtime,
    super.cache,
    super.queue,
    super.connectivity,
    required super.uidProvider,
  });

  @override
  Future<Profile> me() => cached(
    'me',
    () async => (await api.me()).profile,
    encode: (p) => p.toJson(),
    decode: (d) => Profile.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<Profile> updateMe(ProfileUpdate update) async {
    final p = await api.updateMe(update);
    await cache?.put('me', p.toJson());
    return p;
  }

  @override
  Future<List<Vehicle>> vehicles() => cached(
    'vehicles',
    api.vehicles,
    encode: (l) => l.map((v) => v.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => Vehicle.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );

  @override
  Future<Vehicle> addVehicle(VehicleInput input) =>
      api.createVehicle(input, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<Vehicle> updateVehicle(String id, VehicleInput input) =>
      api.updateVehicle(id, input);

  @override
  Future<void> deleteVehicle(String id) => api.deleteVehicle(id);

  @override
  Future<List<Booking>> bookings({BookingStatus? status}) => cached(
    'bookings:${status?.db ?? 'all'}',
    () async => (await api.bookings(status: status, limit: 50)).items,
    encode: (l) => l.map((b) => b.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => Booking.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );

  @override
  Future<Booking> booking(String id) => cached(
    'booking:$id',
    () => api.booking(id),
    encode: (b) => b.toJson(),
    decode: (d) => Booking.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<Booking> createBooking(BookingInput input) => api.createBooking(input);

  @override
  Future<Booking> cancelBooking(String id, {String? reason}) =>
      api.cancelBooking(
        id,
        reason: reason,
        idempotencyKey: SparklingApi.newOpId(),
      );

  @override
  Future<Booking> rescheduleBooking(String id, DateTime slotStart) => api
      .rescheduleBooking(id, slotStart, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<List<Quotation>> quotations() async =>
      (await api.quotations(limit: 50)).items;

  @override
  Future<Quotation> quotation(String id) => api.quotation(id);

  @override
  Future<Quotation> createQuotation(QuotationInput input) =>
      api.createQuotation(input);

  @override
  Future<Quotation> decideQuotation(
    String id, {
    required bool accept,
    String? note,
  }) => api.decideQuotation(
    id,
    accept: accept,
    note: note,
    idempotencyKey: SparklingApi.newOpId(),
  );

  @override
  Future<Uint8List> quotationPdf(String id) => api.quotationPdf(id);

  @override
  Future<Uint8List> photoBytes(String url) => _photoBytes(api, url);

  @override
  Future<List<PaymentMethod>> paymentMethods() => api.paymentMethods();

  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required String bookingId,
    String? methodId,
  }) => api.createPaymentIntent(
    bookingId: bookingId,
    methodId: methodId,
    idempotencyKey: SparklingApi.newOpId(),
  );

  @override
  Future<Payment> confirmSandboxPayment(String paymentId) =>
      api.sandboxConfirmPayment(paymentId);

  @override
  Future<Payment> payment(String id) => api.payment(id);

  @override
  Stream<List<Booking>> watchBookings({BookingStatus? status}) => refetchOn(
    realtime?.customerBookings(uid),
    () => bookings(status: status),
  );

  @override
  Stream<Booking> watchBooking(String id) {
    final rt = realtime;
    Stream<RealtimeChange>? trigger;
    if (rt != null) {
      final c = StreamController<RealtimeChange>.broadcast();
      final subs = <StreamSubscription<RealtimeChange>>[];
      c
        ..onListen = () {
          subs.add(rt.booking(id).listen(c.add));
          subs.add(rt.customerWorkOrders(uid).listen(c.add));
          subs.add(rt.allStepResults().listen(c.add));
          subs.add(rt.customerPayments(uid).listen(c.add));
        }
        ..onCancel = () async {
          for (final s in subs) {
            await s.cancel();
          }
        };
      trigger = c.stream;
    }
    return refetchOn(trigger, () => booking(id));
  }

  @override
  Stream<List<Vehicle>> watchVehicles() => refetchOn(
    realtime?.watchTable('vehicles', filterColumn: 'customer_id', value: uid),
    vehicles,
  );

  @override
  Stream<List<Quotation>> watchQuotations() =>
      refetchOn(realtime?.customerQuotations(uid), quotations);
}

class ApiConfigRepository extends _ApiRepositoryBase
    implements ConfigRepository {
  ApiConfigRepository({required super.api, super.cache})
    : super(uidProvider: () => null);

  static const String cacheKey = 'app_config';

  AppConfig? _current;
  Future<AppConfig>? _inFlight;

  @override
  AppConfig? get current => _current;

  @override
  Future<AppConfig> config({bool force = false}) {
    final have = _current;
    if (have != null && !force) return Future.value(have);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<AppConfig> _fetch() async {
    try {
      final cfg = await api.config();
      _current = cfg;
      await cache?.put(cacheKey, cfg.toJson());
      return cfg;
    } catch (_) {
      // Unreachable: last known config from disk, else safe defaults. Not
      // stored in [_current] so the next call retries the API.
      final cached = cache?.getObject(cacheKey, AppConfig.fromJson);
      return cached?.data ?? AppConfig.defaults;
    }
  }
}

class ApiCatalogueRepository extends _ApiRepositoryBase
    implements CatalogueRepository {
  ApiCatalogueRepository({
    required super.api,
    super.cache,
    required super.uidProvider,
  });

  @override
  Future<List<Outlet>> outlets({double? lat, double? lng}) => cached(
    'outlets',
    () => api.outlets(lat: lat, lng: lng),
    encode: (l) => l.map((o) => o.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => Outlet.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );

  @override
  Future<Outlet?> outlet(String id) async =>
      (await outlets()).where((o) => o.id == id).firstOrNull;

  @override
  Future<OutletCatalogue> outletServices(
    String outletId, {
    VehicleSize? vehicleSize,
  }) => cached(
    'outlet_services:$outletId:${vehicleSize?.db ?? 'any'}',
    () => api.outletServices(outletId, vehicleSize: vehicleSize),
    encode: (c) => c.toJson(),
    decode: (d) => OutletCatalogue.fromJson(
      Map<String, dynamic>.from(d as Map),
      outletId: outletId,
    ),
  );

  @override
  Future<List<AvailabilitySlot>> availability({
    required String outletId,
    required String serviceId,
    required DateTime date,
  }) => api.availability(outletId: outletId, serviceId: serviceId, date: date);
}

class ApiLoyaltyRepository extends _ApiRepositoryBase
    implements LoyaltyRepository {
  ApiLoyaltyRepository({
    required super.api,
    super.realtime,
    super.cache,
    required super.uidProvider,
  });

  @override
  Future<LoyaltyAccountSummary> account() => cached(
    'loyalty:account',
    api.loyaltyAccount,
    encode: (a) => a.toJson(),
    decode: (d) =>
        LoyaltyAccountSummary.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<Page<LedgerEntry>> ledger({int? limit, String? cursor}) =>
      api.loyaltyLedger(limit: limit, cursor: cursor);

  @override
  Future<List<Reward>> rewards() => cached(
    'loyalty:rewards',
    api.rewards,
    encode: (l) => l.map((r) => r.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => Reward.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );

  @override
  Future<RewardRedemption> redeem(String rewardId) =>
      api.redeemReward(rewardId, idempotencyKey: SparklingApi.newOpId());

  @override
  Stream<LoyaltyAccountSummary> watchAccount() =>
      refetchOn(realtime?.loyaltyActivity(uid), account);

  @override
  Stream<List<LedgerEntry>> watchLedger() => refetchOn(
    realtime?.loyaltyLedger(uid),
    () async => (await ledger(limit: 50)).items,
  );
}

class ApiMembershipRepository extends _ApiRepositoryBase
    implements MembershipRepository {
  ApiMembershipRepository({
    required super.api,
    super.realtime,
    super.cache,
    required super.uidProvider,
  });

  @override
  Future<MembershipPlanList> plans() => cached(
    'membership:plans',
    api.membershipPlans,
    encode: (p) => p.toJson(),
    decode: (d) =>
        MembershipPlanList.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<MembershipSummary> me() => cached(
    'membership:me',
    api.membershipMe,
    encode: (m) => m.toJson(),
    decode: (d) =>
        MembershipSummary.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<SubscribeResult> subscribe({
    required String planCode,
    required Map<String, String> selections,
    required String clientOpId,
  }) => api.subscribeMembership(
    planCode: planCode,
    selections: selections,
    clientOpId: clientOpId,
  );

  @override
  Future<PaymentIntentResult> payInvoice(String invoiceId) => api
      .payMembershipInvoice(invoiceId, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<MembershipSummary> changeSelections(Map<String, String> selections) =>
      api.updateMembershipSelections(selections);

  @override
  Future<SubscribeResult> changePlan({
    required String planCode,
    required Map<String, String> selections,
  }) => api.changeMembershipPlan(
    planCode: planCode,
    selections: selections,
    idempotencyKey: SparklingApi.newOpId(),
  );

  @override
  Future<MembershipSummary> cancel({bool atPeriodEnd = true}) =>
      api.cancelMembership(atPeriodEnd: atPeriodEnd);

  @override
  Stream<MembershipSummary> watchMe() =>
      refetchOn(realtime?.membershipActivity(uid), api.membershipMe);
}

class ApiStaffRepository extends _ApiRepositoryBase implements StaffRepository {
  ApiStaffRepository({
    required super.api,
    super.realtime,
    super.cache,
    super.queue,
    super.connectivity,
    required super.uidProvider,
  }) {
    _deferredSub = queue?.changes.listen((_) => unawaited(_uploadDeferred()));
  }

  StreamSubscription<List<QueuedOperation>>? _deferredSub;
  final Set<String> _deferredInFlight = {};

  static String _deferredKey(String clientOpId) =>
      'deferred_photos:$clientOpId';

  /// Damage photos kept locally for queued `quotation.raise` operations are
  /// uploaded (best effort, sequentially) once the server has applied the
  /// operation and handed back the quotation id.
  Future<void> _uploadDeferred() async {
    final q = queue;
    final c = cache;
    if (q == null || c == null) return;
    for (final op in q.all) {
      if (op.kind != SyncKinds.quotationRaise ||
          op.status != QueuedOpStatus.succeeded) {
        continue;
      }
      final key = _deferredKey(op.clientOpId);
      final entry = c.get(key);
      if (entry == null || _deferredInFlight.contains(op.clientOpId)) continue;
      final quotationId =
          op.result?['id']?.toString() ??
          (op.result?['quotation'] is Map
              ? (op.result!['quotation'] as Map)['id']?.toString()
              : null);
      if (quotationId == null) continue;
      _deferredInFlight.add(op.clientOpId);
      try {
        final photos = (entry.data as List? ?? const [])
            .map(
              (m) =>
                  DeferredPhoto.fromJson(Map<String, dynamic>.from(m as Map)),
            )
            .toList();
        for (final p in photos) {
          try {
            final file = File(p.path);
            if (!file.existsSync()) continue;
            await api.uploadQuotationPhoto(
              quotationId,
              path: p.path,
              caption: p.caption,
            );
          } on ApiException catch (e) {
            if (e.isNetwork) return; // try again on the next queue change
            // Rejected (too large / limit reached): skip this photo.
          }
        }
        await c.remove(key);
        await cache?.remove('quotation:$quotationId');
      } finally {
        _deferredInFlight.remove(op.clientOpId);
      }
    }
  }

  /// Stops the deferred-photo listener (tests).
  Future<void> dispose() async => _deferredSub?.cancel();

  @override
  Future<Attachment> uploadStepPhoto(
    String workOrderId, {
    required String stepKey,
    Uint8List? bytes,
    String? path,
  }) => api.uploadWorkOrderPhoto(
    workOrderId,
    stepKey: stepKey,
    bytes: bytes,
    path: path,
  );

  @override
  Future<void> setAvailability(AvailabilityStatus status) =>
      api.setAvailability(status);

  @override
  Future<List<Task>> tasks({required TaskScope scope, String? outletId}) =>
      cached(
        'tasks:${scope.name}:${outletId ?? ''}',
        () => api.tasks(scope: scope, outletId: outletId),
        encode: (l) => l.map((t) => t.toJson()).toList(),
        decode: (d) => (d as List)
            .map((m) => Task.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );

  @override
  Future<WorkOrderDetail> workOrder(String id) => cached(
    'work_order:$id',
    () => api.workOrder(id),
    encode: (w) => w.toJson(),
    decode: (d) =>
        WorkOrderDetail.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<Task> transitionTask(Task task, TaskTransitionInput input) {
    final now = DateTime.now();
    final optimistic = task.copyWith(
      status: input.to,
      blockedReason: input.to == WorkStatus.blocked ? input.reason : null,
      clearBlockedReason: input.to != WorkStatus.blocked,
      startedAt: input.to == WorkStatus.inProgress
          ? (task.startedAt ?? now)
          : null,
      completedAt: input.to == WorkStatus.completed ? now : null,
      updatedAt: now,
      workOrder: task.workOrder?.copyWith(
        status: input.to,
        blockedReason: input.reason,
        clearBlockedReason: input.to != WorkStatus.blocked,
      ),
    );
    return queueIfOffline(
      call: () => api.transitionTask(task.id, input),
      kind: SyncKinds.taskTransition,
      payload: {'task_id': task.id, ...input.toJson()},
      clientOpId: input.clientOpId,
      optimistic: optimistic,
      label: '${task.ref}: ${input.to.label}',
    );
  }

  @override
  Future<Task> assignTask(
    Task task, {
    required String assigneeId,
    String? reason,
  }) {
    final opId = SparklingApi.newOpId();
    return queueIfOffline(
      call: () => api.assignTask(
        task.id,
        assigneeId: assigneeId,
        reason: reason,
        idempotencyKey: opId,
      ),
      kind: SyncKinds.taskAssign,
      payload: {
        'task_id': task.id,
        'assignee_id': assigneeId,
        'reason': reason,
      },
      clientOpId: opId,
      optimistic: task.copyWith(
        assigneeId: assigneeId,
        status: task.status == WorkStatus.queued
            ? WorkStatus.assigned
            : task.status,
      ),
      label: 'Assign ${task.ref}',
    );
  }

  @override
  Future<StepResult> submitStep(
    String workOrderId,
    String stepKey,
    StepResultInput input,
  ) {
    final optimistic = StepResult(
      workOrderId: workOrderId,
      stepKey: stepKey,
      status: input.status,
      value: input.value,
      attachmentId: input.attachmentId,
      actorId: uid,
      note: input.note,
      clientOpId: input.clientOpId,
      completedAt: input.status == StepStatus.done ? DateTime.now() : null,
      updatedAt: DateTime.now(),
      pendingSync: true,
    );
    return queueIfOffline(
      call: () => api.submitStep(workOrderId, stepKey, input),
      kind: SyncKinds.stepResult,
      payload: {
        'work_order_id': workOrderId,
        'step_key': stepKey,
        ...input.toJson(),
      },
      clientOpId: input.clientOpId,
      optimistic: optimistic,
      label: 'Step $stepKey: ${input.status.db}',
    );
  }

  @override
  Future<Booking> checkinBooking(
    String bookingId, {
    String? bay,
    int? priority,
  }) => api.checkinBooking(
    bookingId,
    bay: bay,
    priority: priority,
    idempotencyKey: SparklingApi.newOpId(),
  );

  @override
  Future<WorkOrderCheckInResult> checkInWorkOrder(
    String workOrderId, {
    String? bay,
  }) async {
    final result = await api.checkInWorkOrder(
      workOrderId,
      bay: bay,
      idempotencyKey: SparklingApi.newOpId(),
    );
    // The cached detail carries the old `checked_in_at`; drop it so the next
    // open reflects the check-in even before realtime catches up.
    await cache?.remove('work_order:$workOrderId');
    return result;
  }

  @override
  Future<PickupVerifyResult> verifyPickupOtp(String workOrderId, String otp) =>
      api.verifyPickupOtp(workOrderId, otp);

  @override
  Future<void> resendPickupOtp(String workOrderId) =>
      api.resendPickupOtp(workOrderId);

  @override
  Future<List<Booking>> outletBookings({
    required String outletId,
    BookingStatus? status,
  }) async => (await api.bookings(
    outletId: outletId,
    status: status,
    limit: 100,
  )).items;

  @override
  Future<List<CustomerSummary>> searchCustomers(String query, {int? limit}) =>
      api.searchCustomers(query, limit: limit);

  @override
  Future<CustomerSummary> createCustomer(CustomerInput input) =>
      api.createCustomer(input);

  @override
  Future<Vehicle> createCustomerVehicle(
    String customerId,
    VehicleInput input, {
    bool force = false,
  }) => api.createCustomerVehicle(customerId, input, force: force);

  @override
  Future<Booking> createWalkInBooking(WalkInBookingInput input) {
    final now = DateTime.now();
    final start = input.slotStart ?? now;
    final optimistic = Booking(
      id: 'pending_${input.clientOpId}',
      ref: 'Pending sync',
      customerId: input.customerId,
      status: BookingStatus.confirmed,
      slotStart: start,
      slotEnd: start.add(const Duration(minutes: 30)),
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      serviceId: input.serviceId,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      pendingSync: true,
    );
    return queueIfOffline(
      call: () => api.createWalkInBooking(input),
      kind: SyncKinds.bookingCreateWalkIn,
      payload: input.toJson(),
      clientOpId: input.clientOpId,
      optimistic: optimistic,
      label: 'Walk-in booking${input.checksIn ? ' + check-in' : ''}',
    );
  }

  @override
  Future<Payment> recordPayment(RecordPaymentInput raw) {
    // A booking id of `pending_<op>` means the walk-in itself is still in the
    // queue — carry its op id so the batch can resolve the server row.
    // Quotation payments (`quotation_id`) always target a server row.
    final bookingId = raw.bookingId;
    final input = bookingId != null && bookingId.startsWith('pending_')
        ? raw.copyWith(
            bookingClientOpId: bookingId.substring('pending_'.length),
          )
        : raw;
    final now = DateTime.now();
    final optimistic = Payment(
      id: 'pending_${input.idempotencyKey}',
      bookingId: input.bookingId,
      quotationId: input.quotationId,
      customerId: '',
      provider: 'pos',
      amountCents: input.amountCents,
      status: PaymentStatus.pending,
      idempotencyKey: input.idempotencyKey,
      createdAt: now,
      updatedAt: now,
      pendingSync: true,
    );
    return queueIfOffline(
      call: () => api.recordPayment(input),
      kind: SyncKinds.paymentRecord,
      payload: input.toJson(),
      clientOpId: input.idempotencyKey,
      optimistic: optimistic,
      label:
          '${input.method.label} payment ${Money.formatZar(input.amountCents)}',
    );
  }

  @override
  Future<MembershipSummary> customerMembership(String customerId) =>
      api.staffCustomerMembership(customerId);

  @override
  Future<MembershipSummary> enrolMembership(EnrolMembershipInput input) {
    final now = DateTime.now();
    final optimistic = MembershipSummary(
      membership: Membership(
        id: 'pending_${input.clientOpId}',
        ref: 'Pending sync',
        customerId: input.customerId,
        planId: '',
        planCode: input.planCode,
        status: MembershipStatus.active,
        startedAt: now,
        currentPeriodStart: now,
        paymentMethod: input.paymentMethod.stored,
        clientOpId: input.clientOpId,
        createdAt: now,
        updatedAt: now,
        pendingSync: true,
      ),
      selections: input.selections,
    );
    return queueIfOffline(
      call: () => api.staffEnrolMembership(input),
      kind: SyncKinds.membershipEnrol,
      payload: input.toJson(),
      clientOpId: input.clientOpId,
      optimistic: optimistic,
      label: 'Enrol in ${input.planCode} plan (${input.paymentMethod.label})',
    );
  }

  @override
  Future<MembershipSummary> recordMembershipInvoicePayment({
    required String membershipId,
    required String invoiceId,
    required CounterPaymentMethod method,
    required String clientOpId,
  }) => api.staffRecordMembershipInvoicePayment(
    membershipId: membershipId,
    invoiceId: invoiceId,
    method: method,
    clientOpId: clientOpId,
  );

  @override
  Future<OpsSummary> opsSummary({required String outletId}) => cached(
    'ops:$outletId',
    () => api.opsSummary(outletId: outletId),
    encode: (o) => o.toJson(),
    decode: (d) => OpsSummary.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<List<StaffMember>> team({required String outletId}) =>
      api.team(outletId: outletId);

  @override
  Future<LeaderboardResult> leaderboard({
    required String outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  }) => cached(
    'leaderboard:$outletId:${period.name}',
    () => api.leaderboard(outletId: outletId, period: period),
    encode: (l) => l.toJson(),
    decode: (d) =>
        LeaderboardResult.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<List<Quotation>> quotations({String? outletId}) async =>
      (await api.quotations(outletId: outletId, limit: 100)).items;

  @override
  Future<Quotation> quotation(String id) => cached(
    'quotation:$id',
    () => api.quotation(id),
    encode: (q) => q.toJson(),
    decode: (d) => Quotation.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  @override
  Future<Quotation> quoteQuotation(String id, QuoteInput input) =>
      api.quoteQuotation(id, input, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<Quotation> convertQuotation(String id) =>
      api.convertQuotation(id, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<Quotation> raiseQuotation(
    StaffQuotationInput input, {
    List<DeferredPhoto> deferredPhotos = const [],
  }) async {
    final now = DateTime.now();
    final optimistic = Quotation(
      id: 'pending_${input.clientOpId}',
      ref: 'Pending sync',
      customerId: input.customerId,
      vehicleId: input.vehicleId,
      outletId: input.outletId,
      category: input.category,
      description: input.description,
      status: QuotationStatus.quoted,
      amountCents: input.totalCents,
      lineItems: input.items.map((i) => i.toLineItem()).toList(),
      assessorId: uid,
      validUntil: input.validUntil,
      quotedAt: now,
      itemsNote: input.itemsNote,
      clientOpId: input.clientOpId,
      createdAt: now,
      updatedAt: now,
      pendingSync: true,
    );
    // Photos travel with the queued op only locally (never in the batch).
    if (deferredPhotos.isNotEmpty && queue != null) {
      await cache?.put(
        _deferredKey(input.clientOpId),
        deferredPhotos.map((p) => p.toJson()).toList(),
      );
    }
    final result = await queueIfOffline(
      call: () => api.raiseQuotation(input),
      kind: SyncKinds.quotationRaise,
      payload: input.toJson(),
      clientOpId: input.clientOpId,
      optimistic: optimistic,
      label: 'Quote ${Money.formatZar(input.totalCents)}',
    );
    if (!result.pendingSync) {
      await cache?.remove(_deferredKey(input.clientOpId));
    }
    return result;
  }

  @override
  Future<Attachment> uploadQuotationPhoto(
    String quotationId,
    Uint8List bytes, {
    String? caption,
    String? mimeType,
    String? filename,
  }) async {
    final a = await api.uploadQuotationPhoto(
      quotationId,
      bytes: bytes,
      caption: caption,
      mimeType: mimeType,
      filename: filename,
    );
    await cache?.remove('quotation:$quotationId');
    return a;
  }

  @override
  Future<void> deleteQuotationPhoto(
    String quotationId,
    String attachmentId,
  ) async {
    await api.deleteQuotationPhoto(quotationId, attachmentId);
    await cache?.remove('quotation:$quotationId');
  }

  @override
  Future<SharedQuoteLink> shareQuotation(String quotationId) =>
      api.shareQuotation(quotationId);

  @override
  Future<Uint8List> quotationPdf(String quotationId) =>
      api.quotationPdf(quotationId);

  @override
  Future<Uint8List> photoBytes(String url) => _photoBytes(api, url);

  @override
  Stream<List<Quotation>> watchQuotations({String? outletId}) {
    final rt = realtime;
    Stream<RealtimeChange>? trigger;
    if (rt != null) {
      trigger = rt.watchTable(
        'quotations',
        filterColumn: outletId == null ? null : 'outlet_id',
        value: outletId,
      );
    }
    return refetchOn(trigger, () => quotations(outletId: outletId));
  }

  @override
  Stream<List<Task>> watchTasks({required TaskScope scope, String? outletId}) {
    final rt = realtime;
    Stream<RealtimeChange>? trigger;
    if (rt != null && outletId != null) trigger = rt.outletActivity(outletId);
    return refetchOn(trigger, () => tasks(scope: scope, outletId: outletId));
  }

  @override
  Stream<WorkOrderDetail> watchWorkOrder(String id) {
    final rt = realtime;
    Stream<RealtimeChange>? trigger;
    if (rt != null) {
      final c = StreamController<RealtimeChange>.broadcast();
      final subs = <StreamSubscription<RealtimeChange>>[];
      c
        ..onListen = () {
          subs.add(rt.workOrder(id).listen(c.add));
          subs.add(rt.stepResults(id).listen(c.add));
        }
        ..onCancel = () async {
          for (final s in subs) {
            await s.cancel();
          }
        };
      trigger = c.stream;
    }
    return refetchOn(trigger, () => workOrder(id));
  }

  @override
  Stream<OpsSummary> watchOpsSummary({required String outletId}) => refetchOn(
    realtime?.outletActivity(outletId),
    () => opsSummary(outletId: outletId),
  );
}

class ApiInventoryRepository extends _ApiRepositoryBase
    implements InventoryRepository {
  ApiInventoryRepository({
    required super.api,
    super.realtime,
    super.cache,
    super.queue,
    super.connectivity,
    required super.uidProvider,
  });

  @override
  Future<List<InventoryItem>> items({required String outletId}) => cached(
    'inventory:$outletId',
    () => api.inventory(outletId: outletId),
    encode: (l) => l.map((i) => i.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => InventoryItem.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
  );

  @override
  Future<InventoryItem> logMovement(
    InventoryItem item,
    InventoryMovementInput input,
  ) {
    final newOnHand = (item.onHand + input.delta)
        .clamp(0, double.infinity)
        .toDouble();
    return queueIfOffline(
      call: () => api.addInventoryMovement(item.id, input),
      kind: SyncKinds.inventoryMovement,
      payload: {'item_id': item.id, ...input.toJson()},
      clientOpId: input.clientOpId,
      optimistic: item.copyWith(onHand: newOnHand, updatedAt: DateTime.now()),
      label: '${item.name}: ${input.reason.db} ${input.delta}',
    );
  }

  @override
  Future<InventoryItem> updateItem(
    String id, {
    double? reorderThreshold,
    String? name,
    String? unit,
  }) => api.updateInventoryItem(
    id,
    reorderThreshold: reorderThreshold,
    name: name,
    unit: unit,
  );

  @override
  Stream<List<InventoryItem>> watchItems({required String outletId}) {
    final rt = realtime;
    Stream<RealtimeChange>? trigger;
    if (rt != null) {
      final c = StreamController<RealtimeChange>.broadcast();
      final subs = <StreamSubscription<RealtimeChange>>[];
      c
        ..onListen = () {
          subs.add(rt.outletInventoryItems(outletId).listen(c.add));
          subs.add(rt.outletInventoryAlerts(outletId).listen(c.add));
        }
        ..onCancel = () async {
          for (final s in subs) {
            await s.cancel();
          }
        };
      trigger = c.stream;
    }
    return refetchOn(trigger, () => items(outletId: outletId));
  }
}

class ApiNotificationsRepository extends _ApiRepositoryBase
    implements NotificationsRepository {
  ApiNotificationsRepository({
    required super.api,
    super.realtime,
    super.cache,
    required super.uidProvider,
  });

  @override
  Future<Page<AppNotification>> list({int? limit, String? cursor}) =>
      api.notifications(limit: limit, cursor: cursor);

  @override
  Future<void> markRead(String id) => api.markNotificationRead(id);

  @override
  Future<int> unreadCount() async =>
      (await list(limit: 50)).items.where((n) => !n.isRead).length;

  @override
  Stream<List<AppNotification>> watch() => refetchOn(
    realtime?.notifications(uid),
    () async => (await list(limit: 50)).items,
  );
}
