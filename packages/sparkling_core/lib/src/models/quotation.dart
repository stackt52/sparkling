import 'package:equatable/equatable.dart';

import 'booking.dart';
import 'enums.dart';
import 'json.dart';
import 'money.dart';

/// `quotations.line_items[]` / `items[]` entry — one attention area (dent,
/// scratch, bumper …) optionally tied to an auto-body `service_id`.
class LineItem extends Equatable {
  const LineItem({
    required this.label,
    required this.amountCents,
    this.quantity = 1,
    this.description,
    this.category,
    this.serviceId,
  });
  final String label;
  final int amountCents;
  final int quantity;
  final String? description;

  /// One of [QuoteCategories.all] (free text tolerated).
  final String? category;
  final String? serviceId;

  int get totalCents => amountCents * quantity;

  factory LineItem.fromJson(Json json) => LineItem(
    label: str(json['label']),
    amountCents: intOf(json['amount_cents']),
    quantity: intOf(json['quantity'], 1),
    description: strOrNull(json['description']),
    category: strOrNull(json['category']),
    serviceId: strOrNull(json['service_id']),
  );
  Json toJson() => compact({
    'label': label,
    'amount_cents': amountCents,
    'quantity': quantity == 1 ? null : quantity,
    'description': description,
    'category': category,
    'service_id': serviceId,
  });

  LineItem copyWith({
    String? label,
    int? amountCents,
    int? quantity,
    String? description,
    String? category,
    String? serviceId,
  }) => LineItem(
    label: label ?? this.label,
    amountCents: amountCents ?? this.amountCents,
    quantity: quantity ?? this.quantity,
    description: description ?? this.description,
    category: category ?? this.category,
    serviceId: serviceId ?? this.serviceId,
  );

  @override
  List<Object?> get props => [
    label,
    amountCents,
    quantity,
    description,
    category,
    serviceId,
  ];
}

