import 'dart:typed_data';

import 'package:sparkling_core/sparkling_core.dart';

import '../walk_in/walk_in_flow.dart';

/// Steps of the raise-quote flow (customer → vehicle → items → review).
enum RaiseQuoteStep { customer, vehicle, items, review }

/// Arguments for the raise-quote screen (`/quote/new`, passed as `extra`).
class RaiseQuoteArgs {
  const RaiseQuoteArgs({
    this.scanned,
    this.customer,
    this.vehicle,
    this.service,
  });

  /// Disc scanned on the review screen for a plate without a booking.
  final DiscScanResult? scanned;

  /// Prefilled from the walk-in confirmation ("Raise a quote for this vehicle").
  final CustomerSummary? customer;
  final CustomerVehicleSummary? vehicle;

  /// By-quote catalogue offer tapped on the walk-in service step ("Raise
  /// quote instead") — seeds the description.
  final OutletService? service;
}

/// One attention item (dent, scratch …) in the draft.
class QuoteItemDraft {
  const QuoteItemDraft({
    required this.id,
    required this.label,
    required this.category,
    required this.amountCents,
    this.description,
    this.serviceId,
    this.serviceName,
  });

  final String id;
  final String label;
  final String category;
  final int amountCents;
  final String? description;
  final String? serviceId;
  final String? serviceName;

  QuoteItemInput toInput() => QuoteItemInput(
    label: label,
    amountCents: amountCents,
    description: description,
    category: category,
    serviceId: serviceId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'category': category,
    'amount_cents': amountCents,
    'description': description,
    'service_id': serviceId,
    'service_name': serviceName,
  };

  factory QuoteItemDraft.fromJson(Map<String, dynamic> m) => QuoteItemDraft(
    id: m['id']?.toString() ?? SparklingApi.newOpId(),
    label: m['label']?.toString() ?? '',
    category: m['category']?.toString() ?? 'Other',
    amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
    description: m['description']?.toString(),
    serviceId: m['service_id']?.toString(),
    serviceName: m['service_name']?.toString(),
  );
}

/// A damage photo waiting to be uploaded: a file [path] (camera / gallery)
/// or in-memory [bytes] (tests, pasted images). Only paths survive a restart.
class QuotePhotoDraft {
  const QuotePhotoDraft({
    required this.id,
    this.path,
    this.bytes,
    this.caption,
    this.name,
    this.mimeType,
  });

  final String id;
  final String? path;
  final Uint8List? bytes;
  final String? caption;
  final String? name;
  final String? mimeType;

  String get fileName => name ?? path?.split('/').last ?? 'photo.jpg';

  QuotePhotoDraft copyWith({String? caption, bool clearCaption = false}) =>
      QuotePhotoDraft(
        id: id,
        path: path,
        bytes: bytes,
        caption: clearCaption ? null : (caption ?? this.caption),
        name: name,
        mimeType: mimeType,
      );

  Map<String, dynamic>? toJson() => path == null
      ? null
      : {'id': id, 'path': path, 'caption': caption, 'name': name};

  factory QuotePhotoDraft.fromJson(Map<String, dynamic> m) => QuotePhotoDraft(
    id: m['id']?.toString() ?? SparklingApi.newOpId(),
    path: m['path']?.toString(),
    caption: m['caption']?.toString(),
    name: m['name']?.toString(),
  );
}

/// Result handed to the confirmation screen.
class RaiseQuoteOutcome {
  const RaiseQuoteOutcome({
    required this.quotation,
    this.customer,
    this.uploaded = 0,
    this.failedUploads = 0,
    this.deferredPhotos = 0,
    this.sentToCustomer = true,
  });

  final Quotation quotation;
  final CustomerSummary? customer;
  final int uploaded;
  final int failedUploads;

  /// Photos kept on the device until the queued op syncs.
  final int deferredPhotos;
  final bool sentToCustomer;

  bool get queued => quotation.pendingSync;
}

