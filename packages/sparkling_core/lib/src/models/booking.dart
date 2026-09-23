import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';
import 'membership.dart';
import 'money.dart';
import 'service.dart';

/// Nested `outlet` in booking payloads.
class OutletSummary extends Equatable {
  const OutletSummary({
    required this.id,
    required this.name,
    this.rating,
    this.code,
  });
  final String id;
  final String name;
  final double? rating;
  final String? code;

  factory OutletSummary.fromJson(Json json) => OutletSummary(
    id: str(json['id']),
    name: str(json['name']),
    rating: dblOrNull(json['rating']),
    code: strOrNull(json['code']),
  );
  Json toJson() =>
      compact({'id': id, 'name': name, 'rating': rating, 'code': code});
  @override
  List<Object?> get props => [id, name, rating];
}

/// Nested `service` in booking payloads.
class ServiceSummary extends Equatable {
  const ServiceSummary({
    required this.id,
    required this.name,
    this.durationMinutes,
    this.category,
    this.icon,
  });
  final String id;
  final String name;
  final int? durationMinutes;
  final ServiceCategory? category;
  final String? icon;

  factory ServiceSummary.fromJson(Json json) => ServiceSummary(
    id: str(json['id']),
    name: str(json['name']),
    durationMinutes: intOrNull(json['duration_minutes']),
    category: json['category'] == null
        ? null
        : ServiceCategory.fromDb(strOrNull(json['category'])),
    icon: strOrNull(json['icon']),
  );
  Json toJson() => compact({
    'id': id,
    'name': name,
    'duration_minutes': durationMinutes,
    'category': category?.db,
    'icon': icon,
  });
  @override
  List<Object?> get props => [id, name, durationMinutes, category];
}

/// Nested `vehicle` in booking/task payloads.
class VehicleSummary extends Equatable {
  const VehicleSummary({
    required this.id,
    required this.registrationNo,
    this.make,
    this.model,
  });
  final String id;
  final String registrationNo;
  final String? make;
  final String? model;

  String get displayName =>
      [make, model].where((s) => s != null && s.isNotEmpty).join(' ');
  String get shortName =>
      (model?.isNotEmpty ?? false) ? model! : (make ?? registrationNo);

  factory VehicleSummary.fromJson(Json json) => VehicleSummary(
    id: str(json['id']),
    registrationNo: str(json['registration_no']),
    make: strOrNull(json['make']),
    model: strOrNull(json['model']),
  );
  Json toJson() => compact({
    'id': id,
    'registration_no': registrationNo,
    'make': make,
    'model': model,
  });
  @override
  List<Object?> get props => [id, registrationNo, make, model];
}

/// Nested `work_order` in booking payloads.
class WorkOrderSummary extends Equatable {
  const WorkOrderSummary({
    required this.id,
    required this.ref,
    required this.status,
    this.stage = 0,
    this.stageCount = 0,
    this.progressPct = 0,
    this.assigneeName,
    this.bay,
    this.etaAt,
    this.updatedAt,
    this.stageTitle,
    this.pickupOtp,
    this.pickupOtpVerifiedAt,
    this.collectedAt,
    this.checkedInAt,
  });

  final String id;
  final String ref;
  final WorkStatus status;
  final int stage;
  final int stageCount;
  final int progressPct;
  final String? assigneeName;
  final String? bay;
  final DateTime? etaAt;
  final DateTime? updatedAt;

  /// Current stage title when provided.
  final String? stageTitle;

  /// 5-digit collection OTP. Only present for the owning customer while the
  /// booking is `completed` and the vehicle has not been collected yet.
  final String? pickupOtp;
  final DateTime? pickupOtpVerifiedAt;

  /// Set once staff verified the OTP and released the keys.
  final DateTime? collectedAt;

  /// When the car was confirmed on site. Every confirmed booking has its
  /// work order at once (`checked_in_at: null` = awaiting check-in); the
  /// check-in (`POST /bookings/:id/checkin`) stamps this on the same row.
  final DateTime? checkedInAt;

  bool get isCollected => collectedAt != null;
  bool get isCheckedIn => checkedInAt != null;

