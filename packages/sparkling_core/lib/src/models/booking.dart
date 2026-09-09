import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

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

/// Nested `payment` in `GET /bookings/:id`.
class PaymentSummary extends Equatable {
  const PaymentSummary({
    required this.id,
    required this.status,
    required this.amountCents,
    this.receiptNo,
  });
  final String id;
  final PaymentStatus status;
  final int amountCents;
  final String? receiptNo;

  factory PaymentSummary.fromJson(Json json) => PaymentSummary(
    id: str(json['id']),
    status: PaymentStatus.fromDb(strOrNull(json['status'])),
    amountCents: intOf(json['amount_cents']),
    receiptNo: strOrNull(json['receipt_no']),
  );
  Json toJson() => compact({
    'id': id,
    'status': status.db,
    'amount_cents': amountCents,
    'receipt_no': receiptNo,
  });
  @override
  List<Object?> get props => [id, status, amountCents, receiptNo];
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

  bool get isPaid => payment?.status.isVerified ?? false;
  bool get canCancel => status.canCancel;
  bool get isUpcoming =>
      status == BookingStatus.confirmed || status == BookingStatus.pending;
  bool get isInService => status == BookingStatus.inService;

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
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    slotStart,
    slotEnd,
    totalCents,
    pointsPending,
    workOrder,
    timeline,
    payment,
    updatedAt,
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
  });

  final String vehicleId;
  final String outletId;
  final String serviceId;
  final DateTime slotStart;
  final String clientOpId;
  final String? notes;

  Json toJson() => compact({
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'service_id': serviceId,
    'slot_start': iso(slotStart),
    'client_op_id': clientOpId,
    'notes': notes,
  });

  factory BookingInput.fromJson(Json json) => BookingInput(
    vehicleId: str(json['vehicle_id']),
    outletId: str(json['outlet_id']),
    serviceId: str(json['service_id']),
    slotStart: dt(json['slot_start']),
    clientOpId: str(json['client_op_id']),
    notes: strOrNull(json['notes']),
  );
}
