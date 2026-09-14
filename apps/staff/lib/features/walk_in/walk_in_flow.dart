import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// How the walk-in is paid at the counter (step 4).
enum WalkInPayment {
  cash,
  cardTerminal,

  /// Nothing is recorded — the booking stays pending payment and the
  /// customer pays from the app.
  inApp;

  PaymentMethodKind? get kind => switch (this) {
    cash => PaymentMethodKind.cash,
    cardTerminal => PaymentMethodKind.cardTerminal,
    inApp => null,
  };

  String get label => switch (this) {
    cash => 'Cash',
    cardTerminal => 'Card terminal',
    inApp => 'Customer pays in app',
  };
}

/// Steps of the walk-in flow (customer → vehicle → service & time → pay).
enum WalkInStep { customer, vehicle, service, payment }

/// Outcome of a confirmed walk-in, handed to the confirmation screen.
class WalkInOutcome {
  const WalkInOutcome({required this.booking, this.payment, this.customer});
  final Booking booking;
  final Payment? payment;
  final CustomerSummary? customer;

  bool get queued => booking.pendingSync || (payment?.pendingSync ?? false);
}

/// The customer + vehicle half of a counter flow, shared by the walk-in
/// booking and the raise-quote flow so `CustomerStep` / `VehicleStep` work
/// for both. Implementations persist their draft and notify on change.
abstract class CustomerVehicleFlow extends ChangeNotifier {
  CustomerSummary? get customer;
  CustomerVehicleSummary? get vehicle;

  /// The selected customer's membership (`GET /staff/customers/:id/membership`),
  /// loaded by [loadMembership]; null until loaded, [MembershipSummary.none]
  /// without a plan. Flows that do not price services keep it null.
  MembershipSummary? get membership => null;

  /// Loads [membership] for the current customer (no-op by default).
  Future<void> loadMembership(Repositories repositories, {bool force = false}) async {}

  /// Replaces the cached membership (after a counter enrolment / payment).
  void setMembership(MembershipSummary? m) {}

  /// Disc scanned before a customer was chosen (scan-review entry point).
  DiscScanResult? get scannedVehicle;
  DateTime? get restoredAt;

  void setCustomer(CustomerSummary c);
  void refreshCustomer(CustomerSummary c);
  void clearCustomer();
  void setVehicle(CustomerVehicleSummary v);
  void setScannedVehicle(DiscScanResult? r);
  void reset();

  static Map<String, dynamic> mapOf(Object? v) =>
      Map<String, dynamic>.from(v as Map);

  static DiscScanResult discFromJson(Map<String, dynamic> m) => DiscScanResult(
    registrationNo: m['registration_no']?.toString() ?? '',
    rawHash: m['raw_hash']?.toString() ?? '',
    vin: m['vin']?.toString(),
    engineNo: m['engine_no']?.toString(),
    make: m['make']?.toString(),
    model: m['model']?.toString(),
    colour: m['colour']?.toString(),
    description: m['description']?.toString(),
    licenceNo: m['licence_no']?.toString(),
    discExpiry: m['disc_expiry'] == null
        ? null
        : DateTime.tryParse(m['disc_expiry'].toString()),
    vehicleRegisterNo: m['vehicle_register_no']?.toString(),
  );
}

/// State for the 4-step staff walk-in flow (STF-010/012).
///
/// Mirrors the customer app's `BookingFlowController`: the draft is persisted
/// in [DraftStore] under [draftKey] after every change so a killed or offline
/// app resumes where the technician left off, and the `client_op_id` /
/// `idempotency_key` are generated once per draft so `POST /bookings` and
/// `POST /payments/record` are idempotent on retry (ARC-004).
class WalkInFlowController extends CustomerVehicleFlow {
  WalkInFlowController(this.repositories, {DiscScanResult? scanned}) {
    _restore();
    if (scanned != null) {
      // A fresh scan always wins over a stale draft's vehicle.
      scannedVehicle = scanned;
      vehicle = null;
      _persist();
    }
  }

  static const String draftKey = 'walk_in_draft';

  final Repositories repositories;

  @override
  CustomerSummary? customer;
  @override
  CustomerVehicleSummary? vehicle;

  /// Disc scanned before a customer was chosen (scan-review entry point).
  /// Registered against the customer in step 2.
  @override
  DiscScanResult? scannedVehicle;
  Outlet? outlet;
  OutletService? service;