  /// On the board but the car has not been confirmed on site yet.
  bool get awaitingCheckIn => !isCheckedIn && status.isOpen;

  /// The customer can show an OTP at the counter.
  bool get awaitingCollection => pickupOtp != null && collectedAt == null;

  double get progress => stageCount == 0
      ? progressPct / 100
      : (progressPct > 0 ? progressPct / 100 : stage / stageCount);

  /// "Pieter" from "Pieter van der Merwe".
  String? get assigneeFirstName => assigneeName?.split(' ').first;

  factory WorkOrderSummary.fromJson(Json json) => WorkOrderSummary(
    id: str(json['id']),
    ref: str(json['ref']),
    status: WorkStatus.fromDb(strOrNull(json['status'])),
    stage: intOf(json['stage']),
    stageCount: intOf(json['stage_count']),
    progressPct: intOf(json['progress_pct']),
    assigneeName: strOrNull(json['assignee_name']),
    bay: strOrNull(json['bay']),
    etaAt: dtOrNull(json['eta_at']),
    updatedAt: dtOrNull(json['updated_at']),
    stageTitle: strOrNull(json['stage_title']),
    pickupOtp: strOrNull(json['pickup_otp']),
    pickupOtpVerifiedAt: dtOrNull(json['pickup_otp_verified_at']),
    collectedAt: dtOrNull(json['collected_at']),
    checkedInAt: dtOrNull(json['checked_in_at']),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'status': status.db,
    'stage': stage,
    'stage_count': stageCount,
    'progress_pct': progressPct,
    'assignee_name': assigneeName,
    'bay': bay,
    'eta_at': iso(etaAt),
    'updated_at': iso(updatedAt),
    'stage_title': stageTitle,
    'pickup_otp': pickupOtp,
    'pickup_otp_verified_at': iso(pickupOtpVerifiedAt),
    'collected_at': iso(collectedAt),
    'checked_in_at': iso(checkedInAt),
  });

  WorkOrderSummary copyWith({
    WorkStatus? status,
    int? stage,
    int? stageCount,
    int? progressPct,
    String? assigneeName,
    String? bay,
    DateTime? etaAt,
    DateTime? updatedAt,
    String? stageTitle,
    String? pickupOtp,
    DateTime? pickupOtpVerifiedAt,
    DateTime? collectedAt,
    DateTime? checkedInAt,
    bool clearPickupOtp = false,
  }) => WorkOrderSummary(
    id: id,
    ref: ref,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    stageCount: stageCount ?? this.stageCount,
    progressPct: progressPct ?? this.progressPct,
    assigneeName: assigneeName ?? this.assigneeName,
    bay: bay ?? this.bay,
    etaAt: etaAt ?? this.etaAt,
    updatedAt: updatedAt ?? this.updatedAt,
    stageTitle: stageTitle ?? this.stageTitle,
    pickupOtp: clearPickupOtp ? null : (pickupOtp ?? this.pickupOtp),
    pickupOtpVerifiedAt: pickupOtpVerifiedAt ?? this.pickupOtpVerifiedAt,
    collectedAt: collectedAt ?? this.collectedAt,
    checkedInAt: checkedInAt ?? this.checkedInAt,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    stage,
    stageCount,
    progressPct,
    assigneeName,
    bay,
    etaAt,
    updatedAt,
    pickupOtp,
    pickupOtpVerifiedAt,
    collectedAt,
    checkedInAt,
  ];
}

/// Timeline stage state.
enum TimelineEntryState {
  done,
  current,
  pending;

  static TimelineEntryState fromDb(String? v) => switch (v) {
    'done' => done,
    'current' => current,
    _ => pending,
  };
}

/// `timeline[]` entry derived from the checklist template + results.
class TimelineEntry extends Equatable {
  const TimelineEntry({
    required this.key,
    required this.title,
    required this.state,
    this.at,
    this.note,
    this.actorName,
  });
  final String key;
  final String title;
  final TimelineEntryState state;
  final DateTime? at;
  final String? note;
  final String? actorName;

