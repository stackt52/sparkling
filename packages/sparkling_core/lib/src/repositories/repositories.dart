import '../models/models.dart';

/// Customer-facing data (CUS-*): profile, vehicles, bookings, quotations,
/// payments. `watch*` streams emit an initial value and then again whenever
/// the underlying rows change (realtime or demo mutations).
abstract interface class CustomerRepository {
  Future<Profile> me();
  Future<Profile> updateMe(ProfileUpdate update);

  Future<List<Vehicle>> vehicles();

  /// Throws [ApiException] with `isConflict` + `existingVehicleId` on a
  /// duplicate (CUS-015) unless `input.force`.
  Future<Vehicle> addVehicle(VehicleInput input);
  Future<Vehicle> updateVehicle(String id, VehicleInput input);
  Future<void> deleteVehicle(String id);

  Future<List<Booking>> bookings({BookingStatus? status});
  Future<Booking> booking(String id);

  /// Price is computed server-side; throws `conflict` when the slot is full.
  Future<Booking> createBooking(BookingInput input);
  Future<Booking> cancelBooking(String id, {String? reason});
  Future<Booking> rescheduleBooking(String id, DateTime slotStart);

  Future<List<Quotation>> quotations();
  Future<Quotation> quotation(String id);
  Future<Quotation> createQuotation(QuotationInput input);
  Future<Quotation> decideQuotation(
    String id, {
    required bool accept,
    String? note,
  });

  Future<List<PaymentMethod>> paymentMethods();
  Future<PaymentIntentResult> createPaymentIntent({
    required String bookingId,
    String? methodId,
  });

  /// Sandbox only — simulates the provider webhook (`payments_sandbox` flag).
  Future<Payment> confirmSandboxPayment(String paymentId);
  Future<Payment> payment(String id);

  Stream<List<Booking>> watchBookings({BookingStatus? status});
  Stream<Booking> watchBooking(String id);
  Stream<List<Vehicle>> watchVehicles();
  Stream<List<Quotation>> watchQuotations();
}

/// Outlets, services and availability (public catalogue).
abstract interface class CatalogueRepository {
  Future<List<Outlet>> outlets({double? lat, double? lng});
  Future<Outlet?> outlet(String id);
  Future<List<OutletService>> outletServices(String outletId);
  Future<List<AvailabilitySlot>> availability({
    required String outletId,
    required String serviceId,
    required DateTime date,
  });
}

/// Loyalty (CUS-060..064).
abstract interface class LoyaltyRepository {
  Future<LoyaltyAccountSummary> account();
  Future<Page<LedgerEntry>> ledger({int? limit, String? cursor});
  Future<List<Reward>> rewards();

  /// Idempotent per call (a fresh `Idempotency-Key` is generated).
  Future<RewardRedemption> redeem(String rewardId);

  Stream<LoyaltyAccountSummary> watchAccount();
  Stream<List<LedgerEntry>> watchLedger();
}

/// Staff operations (STF-*): tasks, checklists, ops summary, team,
/// leaderboard, quotations assessment.
abstract interface class StaffRepository {
  Future<List<Task>> tasks({required TaskScope scope, String? outletId});
  Future<WorkOrderDetail> workOrder(String id);

  /// Transition validated server-side (STF-023). When offline the operation is
  /// queued and an optimistic copy of [task] is returned.
  Future<Task> transitionTask(Task task, TaskTransitionInput input);
  Future<Task> assignTask(
    Task task, {
    required String assigneeId,
    String? reason,
  });

  /// When offline the result is queued and returned with `pendingSync: true`.
  Future<StepResult> submitStep(
    String workOrderId,
    String stepKey,
    StepResultInput input,
  );

  Future<Booking> checkinBooking(
    String bookingId, {
    String? bay,
    int? priority,
  });

  /// Vehicle hand-over: verifies the customer's 5-digit collection OTP and
  /// releases the keys. Never queued offline. Throws [ApiException]
  /// `invalid_otp` (see `attemptsLeft`) or `rate_limited`.
  Future<PickupVerifyResult> verifyPickupOtp(String workOrderId, String otp);

  /// Re-sends the collection OTP to the customer (WhatsApp + push).
  /// Throws `rate_limited` when called again within the cooldown.
  Future<void> resendPickupOtp(String workOrderId);
  Future<List<Booking>> outletBookings({
    required String outletId,
    BookingStatus? status,
  });

  Future<OpsSummary> opsSummary({required String outletId});
  Future<List<StaffMember>> team({required String outletId});
  Future<LeaderboardResult> leaderboard({
    required String outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  });

  Future<List<Quotation>> quotations({String? outletId});
  Future<Quotation> quoteQuotation(String id, QuoteInput input);
  Future<Quotation> convertQuotation(String id);

  Stream<List<Task>> watchTasks({required TaskScope scope, String? outletId});
  Stream<WorkOrderDetail> watchWorkOrder(String id);
  Stream<OpsSummary> watchOpsSummary({required String outletId});
}

/// Inventory (STF-040..043).
abstract interface class InventoryRepository {
  Future<List<InventoryItem>> items({required String outletId});

  /// Technicians: `usage` / `reorder_request` only. Offline → queued, optimistic item returned.
  Future<InventoryItem> logMovement(
    InventoryItem item,
    InventoryMovementInput input,
  );

  /// Manager only (audited).
  Future<InventoryItem> updateItem(
    String id, {
    double? reorderThreshold,
    String? name,
    String? unit,
  });

  Stream<List<InventoryItem>> watchItems({required String outletId});
}

/// In-app notification centre (NOT-003).
abstract interface class NotificationsRepository {
  Future<Page<AppNotification>> list({int? limit, String? cursor});
  Future<void> markRead(String id);
  Future<int> unreadCount();
  Stream<List<AppNotification>> watch();
}
