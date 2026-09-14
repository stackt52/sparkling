import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';
import 'service.dart';
import 'vehicle.dart';

/// Vehicle row nested in `GET /staff/customers` results.
class CustomerVehicleSummary extends Equatable {
  const CustomerVehicleSummary({
    required this.id,
    required this.registrationNo,
    this.make,
    this.model,
    this.colour,
    this.discVerified = false,
    this.sizeClass = VehicleSize.small,
  });

  final String id;
  final String registrationNo;
  final String? make;
  final String? model;
  final String? colour;
  final bool discVerified;

  /// Pricing size (`size_class`).
  final VehicleSize sizeClass;

  /// "Toyota Corolla Cross"
  String get displayName =>
      [make, model].where((s) => s != null && s.isNotEmpty).join(' ');

  /// "Corolla Cross" when a model exists, otherwise make or the plate.
  String get shortName =>
      (model?.isNotEmpty ?? false) ? model! : (make ?? registrationNo);

  String get normalisedRegistration =>
      Vehicle.normaliseRegistration(registrationNo);

  factory CustomerVehicleSummary.fromJson(Json json) => CustomerVehicleSummary(
    id: str(json['id']),
    registrationNo: str(json['registration_no']),
    make: strOrNull(json['make']),
    model: strOrNull(json['model']),
    colour: strOrNull(json['colour']),
    discVerified: boolOf(json['disc_verified']),
    sizeClass: VehicleSize.fromDb(strOrNull(json['size_class'])),
  );

  factory CustomerVehicleSummary.fromVehicle(Vehicle v) =>
      CustomerVehicleSummary(
        id: v.id,
        registrationNo: v.registrationNo,
        make: v.make,
        model: v.model,
        colour: v.colour,
        discVerified: v.discVerified,
        sizeClass: v.sizeClass,
      );

  Json toJson() => compact({
    'id': id,
    'registration_no': registrationNo,
    'make': make,
    'model': model,
    'colour': colour,
    'disc_verified': discVerified,
    'size_class': sizeClass.db,
  });

  @override
  List<Object?> get props => [
    id,
    registrationNo,
    make,
    model,
    discVerified,
    sizeClass,
  ];
}

/// Loyalty snapshot nested in a [CustomerSummary] (`null` when the customer
/// has no account yet).
class CustomerLoyaltySummary extends Equatable {
  const CustomerLoyaltySummary({
    required this.tier,
    this.balancePoints = 0,
    this.discountPct,
    this.planCode,
    this.planName,
    this.includedRemaining,
  });
  final LoyaltyTier tier;
  final int balancePoints;

  /// Booking discount % for [tier] from the published loyalty config, as
  /// returned by the API; null when unknown (older responses). Since
  /// membership plans this is 0 — discounts come from the plan.
  final int? discountPct;

  /// Live membership plan (`plan_code` / `plan_name`), null without a plan.
  final String? planCode;
  final String? planName;

  /// Remaining monthly washes across the plan's allowances
  /// ("Gold · 3 washes left").
  final int? includedRemaining;

  bool get hasPlan => planCode != null;

  /// "Gold · 3 washes left" (null without a plan).
  String? get planLabel {
    if (planCode == null) return null;
    final n = includedRemaining;
    if (n == null) return planName ?? planCode;
    return '${planName ?? planCode} · $n wash${n == 1 ? '' : 'es'} left';
  }

  factory CustomerLoyaltySummary.fromJson(Json json) => CustomerLoyaltySummary(
    tier: LoyaltyTier.fromDb(strOrNull(json['tier'])),
    balancePoints: intOf(json['balance_points']),
    discountPct: json['discount_pct'] == null
        ? null
        : intOf(json['discount_pct']),
    planCode: strOrNull(json['plan_code']),
    planName: strOrNull(json['plan_name']),
    includedRemaining: intOrNull(json['included_remaining']),
  );
  Json toJson() => {
    'tier': tier.db,
    'balance_points': balancePoints,
    if (discountPct != null) 'discount_pct': discountPct,
    if (planCode != null) 'plan_code': planCode,
    if (planName != null) 'plan_name': planName,
    if (includedRemaining != null) 'included_remaining': includedRemaining,
  };
  @override
  List<Object?> get props => [
    tier,
    balancePoints,
    discountPct,
    planCode,
    planName,
    includedRemaining,
  ];
}