/// `attachments` row. Damage photos (`kind: damage_photo`) are served through
/// the API at [url] (`/v1/quotations/:id/photos/:attachmentId`, bearer auth
/// required — never a raw bucket URL).
class Attachment extends Equatable {
  const Attachment({
    required this.id,
    this.entityType = 'quotation',
    this.entityId = '',
    this.storagePath = '',
    required this.mimeType,
    this.sizeBytes = 0,
    this.sha256,
    this.uploadedBy,
    this.createdAt,
    this.downloadUrl,
    this.kind = 'damage_photo',
    this.width,
    this.height,
    this.caption,
    this.url,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? sha256;
  final String? uploadedBy;
  final DateTime? createdAt;

  /// Signed/download URL when the API includes one (legacy field).
  final String? downloadUrl;

  /// `damage_photo` | `document`.
  final String kind;
  final int? width;
  final int? height;
  final String? caption;

  /// API path that streams the file (auth header required). Demo data uses
  /// the `demo://photo/<id>` scheme, resolved from memory by the repositories.
  final String? url;

  bool get isImage => mimeType.startsWith('image/');
  bool get isDamagePhoto => kind == 'damage_photo';

  /// Best URL to load the bytes from ([url] first, then [downloadUrl]).
  String? get imageUrl => url ?? downloadUrl;

  factory Attachment.fromJson(Json json) => Attachment(
    id: str(json['id']),
    entityType: str(json['entity_type'], 'quotation'),
    entityId: str(json['entity_id']),
    storagePath: str(json['storage_path']),
    mimeType: str(json['mime_type'], 'application/octet-stream'),
    sizeBytes: intOf(json['size_bytes']),
    sha256: strOrNull(json['sha256']),
    uploadedBy: strOrNull(json['uploaded_by']),
    createdAt: dtOrNull(json['created_at']),
    downloadUrl: strOrNull(json['download_url']),
    kind: str(json['kind'], 'damage_photo'),
    width: intOrNull(json['width']),
    height: intOrNull(json['height']),
    caption: strOrNull(json['caption']),
    url: strOrNull(json['url']),
  );

  Json toJson() => compact({
    'id': id,
    'entity_type': entityType,
    'entity_id': entityId,
    'storage_path': storagePath.isEmpty ? null : storagePath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'uploaded_by': uploadedBy,
    'created_at': iso(createdAt),
    'download_url': downloadUrl,
    'kind': kind,
    'width': width,
    'height': height,
    'caption': caption,
    'url': url,
  });

  Attachment copyWith({String? caption, String? url}) => Attachment(
    id: id,
    entityType: entityType,
    entityId: entityId,
    storagePath: storagePath,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    sha256: sha256,
    uploadedBy: uploadedBy,
    createdAt: createdAt,
    downloadUrl: downloadUrl,
    kind: kind,
    width: width,
    height: height,
    caption: caption ?? this.caption,
    url: url ?? this.url,
  );

  @override
  List<Object?> get props => [
    id,
    entityType,
    entityId,
    storagePath,
    mimeType,
    sizeBytes,
    kind,
    caption,
    url,
  ];
}

/// Body for `POST /quotations/:id/attachments`.
class AttachmentInput {
  const AttachmentInput({
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    this.sha256,
  });
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? sha256;
  Json toJson() => compact({
    'storage_path': storagePath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'sha256': sha256,
  });
}

/// Repair categories accepted by `POST /quotations`.
abstract final class QuoteCategories {
  static const List<String> all = [
    'Dent',
    'Scratch',
    'Bumper',
    'Panel',
    'Paint',
    'Glass',
    'Other',
  ];

  /// Auto-body service code that usually matches [category]
  /// (`Dent` → `PDR`, `Bumper` → `BUMPER_SCUFF`).
  static String? serviceCodeFor(String category) => switch (category) {
    'Dent' => 'PDR',
    'Scratch' => 'SPOT_REPAIR',
    'Bumper' => 'BUMPER_SCUFF',
    'Panel' => 'SPOT_REPAIR',
    'Paint' => 'FLAT_POLISH',
    'Glass' => 'WINDSHIELD_REPAIR',
    _ => null,
  };

  /// Category to preselect when a customer requests a quote for a by-quote
  /// catalogue offer (`code` such as `CERAMIC_COATING`).
  static String categoryForServiceCode(String code) => switch (code) {
    'WINDSHIELD_REPAIR' || 'SMASH_GRAB' => 'Glass',
    'CERAMIC_COATING' => 'Paint',
    'MAG_WHEEL' || 'NUMBER_PLATE' => 'Other',
    _ => 'Other',
  };
}

/// How a quotation was decided (`quotations.decision_source`).
enum QuoteDecisionSource {
  app('app'),
  publicLink('public_link'),
  staff('staff');

  const QuoteDecisionSource(this.db);
  final String db;

  static QuoteDecisionSource? fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull;

  /// "in app" / "via link" / "by staff".
  String get label => switch (this) {
    app => 'in app',
    publicLink => 'via link',
    staff => 'by staff',
  };
}

/// Nested `work_order` on a quotation (`{ id, ref, status, checked_in_at }`).
/// Accepting a quotation creates its work order at once; it waits on the
/// board (`checked_in_at: null`) until the car is confirmed on site, which
/// also marks the quotation `converted`.
class QuotationWorkOrder extends Equatable {
  const QuotationWorkOrder({
    required this.id,
    required this.ref,
    required this.status,
    this.checkedInAt,
  });

  final String id;
  final String ref;
  final WorkStatus status;
  final DateTime? checkedInAt;

  bool get isCheckedIn => checkedInAt != null;

  /// Created on acceptance, car not on site yet.
  bool get awaitingCheckIn => !isCheckedIn && status.isOpen;

  factory QuotationWorkOrder.fromJson(Json json) => QuotationWorkOrder(
    id: str(json['id']),
    ref: str(json['ref']),
    status: WorkStatus.fromDb(strOrNull(json['status'])),
    checkedInAt: dtOrNull(json['checked_in_at']),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'status': status.db,
    'checked_in_at': iso(checkedInAt),
  });

  QuotationWorkOrder copyWith({WorkStatus? status, DateTime? checkedInAt}) =>
      QuotationWorkOrder(
        id: id,
        ref: ref,
        status: status ?? this.status,
        checkedInAt: checkedInAt ?? this.checkedInAt,
      );

  @override
  List<Object?> get props => [id, ref, status, checkedInAt];
}

/// `quotations` row (+ `attachments[]`, `work_order`, `payment` and
/// `amount_due_cents` on `GET /quotations/:id`).
class Quotation extends Equatable {
  const Quotation({
    required this.id,
    required this.ref,
    required this.customerId,
    required this.vehicleId,
    required this.outletId,
    required this.category,
    required this.description,
    required this.status,
    this.amountCents,
    this.lineItems = const [],
    this.assessorId,
    this.assessorName,
    this.validUntil,
    this.quotedAt,
    this.decidedAt,
    this.decisionBy,
    this.decisionNote,
    this.clientOpId,
    this.createdAt,
    this.updatedAt,
    this.attachments = const [],
    this.vehicleLabel,
    this.outletName,
    this.itemsNote,
    this.terms,
    this.decisionSource,
    this.decisionByName,
    this.publicUrl,
    this.pdfUrl,
    this.customerName,
    this.pendingSync = false,
    this.workOrder,
    this.workOrderRef,
    this.payment,
    int? amountDueCents,
  }) : // The wire field backs the `amountDueCents` getter (computed fallback).
       // ignore: prefer_initializing_formals
       _amountDueCents = amountDueCents;

