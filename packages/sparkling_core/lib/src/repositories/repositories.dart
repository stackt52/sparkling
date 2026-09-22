import 'dart:typed_data';

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
  /// One-time decision (CUS-033): a second call throws [ApiException]
  /// `conflict` (409, `data.decided_at` / `data.status`); an expired quote
  /// throws `gone` (410).
  Future<Quotation> decideQuotation(
    String id, {
    required bool accept,
    String? note,
  });

  /// `GET /quotations/:id/pdf` → PDF bytes.
  Future<Uint8List> quotationPdf(String id);

  /// Loads an attachment's bytes with the bearer token (`AuthedImage`).
  /// Demo `demo://photo/<id>` urls are served from memory.
  Future<Uint8List> photoBytes(String url);

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
  /// The outlet's catalogue: offers grouped by `group_name` with per-size
  /// prices, composition and add-ons. [vehicleSize] resolves `price_cents`
  /// for that size (`?vehicle_size`).
  Future<OutletCatalogue> outletServices(
    String outletId, {
    VehicleSize? vehicleSize,
  });
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

/// Membership plans (docs/MEMBERSHIPS.md) — the customer's own plan.
abstract interface class MembershipRepository {
  /// The three plans with their groups / entitlements (+ current plan code).
  Future<MembershipPlanList> plans();

  /// `GET /memberships/me` — [MembershipSummary.none] without a plan.
  Future<MembershipSummary> me();

  /// `POST /memberships` → pending membership + first invoice + sandbox
  /// payment intent; confirm it with [CustomerRepository.confirmSandboxPayment]
  /// to activate. 409 `conflict` when a live membership exists.
  Future<SubscribeResult> subscribe({
    required String planCode,
    required Map<String, String> selections,
    required String clientOpId,
  });

  /// Sandbox payment intent for a pending (renewal) invoice.
  Future<PaymentIntentResult> payInvoice(String invoiceId);

  /// 409 `conflict` once anything was redeemed this period.
  Future<MembershipSummary> changeSelections(Map<String, String> selections);

  /// Upgrade: invoice + payment to confirm now; downgrade: applied at renewal.
  Future<SubscribeResult> changePlan({
    required String planCode,
    required Map<String, String> selections,
  });

  Future<MembershipSummary> cancel({bool atPeriodEnd = true});

  /// Emits now and after every `memberships` / `membership_usage` /
  /// `membership_invoices` change.
  Stream<MembershipSummary> watchMe();
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

  /// `PUT /staff/me/availability` — the signed-in staff member's availability
  /// (drives the supervisor assign sheet and the admin Staff page).
  Future<void> setAvailability(AvailabilityStatus status);

  /// Re-sends the collection OTP to the customer (WhatsApp + push).
  /// Throws `rate_limited` when called again within the cooldown.
  Future<void> resendPickupOtp(String workOrderId);
  Future<List<Booking>> outletBookings({
    required String outletId,
    BookingStatus? status,
  });

  // ---- Walk-in customers & bookings (STF-010/012) ---------------------------

  /// Search customers by name, phone, e-mail or plate (min 2 chars).
  Future<List<CustomerSummary>> searchCustomers(String query, {int? limit});

  /// Registers a walk-in customer. Throws [ApiException] `conflict` with
  /// `existingCustomer` when the phone / e-mail is already registered.
  Future<CustomerSummary> createCustomer(CustomerInput input);

  /// Adds a vehicle for [customerId]. 409 `conflict` + `existingVehicleId`
  /// on a duplicate plate / VIN unless [force].
  Future<Vehicle> createCustomerVehicle(
    String customerId,
    VehicleInput input, {
    bool force = false,
  });

  /// Creates a `confirmed` walk-in booking (optionally checked in). When
  /// offline the operation is queued and an optimistic `pendingSync` copy is
  /// returned. Throws `conflict` when no bay is free.
  Future<Booking> createWalkInBooking(WalkInBookingInput input);

  /// Records a cash / card-terminal payment. Queued offline like
  /// [createWalkInBooking]; the receipt number arrives on sync.
  Future<Payment> recordPayment(RecordPaymentInput input);

  // ---- Memberships at the counter (docs/MEMBERSHIPS.md) ---------------------

  /// `GET /staff/customers/:id/membership` — same shape as `/memberships/me`.
  Future<MembershipSummary> customerMembership(String customerId);

  /// Enrols the customer at the counter: active immediately, invoice paid,
  /// POS payment recorded. Offline the operation is queued
  /// (`membership.enrol`) and a `pendingSync` summary is returned. 409
  /// `conflict` when a live membership exists.
  Future<MembershipSummary> enrolMembership(EnrolMembershipInput input);

  /// Pays a pending renewal invoice at the counter (rolls the period).
  Future<MembershipSummary> recordMembershipInvoicePayment({
    required String membershipId,
    required String invoiceId,
    required CounterPaymentMethod method,
    required String clientOpId,
  });

  Future<OpsSummary> opsSummary({required String outletId});
  Future<List<StaffMember>> team({required String outletId});
  Future<LeaderboardResult> leaderboard({
    required String outletId,
    LeaderboardPeriod period = LeaderboardPeriod.week,
  });

  Future<List<Quotation>> quotations({String? outletId});
  Future<Quotation> quotation(String id);
  Future<Quotation> quoteQuotation(String id, QuoteInput input);
  Future<Quotation> convertQuotation(String id);

  // ---- Staff-raised quotations (STF-010/012, CUS-030..034) ----------------

  /// Raises a `quoted` quotation for a walk-in customer in one step. Offline
  /// the operation is queued (`quotation.raise`) and an optimistic
  /// `pendingSync` copy is returned; [deferredPhotos] (local file paths +
  /// captions) are uploaded once the queued operation is applied.
  Future<Quotation> raiseQuotation(
    StaffQuotationInput input, {
    List<DeferredPhoto> deferredPhotos = const [],
  });

  /// `POST /quotations/:id/photos` (multipart). Up to 10 per quotation.
  Future<Attachment> uploadQuotationPhoto(
    String quotationId,
    Uint8List bytes, {
    String? caption,
    String? mimeType,
    String? filename,
  });

  Future<void> deleteQuotationPhoto(String quotationId, String attachmentId);

  /// Rotates the public token and re-sends the WhatsApp/push. Throws
  /// `rate_limited` within the 60 s cooldown.
  Future<SharedQuoteLink> shareQuotation(String quotationId);

  Future<Uint8List> quotationPdf(String quotationId);

  /// Attachment bytes with auth (see [CustomerRepository.photoBytes]).
  Future<Uint8List> photoBytes(String url);

  Stream<List<Quotation>> watchQuotations({String? outletId});

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

/// A damage photo kept on the device until a queued `quotation.raise` is
/// applied by the server.
class DeferredPhoto {
  const DeferredPhoto({required this.path, this.caption});
  final String path;
  final String? caption;

  Json toJson() => {'path': path, if (caption != null) 'caption': caption};
  factory DeferredPhoto.fromJson(Json json) => DeferredPhoto(
    path: json['path']?.toString() ?? '',
    caption: json['caption']?.toString(),
  );
}