/// Customer as returned by `GET /staff/customers` / `POST /staff/customers`
/// (STF-010/012 walk-in flow).
class CustomerSummary extends Equatable {
  const CustomerSummary({
    required this.id,
    required this.fullName,
    this.email,
    this.phone,
    this.marketingOptIn = false,
    this.whatsappOptIn = true,
    this.loyalty,
    this.vehicles = const [],
  });

  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final bool marketingOptIn;
  final bool whatsappOptIn;
  final CustomerLoyaltySummary? loyalty;
  final List<CustomerVehicleSummary> vehicles;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  /// "TN" for "Thabo Nkosi".
  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Registered at the counter without an app account (`walkin_<uuid>`).
  bool get isWalkIn => id.startsWith('walkin_');

  LoyaltyTier get tier => loyalty?.tier ?? LoyaltyTier.silver;

  factory CustomerSummary.fromJson(Json json) => CustomerSummary(
    id: str(json['id']),
    fullName: str(json['full_name']),
    email: strOrNull(json['email']),
    phone: strOrNull(json['phone']),
    marketingOptIn: boolOf(json['marketing_opt_in']),
    whatsappOptIn: boolOf(json['whatsapp_opt_in'], true),
    loyalty: json['loyalty'] is Map
        ? CustomerLoyaltySummary.fromJson(asJson(json['loyalty']))
        : null,
    vehicles: asJsonList(
      json['vehicles'],
    ).map(CustomerVehicleSummary.fromJson).toList(),
  );

  Json toJson() => compact({
    'id': id,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'marketing_opt_in': marketingOptIn,
    'whatsapp_opt_in': whatsappOptIn,
    'loyalty': loyalty?.toJson(),
    'vehicles': vehicles.map((v) => v.toJson()).toList(),
  });

  CustomerSummary copyWith({
    List<CustomerVehicleSummary>? vehicles,
    CustomerLoyaltySummary? loyalty,
  }) => CustomerSummary(
    id: id,
    fullName: fullName,
    email: email,
    phone: phone,
    marketingOptIn: marketingOptIn,
    whatsappOptIn: whatsappOptIn,
    loyalty: loyalty ?? this.loyalty,
    vehicles: vehicles ?? this.vehicles,
  );

  @override
  List<Object?> get props => [
    id,
    fullName,
    email,
    phone,
    marketingOptIn,
    whatsappOptIn,
    loyalty,
    vehicles,
  ];
}

/// Body for `POST /staff/customers`.
class CustomerInput {
  const CustomerInput({
    required this.fullName,
    required this.phone,
    required this.clientOpId,
    this.email,
    this.marketingOptIn = false,
    this.whatsappOptIn = true,
  });

  final String fullName;
  final String phone;
  final String? email;
  final bool marketingOptIn;
  final bool whatsappOptIn;
  final String clientOpId;

  /// South African numbers to E.164: `082 123 4567` → `+27821234567`,
  /// `27 82 …` → `+2782…`; already-international numbers keep their `+`.
  static String normalisePhone(String raw) {
    final trimmed = raw.trim();
    final plus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (plus) return '+$digits';
    if (digits.startsWith('0') && digits.length == 10) {
      return '+27${digits.substring(1)}';
    }
    if (digits.startsWith('27') && digits.length == 11) return '+$digits';
    return '+$digits';
  }

  /// Digits only — the key used for duplicate detection.
  static String phoneKey(String? raw) =>
      raw == null ? '' : normalisePhone(raw).replaceAll('+', '');

  Json toJson() => compact({
    'full_name': fullName.trim(),
    'phone': normalisePhone(phone),
    'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
    'marketing_opt_in': marketingOptIn,
    'whatsapp_opt_in': whatsappOptIn,
    'client_op_id': clientOpId,
  });

  factory CustomerInput.fromJson(Json json) => CustomerInput(
    fullName: str(json['full_name']),
    phone: str(json['phone']),
    email: strOrNull(json['email']),
    marketingOptIn: boolOf(json['marketing_opt_in']),
    whatsappOptIn: boolOf(json['whatsapp_opt_in'], true),
    clientOpId: str(json['client_op_id']),
  );
}

/// Optional immediate check-in for a walk-in booking (`checkin: {bay, priority}`).
class WalkInCheckin extends Equatable {
  const WalkInCheckin({this.bay, this.priority});
  final String? bay;
  final int? priority;

  factory WalkInCheckin.fromJson(Json json) => WalkInCheckin(
    bay: strOrNull(json['bay']),
    priority: intOrNull(json['priority']),
  );
  Json toJson() => compact({'bay': bay, 'priority': priority});
  @override
  List<Object?> get props => [bay, priority];
}