  final String id;
  final String ref;
  final String customerId;
  final String vehicleId;
  final String outletId;
  final String category;
  final String description;
  final QuotationStatus status;
  final int? amountCents;
  final List<LineItem> lineItems;
  final String? assessorId;
  final String? assessorName;
  final DateTime? validUntil;
  final DateTime? quotedAt;
  final DateTime? decidedAt;
  final String? decisionBy;
  final String? decisionNote;
  final String? clientOpId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Attachment> attachments;

  /// "Corolla Cross · KL 45 MN GP" when expanded.
  final String? vehicleLabel;
  final String? outletName;

  /// Free-text note under the items table (staff-raised quotes).
  final String? itemsNote;

  /// Standard terms printed on the quotation (supplied by the API).
  final String? terms;
  final QuoteDecisionSource? decisionSource;

  /// Name given on the public page (or the customer's name when decided
  /// in-app).
  final String? decisionByName;

  /// `${PUBLIC_WEB_BASE_URL}/q/<token>` — staff responses only.
  final String? publicUrl;

  /// `/v1/quotations/:id/pdf`.
  final String? pdfUrl;

  /// Customer's full name when the API expands it (staff lists).
  final String? customerName;

  /// Raised offline — waiting in the sync queue for a server id / ref.
  final bool pendingSync;

  /// Work order created on acceptance (awaiting check-in until the car is
  /// confirmed on site, which makes the quotation `converted`).
  final QuotationWorkOrder? workOrder;

  /// `work_order_ref` — also set when only the ref is known.
  final String? workOrderRef;

  /// Successful counter payment (`POST /payments/record { quotation_id }`).
  final PaymentSummary? payment;
  final int? _amountDueCents;

  /// `amount_due_cents`: 0 once paid, otherwise the quoted total.
  int get amountDueCents =>
      _amountDueCents ?? (isPaid ? 0 : (amountCents ?? itemsTotalCents));

  bool get isPaid => payment?.isVerified ?? false;

  /// Accepted or converted with a total still to be settled at the counter.
  bool get isPaymentDue =>
      (status == QuotationStatus.accepted ||
          status == QuotationStatus.converted) &&
      !isPaid &&
      amountDueCents > 0;

  /// "Paid · cash · RCP-70007" / "R 2 850.00 due at the counter" — null
  /// before acceptance.
  String? get paymentLabel {
    final p = payment;
    if (p != null && p.isVerified) {
      return [
        'Paid',
        p.methodLabel,
        p.receiptNo,
      ].whereType<String>().join(' · ');
    }
    if (!isPaymentDue) return null;
    return '${Money.formatZar(amountDueCents)} due at the counter';
  }

  /// Alias of [lineItems] (`items` on the wire).
  List<LineItem> get items => lineItems;

  int get itemsTotalCents =>
      lineItems.fold(0, (sum, li) => sum + li.totalCents);

  bool get isExpired =>
      validUntil != null &&
      validUntil!.isBefore(DateTime.now()) &&
      status == QuotationStatus.quoted;

  /// Accepted or declined (decisions are one-time).
  bool get isDecided =>
      decidedAt != null ||
      status == QuotationStatus.accepted ||
      status == QuotationStatus.declined ||
      status == QuotationStatus.converted;