/// State for the 4-step raise-quote flow (STF-010/012, CUS-030..034).
///
/// The draft lives in [DraftStore] under [draftKey] with a stable
/// `client_op_id` so a retried `POST /quotations` is idempotent and a killed
/// app resumes where the technician left off.
class RaiseQuoteController extends CustomerVehicleFlow {
  RaiseQuoteController(this.repositories, {RaiseQuoteArgs? args}) {
    _restore();
    final a = args;
    if (a != null) {
      if (a.customer != null) {
        if (customer?.id != a.customer!.id) vehicle = null;
        customer = a.customer;
      }
      if (a.vehicle != null) vehicle = a.vehicle;
      if (a.scanned != null) {
        scannedVehicle = a.scanned;
        vehicle = null;
      }
      if (a.service != null && description.trim().isEmpty) {
        description = 'Quote for ${a.service!.name}. ';
      }
      if (a.customer != null ||
          a.vehicle != null ||
          a.scanned != null ||
          a.service != null) {
        _persist();
      }
    }
  }

  static const String draftKey = 'raise_quote_draft';
  static const int maxPhotos = 10;
  static const int defaultValidityDays = 14;

  final Repositories repositories;

  @override
  CustomerSummary? customer;
  @override
  CustomerVehicleSummary? vehicle;
  @override
  DiscScanResult? scannedVehicle;
  @override
  DateTime? restoredAt;

  List<QuoteItemDraft> items = [];
  String description = '';
  String itemsNote = '';
  List<QuotePhotoDraft> photos = [];
  DateTime validUntil = _plusDays(defaultValidityDays);
  bool sendToCustomer = true;
  String clientOpId = SparklingApi.newOpId();

