import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `quotations.line_items[]` entry.
class LineItem extends Equatable {
  const LineItem({
    required this.label,
    required this.amountCents,
    this.quantity = 1,
  });
  final String label;
  final int amountCents;
  final int quantity;

  factory LineItem.fromJson(Json json) => LineItem(
    label: str(json['label']),
    amountCents: intOf(json['amount_cents']),
    quantity: intOf(json['quantity'], 1),
  );
  Json toJson() => {
    'label': label,
    'amount_cents': amountCents,
    if (quantity != 1) 'quantity': quantity,
  };
  @override
  List<Object?> get props => [label, amountCents, quantity];
}

/// `attachments` row (file lives in Cloud Storage for Firebase).
class Attachment extends Equatable {
  const Attachment({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.storagePath,
    required this.mimeType,
    this.sizeBytes = 0,
    this.sha256,
    this.uploadedBy,
    this.createdAt,
    this.downloadUrl,
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

  /// Signed/download URL when the API includes one.
  final String? downloadUrl;

  bool get isImage => mimeType.startsWith('image/');

  factory Attachment.fromJson(Json json) => Attachment(
    id: str(json['id']),
    entityType: str(json['entity_type']),
    entityId: str(json['entity_id']),
    storagePath: str(json['storage_path']),
    mimeType: str(json['mime_type'], 'application/octet-stream'),
    sizeBytes: intOf(json['size_bytes']),
    sha256: strOrNull(json['sha256']),
    uploadedBy: strOrNull(json['uploaded_by']),
    createdAt: dtOrNull(json['created_at']),
    downloadUrl: strOrNull(json['download_url']) ?? strOrNull(json['url']),
  );

  Json toJson() => compact({
    'id': id,
    'entity_type': entityType,
    'entity_id': entityId,
    'storage_path': storagePath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'uploaded_by': uploadedBy,
    'created_at': iso(createdAt),
    'download_url': downloadUrl,
  });

  @override
  List<Object?> get props => [
    id,
    entityType,
    entityId,
    storagePath,
    mimeType,
    sizeBytes,
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
  ];
}

/// `quotations` row (+ `attachments[]` on `GET /quotations/:id`).
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
  });

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

  bool get isExpired =>
      validUntil != null &&
      validUntil!.isBefore(DateTime.now()) &&
      status == QuotationStatus.quoted;

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
      lineItems: asJsonList(json['line_items']).map(LineItem.fromJson).toList(),
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
