import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// State for the 3-step booking flow (service → slot → pay).
///
/// The draft is persisted in [DraftStore] after every change (UX-009) so a
/// killed or offline app resumes where the customer left off. The
/// `client_op_id` is generated once per draft and reused on retry, which makes
/// `POST /bookings` idempotent (ARC-004).
class BookingFlowController extends ChangeNotifier {
  BookingFlowController(this.repositories) {
    _restore();
  }

  static const String draftKey = 'booking_draft';

  final Repositories repositories;

  Outlet? outlet;
  OutletService? service;
  Vehicle? vehicle;
  DateTime? slotStart;
  String? methodId;
  String clientOpId = SparklingApi.newOpId();
  DateTime? restoredAt;

  bool get hasDraft => outlet != null && service != null;
  bool get canPickSlot => outlet != null && service != null && vehicle != null;
  bool get canPay => canPickSlot && slotStart != null;

  DateTime? get slotEnd => slotStart == null || service == null
      ? null
      : slotStart!.add(Duration(minutes: service!.durationMinutes));

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
    slotStart = null;
    _persist();
  }

  void setService(OutletService s) {
    service = s;
    slotStart = null;
    _persist();
  }

  void setVehicle(Vehicle v) {
    vehicle = v;
    _persist();
  }

  void setSlot(DateTime? start) {
    slotStart = start;
    _persist();
  }

  void setMethod(String? id) {
    methodId = id;
    _persist();
  }

  BookingInput toInput() => BookingInput(
    vehicleId: vehicle!.id,
    outletId: outlet!.id,
    serviceId: service!.id,
    slotStart: slotStart!,
    clientOpId: clientOpId,
  );

  /// Clears the draft after a successful booking (or on explicit discard).
  void reset() {
    outlet = null;
    service = null;
    vehicle = null;
    slotStart = null;
    methodId = null;
    restoredAt = null;
    clientOpId = SparklingApi.newOpId();
    repositories.drafts.delete(draftKey);
    notifyListeners();
  }
}