  /// Awaiting the customer's answer and still within [validUntil].
  bool get canDecide =>
      status == QuotationStatus.quoted && !isDecided && !isExpired;

  /// Whole days left until [validUntil] (negative once expired).
  int? get daysLeft {
    final v = validUntil;
    if (v == null) return null;
    final now = DateTime.now();
    final end = DateTime(v.year, v.month, v.day, 23, 59, 59);
    return end.difference(now).inDays;
  }

  List<Attachment> get photos =>
      attachments.where((a) => a.isDamagePhoto || a.isImage).toList();

  /// "Accepted via link by Thabo" / "Declined in app".
  String? get decisionLabel {
    if (!isDecided) return null;
    final verb = status == QuotationStatus.declined ? 'Declined' : 'Accepted';
    final source = decisionSource?.label ?? 'in app';
    final by = decisionSource == QuoteDecisionSource.publicLink &&
            decisionByName != null
        ? ' by $decisionByName'
        : '';
    return '$verb $source$by';
  }

  factory Quotation.fromJson(Json json) {
    final vehicle = asJsonOrNull(json['vehicle']);
    final outlet = asJsonOrNull(json['outlet']);
    return Quotation(
      id: str(json['id']),
      ref: str(json['ref']),
      customerId: str(json['customer_id']),
      vehicleId: str(json['vehicle_id'], str(vehicle?['id'])),
      outletId: str(json['outlet_id'], str(outlet?['id'])),
      category: str(json['category']),
      description: str(json['description']),
      status: QuotationStatus.fromDb(strOrNull(json['status'])),
      amountCents: intOrNull(json['amount_cents']),
      lineItems: asJsonList(
        json['items'] ?? json['line_items'],
      ).map(LineItem.fromJson).toList(),
      assessorId: strOrNull(json['assessor_id']),
      assessorName: strOrNull(json['assessor_name']),
      validUntil: dtOrNull(json['valid_until']),
      quotedAt: dtOrNull(json['quoted_at']),
      decidedAt: dtOrNull(json['decided_at']),
      decisionBy: strOrNull(json['decision_by']),
      decisionNote: strOrNull(json['decision_note']),
      clientOpId: strOrNull(json['client_op_id']),
      createdAt: dtOrNull(json['created_at']),
      updatedAt: dtOrNull(json['updated_at']),
      attachments: asJsonList(json['attachments'])
          .map(Attachment.fromJson)
          .toList(),
      vehicleLabel:
          strOrNull(json['vehicle_label']) ??
          (vehicle == null
              ? null
              : [
                  vehicle['model'],
                  vehicle['registration_no'],
                ].whereType<String>().join(' · ')),
      outletName: strOrNull(json['outlet_name']) ?? strOrNull(outlet?['name']),
      itemsNote: strOrNull(json['items_note']),
      terms: strOrNull(json['terms']),
      decisionSource: QuoteDecisionSource.fromDb(
        strOrNull(json['decision_source']),
      ),
      decisionByName: strOrNull(json['decision_by_name']),
      publicUrl: strOrNull(json['public_url']),
      pdfUrl: strOrNull(json['pdf_url']),
      customerName:
          strOrNull(json['customer_name']) ??
          strOrNull(asJsonOrNull(json['customer'])?['full_name']),
      pendingSync: boolOf(json['pending_sync']),
      workOrder: json['work_order'] is Map
          ? QuotationWorkOrder.fromJson(asJson(json['work_order']))
          : null,
      workOrderRef:
          strOrNull(json['work_order_ref']) ??
          strOrNull(asJsonOrNull(json['work_order'])?['ref']),
      payment: json['payment'] is Map
          ? PaymentSummary.fromJson(asJson(json['payment']))
          : null,
      amountDueCents: intOrNull(json['amount_due_cents']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'customer_id': customerId,
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'category': category,
    'description': description,
    'status': status.db,
    'amount_cents': amountCents,
    'line_items': lineItems.map((l) => l.toJson()).toList(),
    'assessor_id': assessorId,
    'assessor_name': assessorName,
    'valid_until': isoDate(validUntil),
    'quoted_at': iso(quotedAt),
    'decided_at': iso(decidedAt),
    'decision_by': decisionBy,
    'decision_note': decisionNote,
    'client_op_id': clientOpId,
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'attachments': attachments.isEmpty
        ? null
        : attachments.map((a) => a.toJson()).toList(),
    'vehicle_label': vehicleLabel,
    'outlet_name': outletName,
    'items_note': itemsNote,
    'terms': terms,
    'decision_source': decisionSource?.db,
    'decision_by_name': decisionByName,
    'public_url': publicUrl,
    'pdf_url': pdfUrl,
    'customer_name': customerName,
    'pending_sync': pendingSync ? true : null,
    'work_order': workOrder?.toJson(),
    'work_order_ref': workOrderRef ?? workOrder?.ref,
    'payment': payment?.toJson(),
    'amount_due_cents': _amountDueCents,
  });

  Quotation copyWith({
    QuotationStatus? status,
    int? amountCents,
    List<LineItem>? lineItems,
    String? assessorId,
    String? assessorName,
    DateTime? validUntil,
    DateTime? quotedAt,
    DateTime? decidedAt,
    String? decisionBy,
    String? decisionNote,
    DateTime? updatedAt,
    List<Attachment>? attachments,
    String? itemsNote,
    String? terms,
    QuoteDecisionSource? decisionSource,
    String? decisionByName,
    String? publicUrl,
    bool clearPublicUrl = false,
    String? pdfUrl,
    String? customerName,
    bool? pendingSync,
    QuotationWorkOrder? workOrder,
    String? workOrderRef,
    PaymentSummary? payment,
    int? amountDueCents,
  }) => Quotation(
    id: id,
    ref: ref,
    customerId: customerId,
    vehicleId: vehicleId,
    outletId: outletId,
    category: category,
    description: description,
    status: status ?? this.status,
    amountCents: amountCents ?? this.amountCents,
    lineItems: lineItems ?? this.lineItems,
    assessorId: assessorId ?? this.assessorId,
    assessorName: assessorName ?? this.assessorName,
    validUntil: validUntil ?? this.validUntil,
    quotedAt: quotedAt ?? this.quotedAt,
    decidedAt: decidedAt ?? this.decidedAt,
    decisionBy: decisionBy ?? this.decisionBy,
    decisionNote: decisionNote ?? this.decisionNote,
    clientOpId: clientOpId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    attachments: attachments ?? this.attachments,
    vehicleLabel: vehicleLabel,
    outletName: outletName,
    itemsNote: itemsNote ?? this.itemsNote,
    terms: terms ?? this.terms,
    decisionSource: decisionSource ?? this.decisionSource,
    decisionByName: decisionByName ?? this.decisionByName,
    publicUrl: clearPublicUrl ? null : (publicUrl ?? this.publicUrl),
    pdfUrl: pdfUrl ?? this.pdfUrl,
    customerName: customerName ?? this.customerName,
    pendingSync: pendingSync ?? this.pendingSync,
    workOrder: workOrder ?? this.workOrder,
    workOrderRef: workOrderRef ?? this.workOrderRef ?? workOrder?.ref,
    payment: payment ?? this.payment,
    amountDueCents: amountDueCents ?? _amountDueCents,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    status,
    amountCents,
    lineItems,
    validUntil,
    decidedAt,
    attachments,
    updatedAt,
    decisionSource,
    publicUrl,
    pendingSync,
    workOrder,
    payment,
    _amountDueCents,
  ];
}

/// Body for `POST /quotations`.
class QuotationInput {
  const QuotationInput({
    required this.vehicleId,
    required this.outletId,
    required this.category,
    required this.description,
    required this.clientOpId,
    this.attachmentIds = const [],
  });

