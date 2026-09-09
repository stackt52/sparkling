import 'dart:async';

import '../api/sparkling_api.dart';
import '../models/models.dart';
import 'demo_store.dart';
import 'repositories.dart';

/// Shared helper: emits `fetch()` now and again after any change on [tables].
Stream<T> _watch<T>(DemoStore store, Set<String> tables, T Function() fetch) {
  late StreamController<T> controller;
  StreamSubscription<DemoChange>? sub;
  void emit() {
    try {
      final v = fetch();
      if (!controller.isClosed) controller.add(v);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      scheduleMicrotask(emit);
      sub = store.changes
          .where((c) => tables.contains(c.table) || c.table == 'session')
          .listen((_) => emit());
    },
    onCancel: () async => sub?.cancel(),
  );
  return controller.stream;
}

/// Small latency so demo UIs exercise loading states.
Future<T> _later<T>(
  T Function() body, {
  Duration delay = const Duration(milliseconds: 120),
}) => Future.delayed(delay, body);

class DemoCustomerRepository implements CustomerRepository {
  DemoCustomerRepository(this.store);
  final DemoStore store;

  @override
  Future<Profile> me() => _later(store.me);
  @override
  Future<Profile> updateMe(ProfileUpdate update) =>
      _later(() => store.updateMe(update));
  @override
  Future<List<Vehicle>> vehicles() => _later(store.myVehicles);
  @override
  Future<Vehicle> addVehicle(VehicleInput input) =>
      _later(() => store.addVehicle(input));
  @override
  Future<Vehicle> updateVehicle(String id, VehicleInput input) =>
      _later(() => store.updateVehicle(id, input));
  @override
  Future<void> deleteVehicle(String id) =>
      _later(() => store.deleteVehicle(id));
  @override
  Future<List<Booking>> bookings({BookingStatus? status}) =>
      _later(() => store.myBookings(status: status));
  @override
  Future<Booking> booking(String id) => _later(() => store.bookingDetail(id));
  @override
  Future<Booking> createBooking(BookingInput input) => _later(
    () => store.createBooking(input),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<Booking> cancelBooking(String id, {String? reason}) =>
      _later(() => store.cancelBooking(id, reason: reason));
  @override
  Future<Booking> rescheduleBooking(String id, DateTime slotStart) =>
      _later(() => store.rescheduleBooking(id, slotStart));
  @override
  Future<List<Quotation>> quotations() => _later(store.myQuotations);
  @override
  Future<Quotation> quotation(String id) =>
      _later(() => store.quotationDetail(id));
  @override
  Future<Quotation> createQuotation(QuotationInput input) => _later(
    () => store.createQuotation(input),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<Quotation> decideQuotation(
    String id, {
    required bool accept,
    String? note,
  }) => _later(() => store.decideQuotation(id, accept: accept, note: note));
  @override
  Future<List<PaymentMethod>> paymentMethods() =>
      _later(store.myPaymentMethods);
  @override
  Future<PaymentIntentResult> createPaymentIntent({
    required String bookingId,
    String? methodId,
  }) => _later(
    () => store.createPaymentIntent(
      bookingId: bookingId,
      methodId: methodId,
      idempotencyKey: SparklingApi.newOpId(),
    ),
  );
  @override
  Future<Payment> confirmSandboxPayment(String paymentId) => _later(
    () => store.sandboxConfirm(paymentId),
    delay: const Duration(milliseconds: 700),
  );
  @override
  Future<Payment> payment(String id) => _later(() => store.paymentById(id));

  static const _bookingTables = {
    'bookings',
    'work_orders',
    'checklist_step_results',
    'payments',
    'tasks',
  };

  @override
  Stream<List<Booking>> watchBookings({BookingStatus? status}) =>
      _watch(store, _bookingTables, () => store.myBookings(status: status));
  @override
  Stream<Booking> watchBooking(String id) =>
      _watch(store, _bookingTables, () => store.bookingDetail(id));
  @override
  Stream<List<Vehicle>> watchVehicles() =>
      _watch(store, const {'vehicles'}, store.myVehicles);
  @override
  Stream<List<Quotation>> watchQuotations() =>
      _watch(store, const {'quotations'}, store.myQuotations);
}

class DemoCatalogueRepository implements CatalogueRepository {
  DemoCatalogueRepository(this.store);
  final DemoStore store;

  @override
  Future<List<Outlet>> outlets({double? lat, double? lng}) =>
      _later(() => store.outlets.where((o) => o.isActive).toList());
  @override
  Future<Outlet?> outlet(String id) => _later(() => store.outletById(id));
  @override
  Future<List<OutletService>> outletServices(String outletId) =>
      _later(() => store.outletServices(outletId));
  @override
  Future<List<AvailabilitySlot>> availability({
    required String outletId,
    required String serviceId,
    required DateTime date,
  }) => _later(
    () => store.availability(
      outletId: outletId,
      serviceId: serviceId,
      date: date,
    ),
  );
}

class DemoLoyaltyRepository implements LoyaltyRepository {
  DemoLoyaltyRepository(this.store);
  final DemoStore store;

  @override
  Future<LoyaltyAccountSummary> account() => _later(store.loyaltyAccount);
  @override
  Future<Page<LedgerEntry>> ledger({int? limit, String? cursor}) => _later(() {
    final all = store.myLedger();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final size = limit ?? 25;
    final items = all.skip(start).take(size).toList();
    final next = start + size < all.length ? '${start + size}' : null;
    return Page(items: items, nextCursor: next);
  });
  @override
  Future<List<Reward>> rewards() => _later(store.eligibleRewards);
  @override
  Future<RewardRedemption> redeem(String rewardId) => _later(
    () => store.redeem(rewardId, idempotencyKey: SparklingApi.newOpId()),
    delay: const Duration(milliseconds: 500),
  );
  @override
  Stream<LoyaltyAccountSummary> watchAccount() =>
      _watch(store, const {'loyalty_ledger'}, store.loyaltyAccount);
  @override
  Stream<List<LedgerEntry>> watchLedger() =>
      _watch(store, const {'loyalty_ledger'}, store.myLedger);
}

class DemoStaffRepository implements StaffRepository {
  DemoStaffRepository(this.store);
  final DemoStore store;

  @override
  Future<List<Task>> tasks({required TaskScope scope, String? outletId}) =>
      _later(() => store.taskList(scope: scope, outletId: outletId));
  @override
  Future<WorkOrderDetail> workOrder(String id) =>
      _later(() => store.workOrderDetail(id));
  @override
  Future<Task> transitionTask(Task task, TaskTransitionInput input) =>
      _later(() => store.transitionTask(task.id, input));
  @override
  Future<Task> assignTask(
    Task task, {
    required String assigneeId,
    String? reason,
  }) => _later(
    () => store.assignTask(
      task.id,
      assigneeId: assigneeId,
      reason: reason,
      clientOpId: SparklingApi.newOpId(),
    ),
  );
  @override
  Future<StepResult> submitStep(
    String workOrderId,
    String stepKey,
    StepResultInput input,
  ) => _later(() => store.submitStep(workOrderId, stepKey, input));
  @override
  Future<Booking> checkinBooking(
    String bookingId, {
    String? bay,
    int? priority,
  }) => _later(
    () => store.checkinBooking(bookingId, bay: bay, priority: priority),
  );
  @override
  Future<List<Booking>> outletBookings({
    required String outletId,
    BookingStatus? status,
  }) => _later(() => store.outletBookings(outletId, status: status));
  @override
  Future<OpsSummary> opsSummary({required String outletId}) =>
      _later(() => store.opsSummary(outletId));
  @override
  Future<List<StaffMember>> team({required String outletId}) =>
      _later(() => store.teamMembers(outletId));
  @override
  Future<LeaderboardResult> leaderboard({
    required String outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  }) => _later(() => store.leaderboard(outletId, period));
  @override
  Future<List<Quotation>> quotations({String? outletId}) =>
      _later(() => store.outletQuotations(outletId));
  @override
  Future<Quotation> quoteQuotation(String id, QuoteInput input) =>
      _later(() => store.quoteQuotation(id, input));
  @override
  Future<Quotation> convertQuotation(String id) =>
      _later(() => store.convertQuotation(id));

  static const _taskTables = {'tasks', 'work_orders', 'checklist_step_results'};

  @override
  Stream<List<Task>> watchTasks({required TaskScope scope, String? outletId}) =>
      _watch(
        store,
        _taskTables,
        () => store.taskList(scope: scope, outletId: outletId),
      );
  @override
  Stream<WorkOrderDetail> watchWorkOrder(String id) =>
      _watch(store, _taskTables, () => store.workOrderDetail(id));
  @override
  Stream<OpsSummary> watchOpsSummary({required String outletId}) => _watch(
    store,
    {..._taskTables, 'inventory_alerts', 'inventory_items'},
    () => store.opsSummary(outletId),
  );
}

class DemoInventoryRepository implements InventoryRepository {
  DemoInventoryRepository(this.store);
  final DemoStore store;

  @override
  Future<List<InventoryItem>> items({required String outletId}) =>
      _later(() => store.inventory(outletId));
  @override
  Future<InventoryItem> logMovement(
    InventoryItem item,
    InventoryMovementInput input,
  ) => _later(() => store.logMovement(item.id, input));
  @override
  Future<InventoryItem> updateItem(
    String id, {
    double? reorderThreshold,
    String? name,
    String? unit,
  }) => _later(
    () => store.updateInventoryItem(
      id,
      reorderThreshold: reorderThreshold,
      name: name,
      unit: unit,
    ),
  );
  @override
  Stream<List<InventoryItem>> watchItems({required String outletId}) => _watch(
    store,
    const {'inventory_items', 'inventory_alerts'},
    () => store.inventory(outletId),
  );
}

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this.store);
  final DemoStore store;

  @override
  Future<Page<AppNotification>> list({int? limit, String? cursor}) =>
      _later(() {
        final all = store.myNotifications();
        final start = int.tryParse(cursor ?? '') ?? 0;
        final size = limit ?? 25;
        return Page(
          items: all.skip(start).take(size).toList(),
          nextCursor: start + size < all.length ? '${start + size}' : null,
        );
      });
  @override
  Future<void> markRead(String id) => _later(() => store.markRead(id));
  @override
  Future<int> unreadCount() =>
      _later(() => store.myNotifications().where((n) => !n.isRead).length);
  @override
  Stream<List<AppNotification>> watch() =>
      _watch(store, const {'notifications'}, store.myNotifications);
}