  static DateTime _plusDays(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + days);
  }

  bool get hasDraft => customer != null || items.isNotEmpty;
  bool get canPickVehicle => customer != null;
  bool get canAddItems => customer != null && vehicle != null;
  bool get canReview =>
      canAddItems && items.isNotEmpty && description.trim().length >= 10;

  int get totalCents => items.fold(0, (sum, i) => sum + i.amountCents);

  /// "Dent, Scratch" — unique categories in order of appearance.
  String get category {
    final seen = <String>[];
    for (final i in items) {
      if (!seen.contains(i.category)) seen.add(i.category);
    }
    return seen.isEmpty ? 'Other' : seen.join(', ');
  }

  RaiseQuoteStep get maxStep => !canPickVehicle
      ? RaiseQuoteStep.customer
      : !canAddItems
      ? RaiseQuoteStep.vehicle
      : !canReview
      ? RaiseQuoteStep.items
      : RaiseQuoteStep.review;

  void _restore() {
    final json = repositories.drafts.load(draftKey);
    if (json == null) return;
    try {
      final map = CustomerVehicleFlow.mapOf;
      if (json['customer'] is Map) {
        customer = CustomerSummary.fromJson(map(json['customer']));
      }
      if (json['vehicle'] is Map) {
        vehicle = CustomerVehicleSummary.fromJson(map(json['vehicle']));
      }
      if (json['scanned_vehicle'] is Map) {
        scannedVehicle = CustomerVehicleFlow.discFromJson(
          map(json['scanned_vehicle']),
        );
      }
      items = (json['items'] as List? ?? const [])
          .map((e) => QuoteItemDraft.fromJson(map(e)))
          .toList();
      description = json['description']?.toString() ?? '';
      itemsNote = json['items_note']?.toString() ?? '';
      photos = (json['photos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => QuotePhotoDraft.fromJson(map(e)))
          .toList();
      final vu = json['valid_until'];
      validUntil = vu == null
          ? _plusDays(defaultValidityDays)
          : (DateTime.tryParse('$vu') ?? _plusDays(defaultValidityDays));
      sendToCustomer = json['send_to_customer'] is bool
          ? json['send_to_customer'] as bool
          : true;
      clientOpId = json['client_op_id']?.toString() ?? clientOpId;
      restoredAt = repositories.drafts.savedAt(draftKey);
    } catch (_) {
      reset();
    }
  }

  Future<void> _persist() async {
    notifyListeners();
    await repositories.drafts.save(draftKey, {
      'customer': customer?.toJson(),
      'vehicle': vehicle?.toJson(),
      'scanned_vehicle': scannedVehicle?.toJson(),
      'items': items.map((i) => i.toJson()).toList(),
      'description': description,
      'items_note': itemsNote,
      'photos': photos.map((p) => p.toJson()).whereType<Map>().toList(),
      'valid_until': validUntil.toIso8601String(),
      'send_to_customer': sendToCustomer,
      'client_op_id': clientOpId,
    });
  }

  @override
  void setCustomer(CustomerSummary c) {
    if (customer?.id != c.id) vehicle = null;
    customer = c;
    _persist();
  }

  @override
  void refreshCustomer(CustomerSummary c) {
    customer = c;
    _persist();
  }

  @override
  void clearCustomer() {
    customer = null;
    vehicle = null;
    _persist();
  }

  @override
  void setVehicle(CustomerVehicleSummary v) {
    vehicle = v;
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

  // ---- Items -----------------------------------------------------------------

  void addItem(QuoteItemDraft item) {
    items = [...items, item];
    _persist();
  }

  void updateItem(QuoteItemDraft item) {
    items = [
      for (final i in items)
        if (i.id == item.id) item else i,
    ];
    _persist();
  }

  void removeItem(String id) {
    items = items.where((i) => i.id != id).toList();
    _persist();
  }

  void setDescription(String v) {
    if (description == v) return;
    description = v;
    _persist();
  }

  void setItemsNote(String v) {
    if (itemsNote == v) return;
    itemsNote = v;
    _persist();
  }

  // ---- Photos ----------------------------------------------------------------

  bool get canAddPhoto => photos.length < maxPhotos;

  void addPhoto(QuotePhotoDraft photo) {
    if (!canAddPhoto) return;
    photos = [...photos, photo];
    _persist();
  }

  void setPhotoCaption(String id, String? caption) {
    photos = [
      for (final p in photos)
        if (p.id == id)
          p.copyWith(
            caption: caption?.trim(),
            clearCaption: caption == null || caption.trim().isEmpty,
          )
        else
          p,
    ];
    _persist();
  }

  void removePhoto(String id) {
    photos = photos.where((p) => p.id != id).toList();
    _persist();
  }

  // ---- Validity & sending ------------------------------------------------------

  void setValidUntil(DateTime d) {
    validUntil = DateTime(d.year, d.month, d.day);
    _persist();
  }

  void setValidForDays(int days) => setValidUntil(_plusDays(days));

  /// Whole days from today to [validUntil] (null when it is not one of the
  /// quick picks).
  int get validityDays {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return validUntil.difference(today).inDays;
  }

  void setSendToCustomer(bool v) {
    sendToCustomer = v;
    _persist();
  }

  StaffQuotationInput toInput({required String outletId}) =>
      StaffQuotationInput(
        customerId: customer!.id,
        vehicleId: vehicle!.id,
        outletId: outletId,
        category: category,
        description: description.trim(),
        items: items.map((i) => i.toInput()).toList(),
        validUntil: validUntil,
        itemsNote: itemsNote.trim().isEmpty ? null : itemsNote.trim(),
        clientOpId: clientOpId,
        sendToCustomer: sendToCustomer,
      );

  /// Photos with a file path can be uploaded later by the sync queue.
  List<DeferredPhoto> get deferredPhotos => [
    for (final p in photos)
      if (p.path != null) DeferredPhoto(path: p.path!, caption: p.caption),
  ];

  /// A rejected submit needs a fresh op id; the draft stays for edits.
  void rotateOpId() {
    clientOpId = SparklingApi.newOpId();
    _persist();
  }

  @override
  void reset() {
    customer = null;
    vehicle = null;
    scannedVehicle = null;
    items = [];
    description = '';
    itemsNote = '';
    photos = [];
    validUntil = _plusDays(defaultValidityDays);
    sendToCustomer = true;
    restoredAt = null;
    clientOpId = SparklingApi.newOpId();
    repositories.drafts.delete(draftKey);
    notifyListeners();
  }
}
