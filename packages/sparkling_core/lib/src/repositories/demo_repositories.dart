import 'dart:async';
import 'dart:typed_data';

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
  Future<Uint8List> quotationPdf(String id) =>
      _later(() => store.quotationPdf(id));
  @override
  Future<Uint8List> photoBytes(String url) =>
      _later(() => store.quotationPhotoBytes(url));
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

class DemoConfigRepository implements ConfigRepository {
  DemoConfigRepository(this.store);
  final DemoStore store;
  AppConfig? _current;

  @override
  AppConfig? get current => _current;

  @override
  Future<AppConfig> config({bool force = false}) =>
      _later(() => _current = store.publicConfig());
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
  Future<OutletCatalogue> outletServices(
    String outletId, {
    VehicleSize? vehicleSize,
  }) => _later(() => store.outletCatalogue(outletId, vehicleSize: vehicleSize));
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
  Stream<LoyaltyAccountSummary> watchAccount() => _watch(
    store,
    const {'loyalty_ledger', 'memberships', 'membership_usage'},
    store.loyaltyAccount,
  );
  @override
  Stream<List<LedgerEntry>> watchLedger() =>
      _watch(store, const {'loyalty_ledger'}, store.myLedger);
}

class DemoMembershipRepository implements MembershipRepository {
  DemoMembershipRepository(this.store);
  final DemoStore store;

  static const tables = {
    'memberships',
    'membership_usage',
    'membership_invoices',
    'payments',
  };

  @override
  Future<MembershipPlanList> plans() => _later(store.membershipPlanList);
  @override
  Future<MembershipSummary> me() =>
      _later(() => store.membershipSummary(store.uid));
  @override
  Future<SubscribeResult> subscribe({
    required String planCode,
    required Map<String, String> selections,
    required String clientOpId,
  }) => _later(
    () => store.subscribeMembership(
      planCode: planCode,
      selections: selections,
      clientOpId: clientOpId,
    ),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<PaymentIntentResult> payInvoice(String invoiceId) => _later(
    () => store.payMembershipInvoice(
      invoiceId,
      idempotencyKey: SparklingApi.newOpId(),
    ),
  );
  @override
  Future<MembershipSummary> changeSelections(Map<String, String> selections) =>
      _later(() => store.changeMembershipSelections(selections));
  @override
  Future<SubscribeResult> changePlan({
    required String planCode,
    required Map<String, String> selections,
  }) => _later(
    () => store.changeMembershipPlan(
      planCode: planCode,
      selections: selections,
      clientOpId: SparklingApi.newOpId(),
    ),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<MembershipSummary> cancel({bool atPeriodEnd = true}) =>
      _later(() => store.cancelMembership(atPeriodEnd: atPeriodEnd));
  @override
  Stream<MembershipSummary> watchMe() =>
      _watch(store, tables, () => store.membershipSummary(store.uid));
}

class DemoStaffRepository implements StaffRepository {
  DemoStaffRepository(this.store);
  final DemoStore store;

  @override
  Future<void> setAvailability(AvailabilityStatus status) =>
      _later(() => store.setAvailability(status));

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
  Future<WorkOrderCheckInResult> checkInWorkOrder(
    String workOrderId, {
    String? bay,
  }) => _later(() => store.checkInWorkOrder(workOrderId, bay: bay));
  @override
  Future<PickupVerifyResult> verifyPickupOtp(String workOrderId, String otp) =>
      _later(
        () => store.verifyPickupOtp(workOrderId, otp),
        delay: const Duration(milliseconds: 400),
      );
  @override
  Future<void> resendPickupOtp(String workOrderId) =>
      _later(() => store.resendPickupOtp(workOrderId));
  @override
  Future<List<Booking>> outletBookings({
    required String outletId,
    BookingStatus? status,
  }) => _later(() => store.outletBookings(outletId, status: status));
  @override
  Future<List<CustomerSummary>> searchCustomers(String query, {int? limit}) =>
      _later(() => store.searchCustomers(query, limit: limit ?? 20));
  @override
  Future<CustomerSummary> createCustomer(CustomerInput input) => _later(
    () => store.createCustomer(input),
    delay: const Duration(milliseconds: 300),
  );
  @override
  Future<Vehicle> createCustomerVehicle(
    String customerId,
    VehicleInput input, {
    bool force = false,
  }) => _later(
    () => store.createCustomerVehicle(
      customerId,
      input.copyWith(force: force || input.force),
    ),
  );
  @override
  Future<Booking> createWalkInBooking(WalkInBookingInput input) => _later(
    () => store.createWalkInBooking(input),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<Payment> recordPayment(RecordPaymentInput input) => _later(
    () => store.recordPayment(input),
    delay: const Duration(milliseconds: 300),
  );
  @override
  Future<MembershipSummary> customerMembership(String customerId) =>
      _later(() => store.customerMembershipSummary(customerId));
  @override
  Future<MembershipSummary> enrolMembership(EnrolMembershipInput input) =>
      _later(
        () => store.enrolMembership(input),
        delay: const Duration(milliseconds: 400),
      );
  @override
  Future<MembershipSummary> recordMembershipInvoicePayment({
    required String membershipId,
    required String invoiceId,
    required CounterPaymentMethod method,
    required String clientOpId,
  }) => _later(
    () => store.recordMembershipInvoicePayment(
      membershipId: membershipId,
      invoiceId: invoiceId,
      method: method,
      clientOpId: clientOpId,
    ),
    delay: const Duration(milliseconds: 300),
  );
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
  Future<Quotation> quotation(String id) =>
      _later(() => store.quotationDetail(id));
  @override
  Future<Quotation> quoteQuotation(String id, QuoteInput input) =>
      _later(() => store.quoteQuotation(id, input));
  @override
  Future<Quotation> convertQuotation(String id) =>
      _later(() => store.convertQuotation(id));
  @override
  Future<Quotation> raiseQuotation(
    StaffQuotationInput input, {
    List<DeferredPhoto> deferredPhotos = const [],
  }) => _later(
    () => store.raiseQuotation(input),
    delay: const Duration(milliseconds: 400),
  );
  @override
  Future<Attachment> uploadQuotationPhoto(
    String quotationId,
    Uint8List bytes, {
    String? caption,
    String? mimeType,
    String? filename,
  }) => _later(
    () => store.uploadQuotationPhoto(
      quotationId,
      bytes,
      caption: caption,
      mimeType: mimeType,
      filename: filename,
    ),
    delay: const Duration(milliseconds: 250),
  );
  @override
  Future<void> deleteQuotationPhoto(String quotationId, String attachmentId) =>
      _later(() => store.deleteQuotationPhoto(quotationId, attachmentId));
  @override
  Future<SharedQuoteLink> shareQuotation(String quotationId) =>
      _later(() => store.shareQuotation(quotationId));
  @override
  Future<Uint8List> quotationPdf(String quotationId) =>
      _later(() => store.quotationPdf(quotationId));
  @override
  Future<Uint8List> photoBytes(String url) =>
      _later(() => store.quotationPhotoBytes(url));
  @override
  Stream<List<Quotation>> watchQuotations({String? outletId}) => _watch(
    store,
    const {'quotations'},
    () => store.outletQuotations(outletId),
  );

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