  factory TimelineEntry.fromJson(Json json) => TimelineEntry(
    key: str(json['key']),
    title: str(json['title']),
    state: TimelineEntryState.fromDb(strOrNull(json['state'])),
    at: dtOrNull(json['at']),
    note: strOrNull(json['note']),
    actorName: strOrNull(json['actor_name']),
  );
  Json toJson() => compact({
    'key': key,
    'title': title,
    'state': state.name,
    'at': iso(at),
    'note': note,
    'actor_name': actorName,
  });

  TimelineEntry copyWith({
    TimelineEntryState? state,
    DateTime? at,
    String? note,
  }) => TimelineEntry(
    key: key,
    title: title,
    state: state ?? this.state,
    at: at ?? this.at,
    note: note ?? this.note,
    actorName: actorName,
  );

  @override
  List<Object?> get props => [key, title, state, at, note];
}

/// Nested `payment` in `GET /bookings/:id` and `GET /quotations/:id`
/// (`{ id, receipt_no, amount_cents, method, verified_at }` — a quotation
/// payment is always the successful counter payment, so a missing `status`
/// with a `verified_at` reads as `successful`).
class PaymentSummary extends Equatable {
  const PaymentSummary({
    required this.id,
    required this.status,
    required this.amountCents,
    this.receiptNo,
    this.method,
    this.verifiedAt,
  });
  final String id;
  final PaymentStatus status;
  final int amountCents;
  final String? receiptNo;

  /// `cash` / `card_terminal` for counter payments, `card` / `eft` online.
  final String? method;
  final DateTime? verifiedAt;

  bool get isVerified => status.isVerified;

  /// "cash" / "card terminal" / "card" for receipts and status lines.
  String? get methodLabel => switch (method) {
    null => null,
    'card_terminal' => 'card terminal',
    final m => m.replaceAll('_', ' '),
  };

  factory PaymentSummary.fromJson(Json json) {
    final verifiedAt = dtOrNull(json['verified_at']);
    final rawStatus = strOrNull(json['status']);
    return PaymentSummary(
      id: str(json['id']),
      status: rawStatus == null && verifiedAt != null
          ? PaymentStatus.successful
          : PaymentStatus.fromDb(rawStatus),
      amountCents: intOf(json['amount_cents']),
      receiptNo: strOrNull(json['receipt_no']),
      method: strOrNull(json['method']),
      verifiedAt: verifiedAt,
    );
  }
  Json toJson() => compact({
    'id': id,
    'status': status.db,
    'amount_cents': amountCents,
    'receipt_no': receiptNo,
    'method': method,
    'verified_at': iso(verifiedAt),
  });
  @override
  List<Object?> get props => [
    id,
    status,
    amountCents,
    receiptNo,
    method,
    verifiedAt,
  ];
}

/// An add-on attached to a booking (`addon_service_ids` expanded).
class BookingAddon extends Equatable {
  const BookingAddon({
    required this.serviceId,
    required this.name,
    required this.priceCents,
  });
  final String serviceId;
  final String name;
  final int priceCents;

  factory BookingAddon.fromJson(Json json) => BookingAddon(
    serviceId: str(json['service_id'] ?? json['id']),
    name: str(json['name']),
    priceCents: intOf(json['price_cents']),
  );
  Json toJson() => {
    'service_id': serviceId,
    'name': name,
    'price_cents': priceCents,
  };
  @override
  List<Object?> get props => [serviceId, name, priceCents];
}

/// Server-side price of a booking before it is created (`priceService`):
/// base for the vehicle size, add-ons, plan / tier discount, VAT, total,
/// points and the `membership` block (docs/MEMBERSHIPS.md "Pricing rules").
class PriceQuote extends Equatable {
  const PriceQuote({
    required this.priceCents,
    required this.totalCents,
    this.addons = const [],
    this.addonsCents = 0,
    this.discountCents = 0,
    this.discountLabel,
    this.vatCents = 0,
    this.pointsPending = 0,
    this.vehicleSize,
    this.pricingMode,
    this.vatMode,
    this.membership,
  });

  final int priceCents;
  final List<BookingAddon> addons;
  final int addonsCents;
  final int discountCents;