  /// Add-ons of the service's group (priced like the service, summed).
  List<OutletService> addons = [];

  /// `true` = book for now (server rounds to the slot grid).
  bool bookNow = true;
  DateTime? slotStart;
  WalkInPayment payment = WalkInPayment.cash;
  String? paymentReference;
  bool checkInNow = true;
  String? bay;
  int priority = 2;
  String clientOpId = SparklingApi.newOpId();
  String paymentIdempotencyKey = SparklingApi.newOpId();
  @override
  DateTime? restoredAt;

  @override
  MembershipSummary? membership;
  String? _membershipFor;

  @override
  Future<void> loadMembership(
    Repositories repositories, {
    bool force = false,
  }) async {
    final c = customer;
    if (c == null) return;
    if (!force && membership != null && _membershipFor == c.id) return;
    _membershipFor = c.id;
    MembershipSummary loaded;
    try {
      loaded = await repositories.staff.customerMembership(c.id);
    } catch (_) {
      loaded = MembershipSummary.none;
    }
    setMembership(loaded);
  }

  @override
  void setMembership(MembershipSummary? m) {
    membership = m;
    _membershipFor = customer?.id;
    // Keep the customer card's plan label in step with the membership (a
    // restored draft may carry a stale summary).
    final c = customer;
    // A walk-in without a loyalty account stays "Walk-in" until enrolled.
    if (c != null && m != null && (m.hasMembership || c.loyalty != null)) {
      customer = c.copyWith(
        loyalty: CustomerLoyaltySummary(
          tier: m.tier,
          balancePoints: c.loyalty?.balancePoints ?? 0,
          discountPct: 0,
          planCode: m.hasMembership ? m.planCode : null,
          planName: m.hasMembership ? m.planName : null,
          includedRemaining: m.hasMembership ? m.includedRemaining : null,
        ),
      );
    }
    notifyListeners();
  }

  bool get hasDraft => customer != null;
  bool get canPickVehicle => customer != null;
  bool get canPickService => customer != null && vehicle != null;
  bool get canPay =>
      canPickService &&
      outlet != null &&
      service != null &&
      (bookNow || slotStart != null);

  /// Furthest step the draft allows.
  WalkInStep get maxStep => !canPickVehicle
      ? WalkInStep.customer
      : !canPickService
      ? WalkInStep.vehicle
      : !canPay
      ? WalkInStep.service
      : WalkInStep.payment;

  static Map<String, dynamic> _map(Object? v) => CustomerVehicleFlow.mapOf(v);

  void _restore() {
    final json = repositories.drafts.load(draftKey);
    if (json == null) return;
    try {
      if (json['customer'] is Map) {
        customer = CustomerSummary.fromJson(_map(json['customer']));
      }
      if (json['vehicle'] is Map) {
        vehicle = CustomerVehicleSummary.fromJson(_map(json['vehicle']));
      }
      if (json['scanned_vehicle'] is Map) {
        scannedVehicle = _discFromJson(_map(json['scanned_vehicle']));
      }
      if (json['outlet'] is Map) outlet = Outlet.fromJson(_map(json['outlet']));
      if (json['service'] is Map) {
        service = OutletService.fromJson(_map(json['service']));
      }
      addons = [
        for (final a in (json['addons'] as List? ?? const []))
          if (a is Map) OutletService.fromJson(_map(a)),
      ];
      bookNow = json['book_now'] is bool ? json['book_now'] as bool : true;
      final slot = json['slot_start'];
      slotStart = slot == null ? null : DateTime.tryParse('$slot')?.toLocal();
      payment = WalkInPayment.values.firstWhere(
        (p) => p.name == json['payment'],
        orElse: () => WalkInPayment.cash,
      );
      paymentReference = json['payment_reference']?.toString();
      checkInNow = json['check_in_now'] is bool
          ? json['check_in_now'] as bool
          : true;
      bay = json['bay']?.toString();
      priority = (json['priority'] as num?)?.toInt() ?? 2;
      clientOpId = json['client_op_id']?.toString() ?? clientOpId;
      paymentIdempotencyKey =
          json['payment_idempotency_key']?.toString() ?? paymentIdempotencyKey;
      restoredAt = repositories.drafts.savedAt(draftKey);
    } catch (_) {
      // Corrupt draft — start clean.
      reset();
    }
  }

  static DiscScanResult _discFromJson(Map<String, dynamic> m) =>
      CustomerVehicleFlow.discFromJson(m);