  final String vehicleId;
  final String outletId;
  final String category;
  final String description;
  final String clientOpId;
  final List<String> attachmentIds;

  Json toJson() => compact({
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'category': category,
    'description': description,
    'client_op_id': clientOpId,
    'attachment_ids': attachmentIds.isEmpty ? null : attachmentIds,
  });

  factory QuotationInput.fromJson(Json json) => QuotationInput(
    vehicleId: str(json['vehicle_id']),
    outletId: str(json['outlet_id']),
    category: str(json['category']),
    description: str(json['description']),
    clientOpId: str(json['client_op_id']),
    attachmentIds: asStringList(json['attachment_ids']),
  );
}

/// Body for `POST /quotations/:id/quote` (supervisor/manager).
class QuoteInput {
  const QuoteInput({
    required this.amountCents,
    required this.lineItems,
    required this.validUntil,
  });
  final int amountCents;
  final List<LineItem> lineItems;
  final DateTime validUntil;
  Json toJson() => {
    'amount_cents': amountCents,
    'line_items': lineItems.map((l) => l.toJson()).toList(),
    'valid_until': isoDate(validUntil),
  };
}

/// One attention item of a staff-raised quote (`items[]` of `POST /quotations`).
class QuoteItemInput extends Equatable {
  const QuoteItemInput({
    required this.label,
    required this.amountCents,
    this.description,
    this.category,
    this.serviceId,
  });