/// Body for `POST /bookings` from the staff app: a walk-in booking on behalf
/// of [customerId]. [slotStart] omitted = now (rounded to the outlet grid).
class WalkInBookingInput {
  const WalkInBookingInput({
    required this.customerId,
    required this.vehicleId,
    required this.outletId,
    required this.serviceId,
    required this.clientOpId,
    this.slotStart,
    this.checkin,
    this.notes,
    this.vehicleSize,
    this.addonServiceIds = const [],
  });

  final String customerId;
  final String vehicleId;
  final String outletId;
  final String serviceId;
  final String clientOpId;
  final DateTime? slotStart;
  final WalkInCheckin? checkin;
  final String? notes;

  /// Size to price for (defaults to the vehicle's `size_class` server-side).
  final VehicleSize? vehicleSize;

  /// Add-ons (`is_addon` services of the service's group).
  final List<String> addonServiceIds;

  bool get isNow => slotStart == null;
  bool get checksIn => checkin != null;

  Json toJson() => compact({
    'customer_id': customerId,
    'walk_in': true,
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'service_id': serviceId,
    'slot_start': iso(slotStart),
    'checkin': checkin?.toJson(),
    'client_op_id': clientOpId,
    'notes': notes,
    'vehicle_size': vehicleSize?.db,
    'addon_service_ids': addonServiceIds.isEmpty ? null : addonServiceIds,
  });

  factory WalkInBookingInput.fromJson(Json json) => WalkInBookingInput(
    customerId: str(json['customer_id']),
    vehicleId: str(json['vehicle_id']),
    outletId: str(json['outlet_id']),
    serviceId: str(json['service_id']),
    clientOpId: str(json['client_op_id']),
    slotStart: dtOrNull(json['slot_start']),
    checkin: json['checkin'] is Map
        ? WalkInCheckin.fromJson(asJson(json['checkin']))
        : null,
    notes: strOrNull(json['notes']),
    vehicleSize: json['vehicle_size'] == null
        ? null
        : VehicleSize.fromDb(strOrNull(json['vehicle_size'])),
    addonServiceIds: asStringList(json['addon_service_ids']),
  );
}

/// In-person payment methods a staff member can attest (`POST /payments/record`).
enum PaymentMethodKind implements SparklingEnum {
  cash('cash'),
  cardTerminal('card_terminal');

  const PaymentMethodKind(this.db);
  @override
  final String db;

  static PaymentMethodKind fromDb(String? v) =>
      values.where((k) => k.db == v).firstOrNull ?? cash;

  String get label => switch (this) {
    cash => 'Cash',
    cardTerminal => 'Card terminal',
  };
}

/// Body for `POST /payments/record`.
class RecordPaymentInput {
  const RecordPaymentInput({
    required this.bookingId,
    required this.method,
    required this.amountCents,
    required this.idempotencyKey,
    this.reference,
    this.bookingClientOpId,
  });

  final String bookingId;
  final PaymentMethodKind method;
  final int amountCents;
  final String idempotencyKey;

  /// Terminal slip / till reference (optional).
  final String? reference;

  /// Set when the payment is queued offline behind a queued walk-in booking
  /// whose server id is not known yet: `booking_client_op_id` lets
  /// `POST /sync/batch` resolve the booking created earlier in the batch.
  final String? bookingClientOpId;

  RecordPaymentInput copyWith({String? bookingId, String? bookingClientOpId}) =>
      RecordPaymentInput(
        bookingId: bookingId ?? this.bookingId,
        method: method,
        amountCents: amountCents,
        idempotencyKey: idempotencyKey,
        reference: reference,
        bookingClientOpId: bookingClientOpId ?? this.bookingClientOpId,
      );

  Json toJson() => compact({
    'booking_id': bookingId,
    'booking_client_op_id': bookingClientOpId,
    'method': method.db,
    'reference': (reference?.trim().isEmpty ?? true) ? null : reference!.trim(),
    'amount_cents': amountCents,
    'idempotency_key': idempotencyKey,
  });

  factory RecordPaymentInput.fromJson(Json json) => RecordPaymentInput(
    bookingId: str(json['booking_id']),
    bookingClientOpId: strOrNull(json['booking_client_op_id']),
    method: PaymentMethodKind.fromDb(strOrNull(json['method'])),
    amountCents: intOf(json['amount_cents']),
    idempotencyKey:
        strOrNull(json['idempotency_key']) ?? str(json['client_op_id']),
    reference: strOrNull(json['reference']),
  );
}