  Future<void> _persist() async {
    // Notify first so the UI never waits on disk I/O.
    notifyListeners();
    await repositories.drafts.save(draftKey, {
      'customer': customer?.toJson(),
      'vehicle': vehicle?.toJson(),
      'scanned_vehicle': scannedVehicle?.toJson(),
      'outlet': outlet?.toJson(),
      'service': service?.toJson(),
      'addons': addons.map((a) => a.toJson()).toList(),
      'book_now': bookNow,
      'slot_start': slotStart?.toUtc().toIso8601String(),
      'payment': payment.name,
      'payment_reference': paymentReference,
      'check_in_now': checkInNow,
      'bay': bay,
      'priority': priority,
      'client_op_id': clientOpId,
      'payment_idempotency_key': paymentIdempotencyKey,
    });
  }

  @override
  void setCustomer(CustomerSummary c) {
    if (customer?.id != c.id) {
      vehicle = null;
      membership = null;
      _membershipFor = null;
    }
    customer = c;
    _persist();
  }

  /// Replaces the cached customer (e.g. after a vehicle was added).
  @override
  void refreshCustomer(CustomerSummary c) {
    customer = c;
    _persist();
  }

  @override
  void clearCustomer() {
    customer = null;
    vehicle = null;
    membership = null;
    _membershipFor = null;
    _persist();
  }

  @override
  void setVehicle(CustomerVehicleSummary v) {
    vehicle = v;
    // Once a vehicle is chosen the pre-scanned disc has served its purpose.
    if (scannedVehicle != null &&
        Vehicle.normaliseRegistration(scannedVehicle!.registrationNo) ==
            v.normalisedRegistration) {
      scannedVehicle = null;
    }
    _persist();
  }

  @override
  void setScannedVehicle(DiscScanResult? r) {
    scannedVehicle = r;
    _persist();
  }

  void setOutlet(Outlet o) {
    if (outlet?.id == o.id) return;
    outlet = o;
    service = null;
    addons = [];
    slotStart = null;
    _persist();
  }

  void setService(OutletService s) {
    if (service?.groupName != s.groupName) addons = [];
    service = s;
    slotStart = null;
    _persist();
  }

  /// Toggles an add-on of the selected service's group.
  void toggleAddon(OutletService addon, bool selected) {
    final without = addons.where((a) => a.serviceId != addon.serviceId);
    addons = selected ? [...without, addon] : without.toList();
    _persist();
  }

  bool hasAddon(String serviceId) =>
      addons.any((a) => a.serviceId == serviceId);

  void setBookNow(bool now) {
    bookNow = now;
    if (now) slotStart = null;
    _persist();
  }

  void setSlot(DateTime? start) {
    slotStart = start;
    if (start != null) bookNow = false;
    _persist();
  }

  void setPayment(WalkInPayment p) {
    payment = p;
    if (p != WalkInPayment.cardTerminal) paymentReference = null;
    _persist();
  }

  void setPaymentReference(String? ref) {
    paymentReference = (ref?.trim().isEmpty ?? true) ? null : ref!.trim();
    _persist();
  }

  void setCheckIn({bool? now, String? bay, int? priority}) {
    if (now != null) checkInNow = now;
    if (bay != null) this.bay = bay.trim().isEmpty ? null : bay.trim();
    if (priority != null) this.priority = priority;
    _persist();
  }

  /// Size the prices are resolved for (the chosen vehicle's `size_class`).
  VehicleSize get vehicleSize => vehicle?.sizeClass ?? VehicleSize.small;

  /// Catalogue price for [vehicleSize] (estimate; the server recomputes on
  /// `POST /bookings`).
  int get priceCents => service?.priceFor(vehicleSize) ?? 0;

  /// Sum of the selected add-ons for [vehicleSize].
  int get addonsCents =>
      addons.fold(0, (sum, a) => sum + (a.priceFor(vehicleSize) ?? 0));

  /// Base + add-ons before the tier discount and VAT.
  int get subtotalCents => priceCents + addonsCents;

  bool get isExclVat => service?.vatMode == VatMode.excl;

  /// Tier discount on base + add-ons.
  int discountFor(int pct) => (subtotalCents * pct / 100).round();

  /// 15 % VAT on the discounted subtotal for `excl` offers.
  int vatFor(int pct) =>
      isExclVat ? VatMode.excl.vatOn(subtotalCents - discountFor(pct)) : 0;