  /// "Included in Gold · 2 of 4 left" / "Platinum −10%"
  final String? discountLabel;
  final int vatCents;
  final int totalCents;
  final int pointsPending;
  final VehicleSize? vehicleSize;
  final PricingMode? pricingMode;
  final VatMode? vatMode;

  /// `null` when the customer has no active plan.
  final BookingMembership? membership;

  int get subtotalCents => priceCents + addonsCents;
  bool get isIncluded => membership?.isIncluded ?? false;
  MembershipBenefit? get membershipBenefit => membership?.benefit;

  factory PriceQuote.fromJson(Json json) => PriceQuote(
    priceCents: intOf(json['price_cents']),
    addons: asJsonList(json['addons']).map(BookingAddon.fromJson).toList(),
    addonsCents: intOf(json['addons_cents']),
    discountCents: intOf(json['discount_cents']),
    discountLabel: strOrNull(json['discount_label']),
    vatCents: intOf(json['vat_cents']),
    totalCents: intOf(json['total_cents']),
    pointsPending: intOf(json['points_pending']),
    vehicleSize: json['vehicle_size'] == null
        ? null
        : VehicleSize.fromDb(strOrNull(json['vehicle_size'])),
    pricingMode: json['pricing_mode'] == null
        ? null
        : PricingMode.fromDb(strOrNull(json['pricing_mode'])),
    vatMode: json['vat_mode'] == null
        ? null
        : VatMode.fromDb(strOrNull(json['vat_mode'])),
    membership: json['membership'] is Map
        ? BookingMembership.fromJson(asJson(json['membership']))
        : null,
  );

  Json toJson() => compact({
    'price_cents': priceCents,
    'addons': addons.map((a) => a.toJson()).toList(),
    'addons_cents': addonsCents,
    'discount_cents': discountCents,
    'discount_label': discountLabel,
    'vat_cents': vatCents,
    'total_cents': totalCents,
    'points_pending': pointsPending,
    'vehicle_size': vehicleSize?.db,
    'pricing_mode': pricingMode?.db,
    'vat_mode': vatMode?.db,
    'membership': membership?.toJson(),
  });

  @override
  List<Object?> get props => [
    priceCents,
    addons,
    addonsCents,
    discountCents,
    discountLabel,
    vatCents,
    totalCents,
    pointsPending,
    vehicleSize,
    membership,
  ];
}

