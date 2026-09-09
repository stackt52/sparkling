import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/json.dart';

/// Kind of row change.
enum RealtimeEvent { insert, update, delete }

/// One `postgres_changes` event.
class RealtimeChange {
  const RealtimeChange({
    required this.table,
    required this.event,
    required this.newRecord,
    required this.oldRecord,
    required this.commitTimestamp,
  });

  final String table;
  final RealtimeEvent event;
  final Json newRecord;
  final Json oldRecord;
  final DateTime commitTimestamp;

  /// The row after the change (or the deleted row for deletes).
  Json get record => event == RealtimeEvent.delete ? oldRecord : newRecord;
  String? get id => record['id']?.toString();

  factory RealtimeChange.fromPayload(PostgresChangePayload p) => RealtimeChange(
    table: p.table,
    event: switch (p.eventType) {
      PostgresChangeEvent.insert => RealtimeEvent.insert,
      PostgresChangeEvent.update => RealtimeEvent.update,
      PostgresChangeEvent.delete => RealtimeEvent.delete,
      PostgresChangeEvent.all => RealtimeEvent.update,
    },
    newRecord: Map<String, dynamic>.from(p.newRecord),
    oldRecord: Map<String, dynamic>.from(p.oldRecord),
    commitTimestamp: p.commitTimestamp,
  );
}

/// Supabase Realtime (`postgres_changes`) consumed with the Firebase ID token
/// via Third-Party Auth (ARC-003, API-007/008). RLS applies to subscriptions.
///
/// ```dart
/// final rt = RealtimeService(supabaseUrl: Env.supabaseUrl, anonKey: Env.supabaseAnonKey, accessToken: auth.idToken);
/// rt.customerBookings(uid).listen((c) => refresh());
/// ```
class RealtimeService {
  RealtimeService({
    required String supabaseUrl,
    required String anonKey,
    required Future<String?> Function() accessToken,
    SupabaseClient? client,
  }) : client =
           client ??
           SupabaseClient(
             supabaseUrl,
             anonKey,
             accessToken: accessToken,
             realtimeClientOptions: const RealtimeClientOptions(
               eventsPerSecond: 20,
             ),
           );

  final SupabaseClient client;
  int _seq = 0;

  /// Stream of changes on [table] (schema `public`), optionally filtered by
  /// `filterColumn = value`. The channel is created on first listen and
  /// removed on cancel.
  Stream<RealtimeChange> watchTable(
    String table, {
    String? filterColumn,
    Object? value,
    PostgresChangeFilterType filterType = PostgresChangeFilterType.eq,
    RealtimeEvent? event,
  }) {
    late StreamController<RealtimeChange> controller;
    RealtimeChannel? channel;

    controller = StreamController<RealtimeChange>.broadcast(
      onListen: () {
        final name =
            'sparkling:$table:${filterColumn ?? '*'}:${value ?? '*'}:${_seq++}';
        channel = client
            .channel(name)
            .onPostgresChanges(
              event: switch (event) {
                RealtimeEvent.insert => PostgresChangeEvent.insert,
                RealtimeEvent.update => PostgresChangeEvent.update,
                RealtimeEvent.delete => PostgresChangeEvent.delete,
                null => PostgresChangeEvent.all,
              },
              schema: 'public',
              table: table,
              filter: filterColumn == null
                  ? null
                  : PostgresChangeFilter(
                      type: filterType,
                      column: filterColumn,
                      value: value,
                    ),
              callback: (payload) {
                if (!controller.isClosed) {
                  controller.add(RealtimeChange.fromPayload(payload));
                }
              },
            );
        channel!.subscribe((status, error) {
          if (error != null && !controller.isClosed) controller.addError(error);
        });
      },
      onCancel: () async {
        final c = channel;
        channel = null;
        if (c != null) await client.removeChannel(c);
      },
    );
    return controller.stream;
  }

  // ---- Customer channels (API.md "Realtime channels") ----------------------

  Stream<RealtimeChange> customerBookings(String uid) =>
      watchTable('bookings', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> customerWorkOrders(String uid) =>
      watchTable('work_orders', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> customerQuotations(String uid) =>
      watchTable('quotations', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> customerPayments(String uid) =>
      watchTable('payments', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> loyaltyLedger(String uid) =>
      watchTable('loyalty_ledger', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> loyaltyAccount(String uid) =>
      watchTable('loyalty_accounts', filterColumn: 'customer_id', value: uid);
  Stream<RealtimeChange> notifications(String uid) =>
      watchTable('notifications', filterColumn: 'recipient_id', value: uid);

  /// Step results for one work order (customer timeline / staff checklist).
  Stream<RealtimeChange> stepResults(String workOrderId) => watchTable(
    'checklist_step_results',
    filterColumn: 'work_order_id',
    value: workOrderId,
  );

  /// A single work order row.
  Stream<RealtimeChange> workOrder(String workOrderId) =>
      watchTable('work_orders', filterColumn: 'id', value: workOrderId);

  /// A single booking row.
  Stream<RealtimeChange> booking(String bookingId) =>
      watchTable('bookings', filterColumn: 'id', value: bookingId);

  // ---- Staff channels (filtered by outlet_id) --------------------------------

  Stream<RealtimeChange> outletTasks(String outletId) =>
      watchTable('tasks', filterColumn: 'outlet_id', value: outletId);
  Stream<RealtimeChange> outletWorkOrders(String outletId) =>
      watchTable('work_orders', filterColumn: 'outlet_id', value: outletId);
  Stream<RealtimeChange> outletBookings(String outletId) =>
      watchTable('bookings', filterColumn: 'outlet_id', value: outletId);
  Stream<RealtimeChange> outletInventoryItems(String outletId) =>
      watchTable('inventory_items', filterColumn: 'outlet_id', value: outletId);
  Stream<RealtimeChange> outletInventoryAlerts(String outletId) => watchTable(
    'inventory_alerts',
    filterColumn: 'outlet_id',
    value: outletId,
  );
  Stream<RealtimeChange> outletStaffPoints(String outletId) => watchTable(
    'staff_points_ledger',
    filterColumn: 'outlet_id',
    value: outletId,
  );

  /// `staff_availability` has no outlet column; RLS limits rows to staff.
  Stream<RealtimeChange> staffAvailability() =>
      watchTable('staff_availability');

  /// All step results visible to the caller (RLS-scoped) — staff checklist
  /// lists across an outlet.
  Stream<RealtimeChange> allStepResults() =>
      watchTable('checklist_step_results');

  // ---- Admin channels --------------------------------------------------------

  Stream<RealtimeChange> outletPayments(String outletId) =>
      watchTable('payments', filterColumn: 'outlet_id', value: outletId);

  /// Merged "anything changed for this outlet" stream for dashboards.
  Stream<RealtimeChange> outletActivity(String outletId) => _merge([
    outletBookings(outletId),
    outletWorkOrders(outletId),
    outletTasks(outletId),
    outletInventoryAlerts(outletId),
  ]);

  static Stream<RealtimeChange> _merge(List<Stream<RealtimeChange>> streams) {
    late StreamController<RealtimeChange> controller;
    final subs = <StreamSubscription<RealtimeChange>>[];
    controller = StreamController<RealtimeChange>.broadcast(
      onListen: () {
        for (final s in streams) {
          subs.add(s.listen(controller.add, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// Removes all channels (call on sign-out).
  Future<void> dispose() => client.removeAllChannels();
}