  /// What the customer pays after [pct] tier discount.
  int totalFor(int pct) => subtotalCents - discountFor(pct) + vatFor(pct);

  // ---- Membership benefit (estimate of docs/MEMBERSHIPS.md pricing rules) --

  Allowance? coveringAllowance(OutletService offer) {
    final m = membership;
    if (m == null || !m.benefitsActive) return null;
    return m.coveringAllowance(offer.code);
  }

  bool isCovered(OutletService offer) => coveringAllowance(offer) != null;

  int planDiscountPctFor(OutletService offer) =>
      isCovered(offer) ? 0 : (membership?.discountPctFor(offer.code) ?? 0);

  /// "3 of 4 left" (covered) / "Gold −10%" for an offer card.
  String? benefitTagFor(OutletService offer) {
    final a = coveringAllowance(offer);
    if (a != null) return '${a.remaining} of ${a.quantity} left';
    final pct = planDiscountPctFor(offer);
    if (pct > 0) return '${membership!.planName} −$pct%';
    return null;
  }

  /// The whole base when covered, else the plan % on base + add-ons.
  int get membershipDiscountCents {
    final s = service;
    if (s == null) return 0;
    if (isCovered(s)) return priceCents;
    return (subtotalCents * planDiscountPctFor(s) / 100).round();
  }

  /// "Included in Gold · 2 of 4 left" / "Gold −10%".
  String? get membershipLabel {
    final s = service;
    if (s == null) return null;
    final a = coveringAllowance(s);
    if (a != null) {
      return 'Included in ${membership!.planName} · ${a.remaining - 1} of ${a.quantity} left';
    }
    final pct = planDiscountPctFor(s);
    return pct > 0 ? '${membership!.planName} −$pct%' : null;
  }

  bool get isIncluded => service != null && isCovered(service!);

  int get estimatedVatCents => isExclVat
      ? VatMode.excl.vatOn(subtotalCents - membershipDiscountCents)
      : 0;

  /// What the customer pays (server recomputes on `POST /bookings`).
  int get estimatedTotalCents =>
      subtotalCents - membershipDiscountCents + estimatedVatCents;

  bool get nothingToPay => service != null && estimatedTotalCents == 0;

  /// Points on what is actually paid at the published rate — 0 for a
  /// fully covered wash.
  int get pointsEstimate {
    final s = service;
    if (s == null) return 0;
    return (estimatedTotalCents / 100 * s.pointsPerRand).round();
  }

  WalkInBookingInput toBookingInput() => WalkInBookingInput(
    customerId: customer!.id,
    vehicleId: vehicle!.id,
    outletId: outlet!.id,
    serviceId: service!.id,
    clientOpId: clientOpId,
    slotStart: bookNow ? null : slotStart,
    checkin: checkInNow ? WalkInCheckin(bay: bay, priority: priority) : null,
    vehicleSize: vehicleSize,
    addonServiceIds: addons.map((a) => a.serviceId).toList(),
  );

  RecordPaymentInput? toPaymentInput(Booking booking) {
    final kind = payment.kind;
    // Nothing to record when the plan covered the whole booking.
    if (kind == null || booking.totalCents <= 0) return null;
    return RecordPaymentInput(
      bookingId: booking.id,
      method: kind,
      reference: paymentReference,
      amountCents: booking.totalCents,
      idempotencyKey: paymentIdempotencyKey,
    );
  }

  /// A conflict on submit (bays full / slot taken) needs a fresh op id, the
  /// draft otherwise stays for the technician to adjust.
  void rotateOpIds() {
    clientOpId = SparklingApi.newOpId();
    paymentIdempotencyKey = SparklingApi.newOpId();
    _persist();
  }

  /// Clears the draft after a successful booking (or on explicit discard).
  @override
  void reset() {
    customer = null;
    vehicle = null;
    scannedVehicle = null;
    outlet = null;
    service = null;
    addons = [];
    bookNow = true;
    slotStart = null;
    payment = WalkInPayment.cash;
    paymentReference = null;
    checkInNow = true;
    bay = null;
    priority = 2;
    restoredAt = null;
    membership = null;
    _membershipFor = null;
    clientOpId = SparklingApi.newOpId();
    paymentIdempotencyKey = SparklingApi.newOpId();
    repositories.drafts.delete(draftKey);
    notifyListeners();
  }
}