/// `bookings` row plus the expansions from `GET /bookings` and `GET /bookings/:id`
/// (see the reference payload in docs/API.md).
class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.ref,
    required this.customerId,
    required this.status,
    required this.slotStart,
    required this.slotEnd,
    this.vehicleId,
    this.outletId,
    this.serviceId,
    this.quotationId,
    this.priceCents = 0,
    this.discountCents = 0,
    this.totalCents = 0,
    this.discountLabel,
    this.vehicleSize,
    this.pricingMode,
    this.vatMode,
    this.addons = const [],
    this.addonsCents = 0,
    this.vatCents = 0,
    this.pointsPending = 0,
    this.notes,
    this.cancelReason,
    this.clientOpId,
    this.createdAt,
    this.updatedAt,
    this.outlet,
    this.service,
    this.vehicle,
    this.workOrder,
    this.timeline = const [],
    this.payment,
    this.pendingSync = false,
    this.membershipId,
    this.entitlementId,
    this.membershipBenefit,
    this.membership,
    this.paymentMethod,
  });

  final String id;
  final String ref;
  final String customerId;
  final BookingStatus status;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String? vehicleId;
  final String? outletId;
  final String? serviceId;
  final String? quotationId;
  final int priceCents;
  final int discountCents;
  final int totalCents;

  /// e.g. "Gold −10%"
  final String? discountLabel;

  /// Size the price was resolved for (`vehicle_size`).
  final VehicleSize? vehicleSize;

  /// Pricing basis recorded at booking time.
  final PricingMode? pricingMode;
  final VatMode? vatMode;

  /// Add-ons attached to the booking (`addon_service_ids` expanded).
  final List<BookingAddon> addons;

  /// Sum of the add-on prices (`addons_cents`).
  final int addonsCents;

  /// VAT added on `excl` totals (`vat_cents`).
  final int vatCents;

  /// Points that post on completion (CUS-064).
  final int pointsPending;
  final String? notes;
  final String? cancelReason;
  final String? clientOpId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Expansions
  final OutletSummary? outlet;
  final ServiceSummary? service;
  final VehicleSummary? vehicle;
  final WorkOrderSummary? workOrder;
  final List<TimelineEntry> timeline;
  final PaymentSummary? payment;

  /// `true` for the optimistic copy returned while the create is queued
  /// offline (`booking.create_walk_in`); the server row replaces it on sync.
  final bool pendingSync;

  /// Plan redemption recorded on the booking (`bookings.membership_id`,
  /// `entitlement_id`, `membership_benefit`) and the expanded `membership`
  /// block (docs/MEMBERSHIPS.md).
  final String? membershipId;
  final String? entitlementId;
  final MembershipBenefit? membershipBenefit;
  final BookingMembership? membership;

  /// How the customer chose to pay (`bookings.payment_method`); `cash` means
  /// **cash on collection** — confirmed without an online payment, settled at
  /// the counter before the keys are released.
  final PaymentChoice? paymentMethod;

  bool get isCashOnCollection => paymentMethod == PaymentChoice.cash;

  /// Cash still to be collected at the counter (no verified payment yet).
  bool get isCashDue => isCashOnCollection && totalCents > 0 && !isPaid;

  /// The service was covered by the customer's plan (base price waived).
  bool get isIncluded =>
      membershipBenefit == MembershipBenefit.included ||
      (membership?.isIncluded ?? false);

  bool get isPaid => payment?.status.isVerified ?? false;
  bool get canCancel => status.canCancel;
  bool get isUpcoming =>
      status == BookingStatus.confirmed || status == BookingStatus.pending;
  bool get isInService => status == BookingStatus.inService;

  /// Confirmed with its work order on the board, car not yet on site
  /// (`work_order.checked_in_at == null`).
  bool get isAwaitingCheckIn =>
      isUpcoming && workOrder != null && !workOrder!.isCheckedIn;

  /// Completed, keys not yet released and the API exposed the collection OTP
  /// (only the owning customer receives it).
  bool get isReadyForCollection =>
      status == BookingStatus.completed &&
      (workOrder?.awaitingCollection ?? false);

  /// Collection OTP to show at the counter, when [isReadyForCollection].
  String? get pickupOtp => isReadyForCollection ? workOrder!.pickupOtp : null;

  /// Base + add-ons before the tier discount and VAT.
  int get subtotalCents => priceCents + addonsCents;

  /// `From R 150` / `R 400 excl. VAT` style label for the base price.
  String get priceLabel {
    final amount = Money.formatZarCompact(priceCents).replaceFirst('R', 'R ');
    final prefix = pricingMode == PricingMode.from ? 'From ' : '';
    final suffix = vatMode == VatMode.excl ? ' excl. VAT' : '';
    return '$prefix$amount$suffix';
  }

  bool get hasAddons => addons.isNotEmpty || addonsCents > 0;
  bool get hasVat => vatCents > 0 || vatMode == VatMode.excl;

  /// "Full Valet — Corolla Cross"
  String get title => [
    service?.name,
    vehicle?.shortName,
  ].where((s) => s != null && s.isNotEmpty).join(' — ');

  factory Booking.fromJson(Json json) => Booking(
    id: str(json['id']),
    ref: str(json['ref']),
    customerId: str(json['customer_id']),
    status: BookingStatus.fromDb(strOrNull(json['status'])),
    slotStart: dt(json['slot_start']),
    slotEnd: dt(json['slot_end']),
    vehicleId:
        strOrNull(json['vehicle_id']) ??
        strOrNull(asJsonOrNull(json['vehicle'])?['id']),
    outletId:
        strOrNull(json['outlet_id']) ??
        strOrNull(asJsonOrNull(json['outlet'])?['id']),
    serviceId:
        strOrNull(json['service_id']) ??
        strOrNull(asJsonOrNull(json['service'])?['id']),
    quotationId: strOrNull(json['quotation_id']),
    priceCents: intOf(json['price_cents']),
    discountCents: intOf(json['discount_cents']),
    totalCents: intOf(json['total_cents']),
    discountLabel: strOrNull(json['discount_label']),
    vehicleSize: json['vehicle_size'] == null
        ? null
        : VehicleSize.fromDb(strOrNull(json['vehicle_size'])),
    pricingMode: json['pricing_mode'] == null
        ? null
        : PricingMode.fromDb(strOrNull(json['pricing_mode'])),
    vatMode: json['vat_mode'] == null
        ? null
        : VatMode.fromDb(strOrNull(json['vat_mode'])),
    addons: asJsonList(json['addons']).map(BookingAddon.fromJson).toList(),
    addonsCents: intOf(json['addons_cents']),
    vatCents: intOf(json['vat_cents']),
    pointsPending: intOf(json['points_pending']),
    notes: strOrNull(json['notes']),
    cancelReason: strOrNull(json['cancel_reason']),
    clientOpId: strOrNull(json['client_op_id']),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
    outlet: json['outlet'] is Map
        ? OutletSummary.fromJson(asJson(json['outlet']))
        : null,
    service: json['service'] is Map
        ? ServiceSummary.fromJson(asJson(json['service']))
        : null,
    vehicle: json['vehicle'] is Map
        ? VehicleSummary.fromJson(asJson(json['vehicle']))
        : null,
    workOrder: json['work_order'] is Map
        ? WorkOrderSummary.fromJson(asJson(json['work_order']))
        : null,
    timeline: asJsonList(json['timeline']).map(TimelineEntry.fromJson).toList(),
    payment: json['payment'] is Map
        ? PaymentSummary.fromJson(asJson(json['payment']))
        : null,
    pendingSync: boolOf(json['pending_sync']),
    membershipId: strOrNull(json['membership_id']),
    entitlementId: strOrNull(json['entitlement_id']),
    membershipBenefit:
        MembershipBenefit.fromDb(strOrNull(json['membership_benefit'])) ??
        (json['membership'] is Map
            ? MembershipBenefit.fromDb(
                strOrNull(asJson(json['membership'])['benefit']),
              )
            : null),
    membership: json['membership'] is Map
        ? BookingMembership.fromJson(asJson(json['membership']))
        : null,
    paymentMethod: PaymentChoice.fromDb(strOrNull(json['payment_method'])),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'customer_id': customerId,
    'status': status.db,
    'slot_start': iso(slotStart),
    'slot_end': iso(slotEnd),
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'service_id': serviceId,
    'quotation_id': quotationId,
    'price_cents': priceCents,
    'discount_cents': discountCents,
    'total_cents': totalCents,
    'discount_label': discountLabel,
    'vehicle_size': vehicleSize?.db,
    'pricing_mode': pricingMode?.db,
    'vat_mode': vatMode?.db,
    'addons': addons.isEmpty ? null : addons.map((a) => a.toJson()).toList(),
    'addon_service_ids': addons.isEmpty
        ? null
        : addons.map((a) => a.serviceId).toList(),
    'addons_cents': addonsCents,
    'vat_cents': vatCents,
    'points_pending': pointsPending,
    'notes': notes,
    'cancel_reason': cancelReason,
    'client_op_id': clientOpId,
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'outlet': outlet?.toJson(),
    'service': service?.toJson(),
    'vehicle': vehicle?.toJson(),
    'work_order': workOrder?.toJson(),
    'timeline': timeline.isEmpty
        ? null
        : timeline.map((t) => t.toJson()).toList(),
    'payment': payment?.toJson(),
    'pending_sync': pendingSync ? true : null,
    'membership_id': membershipId,
    'entitlement_id': entitlementId,
    'membership_benefit': membershipBenefit?.db,
    'membership': membership?.toJson(),
    'payment_method': paymentMethod?.db,
  });

  Booking copyWith({
    BookingStatus? status,
    DateTime? slotStart,
    DateTime? slotEnd,
    int? priceCents,
    int? discountCents,
    int? totalCents,
    String? discountLabel,
    int? pointsPending,
    String? notes,
    String? cancelReason,
    DateTime? updatedAt,
    OutletSummary? outlet,
    ServiceSummary? service,
    VehicleSummary? vehicle,
    WorkOrderSummary? workOrder,
    List<TimelineEntry>? timeline,
    PaymentSummary? payment,
    bool clearWorkOrder = false,
    bool? pendingSync,
  }) => Booking(
    id: id,
    ref: ref,
    customerId: customerId,
    status: status ?? this.status,
    slotStart: slotStart ?? this.slotStart,
    slotEnd: slotEnd ?? this.slotEnd,
    vehicleId: vehicleId,
    outletId: outletId,
    serviceId: serviceId,
    quotationId: quotationId,
    priceCents: priceCents ?? this.priceCents,
    discountCents: discountCents ?? this.discountCents,
    totalCents: totalCents ?? this.totalCents,
    discountLabel: discountLabel ?? this.discountLabel,
    vehicleSize: vehicleSize,
    pricingMode: pricingMode,
    vatMode: vatMode,
    addons: addons,
    addonsCents: addonsCents,
    vatCents: vatCents,
    pointsPending: pointsPending ?? this.pointsPending,
    notes: notes ?? this.notes,
    cancelReason: cancelReason ?? this.cancelReason,
    clientOpId: clientOpId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    outlet: outlet ?? this.outlet,
    service: service ?? this.service,
    vehicle: vehicle ?? this.vehicle,
    workOrder: clearWorkOrder ? null : (workOrder ?? this.workOrder),
    timeline: timeline ?? this.timeline,
    payment: payment ?? this.payment,
    pendingSync: pendingSync ?? this.pendingSync,
    membershipId: membershipId,
    entitlementId: entitlementId,
    membershipBenefit: membershipBenefit,
    membership: membership,
    paymentMethod: paymentMethod,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    slotStart,
    slotEnd,
    totalCents,
    addonsCents,
    vatCents,
    pointsPending,
    workOrder,
    timeline,
    payment,
    updatedAt,
    pendingSync,
    membershipBenefit,
    paymentMethod,
  ];
}

