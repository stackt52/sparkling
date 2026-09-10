import 'dart:async';

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
  Future<List<OutletService>> outletServices(String outletId) => cached(
    'outlet_services:$outletId',
    () => api.outletServices(outletId),
    encode: (l) => l.map((s) => s.toJson()).toList(),
    decode: (d) => (d as List)
        .map((m) => OutletService.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
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
      refetchOn(realtime?.loyaltyLedger(uid), account);

  @override
  Stream<List<LedgerEntry>> watchLedger() => refetchOn(
    realtime?.loyaltyLedger(uid),
    () async => (await ledger(limit: 50)).items,
  );
}

class ApiStaffRepository extends _ApiRepositoryBase implements StaffRepository {
  ApiStaffRepository({
    required super.api,
    super.realtime,
    super.cache,
    super.queue,
    super.connectivity,
    required super.uidProvider,
  });

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
  Future<Quotation> quoteQuotation(String id, QuoteInput input) =>
      api.quoteQuotation(id, input, idempotencyKey: SparklingApi.newOpId());

  @override
  Future<Quotation> convertQuotation(String id) =>
      api.convertQuotation(id, idempotencyKey: SparklingApi.newOpId());

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