  final String label;
  final int amountCents;
  final String? description;
  final String? category;
  final String? serviceId;

  Json toJson() => compact({
    'label': label.trim(),
    'description': (description?.trim().isEmpty ?? true)
        ? null
        : description!.trim(),
    'category': category,
    'service_id': serviceId,
    'amount_cents': amountCents,
  });

  factory QuoteItemInput.fromJson(Json json) => QuoteItemInput(
    label: str(json['label']),
    amountCents: intOf(json['amount_cents']),
    description: strOrNull(json['description']),
    category: strOrNull(json['category']),
    serviceId: strOrNull(json['service_id']),
  );

  LineItem toLineItem() => LineItem(
    label: label,
    amountCents: amountCents,
    description: description,
    category: category,
    serviceId: serviceId,
  );

  @override
  List<Object?> get props => [label, amountCents, description, category, serviceId];
}

/// Body for the staff `POST /quotations` (STF-010/012 — raise a quote for a
/// walk-in customer in one step; status starts `quoted`).
class StaffQuotationInput {
  const StaffQuotationInput({
    required this.customerId,
    required this.vehicleId,
    required this.outletId,
    required this.category,
    required this.description,
    required this.items,
    required this.validUntil,
    required this.clientOpId,
    this.itemsNote,
    this.sendToCustomer = true,
  });

  final String customerId;
  final String vehicleId;
  final String outletId;

  /// Primary category (first item's, or "Dent, Scratch" when mixed).
  final String category;
  final String description;
  final List<QuoteItemInput> items;
  final DateTime validUntil;
  final String? itemsNote;
  final bool sendToCustomer;
  final String clientOpId;

  int get totalCents => items.fold(0, (sum, i) => sum + i.amountCents);

  Json toJson() => compact({
    'customer_id': customerId,
    'vehicle_id': vehicleId,
    'outlet_id': outletId,
    'category': category,
    'description': description.trim(),
    'items': items.map((i) => i.toJson()).toList(),
    'valid_until': isoDate(validUntil),
    'items_note': (itemsNote?.trim().isEmpty ?? true) ? null : itemsNote!.trim(),
    'client_op_id': clientOpId,
    'send_to_customer': sendToCustomer,
  });

  factory StaffQuotationInput.fromJson(Json json) => StaffQuotationInput(
    customerId: str(json['customer_id']),
    vehicleId: str(json['vehicle_id']),
    outletId: str(json['outlet_id']),
    category: str(json['category']),
    description: str(json['description']),
    items: asJsonList(json['items']).map(QuoteItemInput.fromJson).toList(),
    validUntil: dtOrNull(json['valid_until']) ?? DateTime.now(),
    itemsNote: strOrNull(json['items_note']),
    sendToCustomer: boolOf(json['send_to_customer'], true),
    clientOpId: str(json['client_op_id']),
  );
}

/// Response of `POST /quotations/:id/share`.
class SharedQuoteLink extends Equatable {
  const SharedQuoteLink({required this.publicUrl, this.expiresAt});
  final String publicUrl;
  final DateTime? expiresAt;

  factory SharedQuoteLink.fromJson(Json json) => SharedQuoteLink(
    publicUrl: str(json['public_url']),
    expiresAt: dtOrNull(json['expires_at']),
  );
  Json toJson() =>
      compact({'public_url': publicUrl, 'expires_at': iso(expiresAt)});

  @override
  List<Object?> get props => [publicUrl, expiresAt];
}