/// Body for `POST /bookings`.
class BookingInput {
  const BookingInput({
    required this.vehicleId,
    required this.outletId,
    required this.serviceId,
    required this.slotStart,
    required this.clientOpId,
    this.notes,
    this.vehicleSize,
    this.addonServiceIds = const [],
    this.paymentMethod,
  });

  final String vehicleId;
  final String outletId;
  final String serviceId;
  final DateTime slotStart;
  final String clientOpId;
  final String? notes;

  /// Size to price for (defaults to the vehicle's `size_class` server-side).
  final VehicleSize? vehicleSize;

  /// Add-ons (`is_addon` services of the service's group).
  final List<String> addonServiceIds;

  /// `payment_method`: `cash` confirms the booking for payment at the counter
  /// (409 `validation_error {reason: 'cash_disabled'}` when the
  /// `cash_on_collection` flag is off); `card` / `eft` are informational.
  final PaymentChoice? paymentMethod;

  Json toJson() => compact({
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'service_id': serviceId,
    'slot_start': iso(slotStart),
    'client_op_id': clientOpId,
    'notes': notes,
    'vehicle_size': vehicleSize?.db,
    'addon_service_ids': addonServiceIds.isEmpty ? null : addonServiceIds,
    'payment_method': paymentMethod?.db,
  });

  factory BookingInput.fromJson(Json json) => BookingInput(
    vehicleId: str(json['vehicle_id']),
    outletId: str(json['outlet_id']),
    serviceId: str(json['service_id']),
    slotStart: dt(json['slot_start']),
    clientOpId: str(json['client_op_id']),
    notes: strOrNull(json['notes']),
    vehicleSize: json['vehicle_size'] == null
        ? null
        : VehicleSize.fromDb(strOrNull(json['vehicle_size'])),
    addonServiceIds: asStringList(json['addon_service_ids']),
    paymentMethod: PaymentChoice.fromDb(strOrNull(json['payment_method'])),
  );
}
