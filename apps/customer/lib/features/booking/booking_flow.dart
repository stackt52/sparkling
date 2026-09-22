import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// State for the 3-step booking flow (service → slot → pay).
///
/// The draft is persisted in [DraftStore] after every change (UX-009) so a
/// killed or offline app resumes where the customer left off. The
/// `client_op_id` is generated once per draft and reused on retry, which makes
/// `POST /bookings` idempotent (ARC-004).
///
/// Prices follow the catalogue pricing model: the offer's price is resolved
/// for the selected vehicle's size, add-ons of the same group are summed,
/// the membership benefit applies (a covered service waives the base, the
/// plan discount applies by scope — docs/MEMBERSHIPS.md) and 15 % VAT is
/// added on `excl` offers. The server recomputes on `POST /bookings`.
class BookingFlowController extends ChangeNotifier {
  BookingFlowController(this.repositories) {
    _restore();
  }

  static const String draftKey = 'booking_draft';

  final Repositories repositories;

  Outlet? outlet;
  OutletService? service;
  List<OutletService> addons = [];
  Vehicle? vehicle;
  DateTime? slotStart;
  String? methodId;

  /// How the customer chose to pay at "Review & pay": a saved card / instant
  /// EFT ([methodId]) or **cash on collection** (`payment_method: cash`, only
  /// when the `cash_on_collection` flag is on). Kept in memory for the flow
  /// only — not part of the persisted draft.
  PaymentChoice? paymentChoice;
  String clientOpId = SparklingApi.newOpId();
  DateTime? restoredAt;

  /// The customer's membership (`GET /memberships/me`), loaded once per flow
  /// by [loadMembership]; [MembershipSummary.none] without a plan.
  MembershipSummary? membership;

  /// Loads (or refreshes) [membership] — errors leave the estimate plan-less.
  Future<void> loadMembership({bool force = false}) async {
    if (membership != null && !force) return;
    try {
      membership = await repositories.membership.me();
    } catch (_) {
      membership = MembershipSummary.none;
    }
    notifyListeners();
  }

  bool get hasDraft => outlet != null && service != null;
  bool get canPickSlot => outlet != null && service != null && vehicle != null;
  bool get canPay => canPickSlot && slotStart != null;

  DateTime? get slotEnd => slotStart == null || service == null
      ? null
      : slotStart!.add(Duration(minutes: service!.durationMinutes));

  /// Size the prices are resolved for (the chosen vehicle's `size_class`).
  VehicleSize get vehicleSize => vehicle?.sizeClass ?? VehicleSize.small;

  /// Resolved base price for [vehicleSize] (0 while nothing is selected).
  int get baseCents => service?.priceFor(vehicleSize) ?? 0;

  /// Sum of the selected add-ons for [vehicleSize].
  int get addonsCents =>
      addons.fold(0, (sum, a) => sum + (a.priceFor(vehicleSize) ?? 0));

  /// Base + add-ons before discount and VAT.
  int get subtotalCents => baseCents + addonsCents;

  bool get isExclVat => service?.vatMode == VatMode.excl;

  /// Flat % discount on base + add-ons (legacy tier discount; 0 now).
  int discountFor(int pct) => (subtotalCents * pct / 100).round();

  /// VAT (15 %) on the discounted subtotal for `excl` offers.
  int vatFor(int discountPct) => isExclVat
      ? VatMode.excl.vatOn(subtotalCents - discountFor(discountPct))
      : 0;

  /// Total the customer pays after [discountPct].
  int totalFor(int discountPct) =>
      subtotalCents - discountFor(discountPct) + vatFor(discountPct);

  // ---- Membership benefit (estimate of docs/MEMBERSHIPS.md pricing rules) --

  /// The plan allowance that covers [offer] (null without a plan, when the
  /// plan is not active, or when the allowance is used up).
  Allowance? coveringAllowance(OutletService offer) {
    final m = membership;
    if (m == null || !m.benefitsActive) return null;
    return m.coveringAllowance(offer.code);
  }

  bool isCovered(OutletService offer) => coveringAllowance(offer) != null;

  /// Plan discount % on [offer] by scope (0 when none / covered instead).
  int planDiscountPctFor(OutletService offer) =>
      isCovered(offer) ? 0 : (membership?.discountPctFor(offer.code) ?? 0);

  /// Short benefit tag for an offer card: "3 of 4 left" (covered),
  /// "Gold −10%" or null.
  String? benefitTagFor(OutletService offer) {
    final a = coveringAllowance(offer);
    if (a != null) return '${a.remaining} of ${a.quantity} left';
    final pct = planDiscountPctFor(offer);
    if (pct > 0) return '${membership!.planName} −$pct%';
    return null;
  }

  /// Membership discount on the draft: the whole base when the service is
  /// covered, else the plan % on base + add-ons.
  int get membershipDiscountCents {
    final s = service;
    if (s == null) return 0;
    if (isCovered(s)) return baseCents;
    return (subtotalCents * planDiscountPctFor(s) / 100).round();
  }

  /// "Included in Gold · 2 of 4 left" / "Gold −10%" (what the server labels).
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

  /// VAT on what is still charged (add-ons only when the service is covered).
  int get estimatedVatCents => isExclVat
      ? VatMode.excl.vatOn(subtotalCents - membershipDiscountCents)
      : 0;

  /// What the customer is expected to pay (server recomputes on submit).
  int get estimatedTotalCents =>
      subtotalCents - membershipDiscountCents + estimatedVatCents;

  /// A fully covered booking with no add-ons has nothing to pay.
  bool get nothingToPay => service != null && estimatedTotalCents == 0;

  /// Estimated total shown in the step bottom bars.
  int get quotedCents => estimatedTotalCents;

  /// Points on what is actually paid (published rate) — 0 for a fully
  /// covered wash.
  int get pointsEstimate {
    final s = service;
    if (s == null) return 0;
    return (estimatedTotalCents / 100 * s.pointsPerRand).round();
  }

  static Map<String, dynamic> _map(Object? v) =>
      Map<String, dynamic>.from(v as Map);

  void _restore() {
    final json = repositories.drafts.load(draftKey);
    if (json == null) return;
    try {
      if (json['outlet'] is Map) outlet = Outlet.fromJson(_map(json['outlet']));
      if (json['service'] is Map) {
        service = OutletService.fromJson(_map(json['service']));
      }
      addons = [
        for (final a in (json['addons'] as List? ?? const []))
          if (a is Map) OutletService.fromJson(_map(a)),
      ];
      if (json['vehicle'] is Map) {
        vehicle = Vehicle.fromJson(_map(json['vehicle']));
      }
      final slot = json['slot_start'];
      slotStart = slot == null ? null : DateTime.tryParse('$slot')?.toLocal();
      methodId = json['method_id']?.toString();
      clientOpId = json['client_op_id']?.toString() ?? clientOpId;
      restoredAt = repositories.drafts.savedAt(draftKey);
    } catch (_) {
      // Corrupt draft — start clean.
      reset();
    }
  }

  Future<void> _persist() async {
    // Notify first so the UI never waits on disk I/O; the draft write is
    // fire-and-forget (it is re-read only on the next cold start).
    notifyListeners();
    await repositories.drafts.save(draftKey, {
      'outlet': outlet?.toJson(),
      'service': service?.toJson(),
      'addons': addons.map((a) => a.toJson()).toList(),
      'vehicle': vehicle?.toJson(),
      'slot_start': slotStart?.toUtc().toIso8601String(),
      'method_id': methodId,
      'client_op_id': clientOpId,
    });
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

  void setVehicle(Vehicle v) {
    vehicle = v;
    _persist();
  }

  void setSlot(DateTime? start) {
    slotStart = start;
    _persist();
  }

  void setMethod(String? id, {PaymentChoice? choice}) {
    methodId = id;
    paymentChoice = choice;
    _persist();
  }

  /// Selects **cash on collection** (the saved method stays remembered).
  void setPayCash() {
    paymentChoice = PaymentChoice.cash;
    notifyListeners();
  }

  bool get payCash => paymentChoice == PaymentChoice.cash;

  BookingInput toInput() => BookingInput(
    vehicleId: vehicle!.id,
    outletId: outlet!.id,
    serviceId: service!.id,
    slotStart: slotStart!,
    clientOpId: clientOpId,
    vehicleSize: vehicleSize,
    addonServiceIds: addons.map((a) => a.serviceId).toList(),
    paymentMethod: nothingToPay ? null : paymentChoice,
  );

  /// Clears the draft after a successful booking (or on explicit discard).
  void reset() {
    outlet = null;
    service = null;
    addons = [];
    vehicle = null;
    slotStart = null;
    methodId = null;
    paymentChoice = null;
    restoredAt = null;
    clientOpId = SparklingApi.newOpId();
    repositories.drafts.delete(draftKey);
    notifyListeners();
  }
}
