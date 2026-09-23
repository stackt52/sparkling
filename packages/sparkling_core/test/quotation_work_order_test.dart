import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Records requests and replies with scripted responses.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  Future<ResponseBody> Function(RequestOptions o)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

/// Work orders for every confirmed job and counter payments for quotations:
/// a confirmed booking / accepted quotation has its work order at once
/// (awaiting check-in), the check-in reuses it (a quotation check-in marks
/// the quotation `converted`), and `POST /payments/record { quotation_id }`
/// settles an accepted quotation (`quotation.payment`, `amount_due_cents`).
void main() {
  group('models', () {
    test('Quotation parses work_order, payment and amount_due_cents', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'ref': 'QT-2026-0039',
        'customer_id': 'c1',
        'vehicle_id': 'v1',
        'outlet_id': 'o1',
        'category': 'Bumper',
        'description': 'Scuff',
        'status': 'accepted',
        'amount_cents': 285000,
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'status': 'queued',
          'checked_in_at': null,
        },
        'work_order_ref': 'WO-2026-4819',
        'payment': null,
        'amount_due_cents': 285000,
      });
      expect(q.workOrder?.id, 'wo1');
      expect(q.workOrder?.ref, 'WO-2026-4819');
      expect(q.workOrder?.status, WorkStatus.queued);
      expect(q.workOrder?.isCheckedIn, isFalse);
      expect(q.workOrder?.awaitingCheckIn, isTrue);
      expect(q.workOrderRef, 'WO-2026-4819');
      expect(q.payment, isNull);
      expect(q.isPaid, isFalse);
      expect(q.amountDueCents, 285000);
      expect(q.isPaymentDue, isTrue);
      expect(q.paymentLabel, 'R 2 850.00 due at the counter');
      expect(q.toJson()['work_order_ref'], 'WO-2026-4819');
      expect(q.toJson()['work_order'], isA<Map<String, dynamic>>());

      // Paid: the summary carries no `status`, `verified_at` reads as paid.
      final paid = Quotation.fromJson({
        ...q.toJson(),
        'status': 'converted',
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'status': 'assigned',
          'checked_in_at': '2026-09-22T08:15:00Z',
        },
        'payment': {
          'id': 'p1',
          'receipt_no': 'RCP-70007',
          'amount_cents': 285000,
          'method': 'cash',
          'verified_at': '2026-09-22T08:20:00Z',
        },
        'amount_due_cents': 0,
      });
      expect(paid.workOrder?.isCheckedIn, isTrue);
      expect(paid.workOrder?.awaitingCheckIn, isFalse);
      expect(paid.payment?.status, PaymentStatus.successful);
      expect(paid.payment?.isVerified, isTrue);
      expect(paid.payment?.method, 'cash');
      expect(paid.payment?.methodLabel, 'cash');
      expect(paid.payment?.verifiedAt, isNotNull);
      expect(paid.isPaid, isTrue);
      expect(paid.amountDueCents, 0);
      expect(paid.isPaymentDue, isFalse);
      expect(paid.paymentLabel, 'Paid · cash · RCP-70007');
      // Round trip keeps the nested shapes.
      final again = Quotation.fromJson(paid.toJson());
      expect(again.payment, paid.payment);
      expect(again.workOrder, paid.workOrder);
      expect(again.amountDueCents, 0);

      // Without `amount_due_cents` the due amount is derived.
      final derived = Quotation.fromJson({
        ...q.toJson()..remove('amount_due_cents'),
      });
      expect(derived.amountDueCents, 285000);
      expect(
        Quotation.fromJson({
          ...q.toJson()..remove('amount_due_cents'),
          'status': 'quoted',
        }).paymentLabel,
        isNull,
      );
    });

    test('RecordPaymentInput targets a booking or a quotation', () {
      final booking = RecordPaymentInput(
        bookingId: 'b1',
        method: PaymentMethodKind.cash,
        amountCents: 8100,
        idempotencyKey: 'k1',
      );
      expect(booking.isForQuotation, isFalse);
      expect(booking.targetId, 'b1');
      expect(booking.toJson(), {
        'booking_id': 'b1',
        'method': 'cash',
        'amount_cents': 8100,
        'idempotency_key': 'k1',
      });

      final quote = RecordPaymentInput(
        quotationId: 'q1',
        method: PaymentMethodKind.cardTerminal,
        amountCents: 285000,
        idempotencyKey: 'k2',
        reference: ' SLIP 9 ',
      );
      expect(quote.isForQuotation, isTrue);
      expect(quote.targetId, 'q1');
      expect(quote.toJson(), {
        'quotation_id': 'q1',
        'method': 'card_terminal',
        'reference': 'SLIP 9',
        'amount_cents': 285000,
        'idempotency_key': 'k2',
      });
      expect(quote.toJson().containsKey('booking_id'), isFalse);
      final parsed = RecordPaymentInput.fromJson(quote.toJson());
      expect(parsed.quotationId, 'q1');
      expect(parsed.bookingId, isNull);
      expect(parsed.toJson(), quote.toJson());

      // Exactly one target.
      expect(
        () => RecordPaymentInput(
          bookingId: 'b1',
          quotationId: 'q1',
          method: PaymentMethodKind.cash,
          amountCents: 1,
          idempotencyKey: 'k3',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RecordPaymentInput(
          method: PaymentMethodKind.cash,
          amountCents: 1,
          idempotencyKey: 'k4',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('booking work_order summary carries checked_in_at', () {
      Booking booking(Map<String, Object?> wo) => Booking.fromJson({
        'id': 'b1',
        'ref': 'SPK-2026-0094',
        'customer_id': 'c1',
        'status': 'confirmed',
        'slot_start': '2026-09-23T09:00:00Z',
        'slot_end': '2026-09-23T09:30:00Z',
        'work_order': wo,
      });
      final waiting = booking({
        'id': 'wo1',
        'ref': 'WO-2026-4817',
        'status': 'queued',
        'checked_in_at': null,
      });
      expect(waiting.workOrder?.isCheckedIn, isFalse);
      expect(waiting.workOrder?.awaitingCheckIn, isTrue);
      expect(waiting.isAwaitingCheckIn, isTrue);
      expect(waiting.toJson()['work_order'], isNot(contains('checked_in_at')));

      final checked = booking({
        'id': 'wo1',
        'ref': 'WO-2026-4817',
        'status': 'queued',
        'checked_in_at': '2026-09-23T09:02:00Z',
      });
      expect(checked.workOrder?.isCheckedIn, isTrue);
      expect(checked.workOrder?.awaitingCheckIn, isFalse);
      expect(checked.isAwaitingCheckIn, isFalse);
      expect(
        (checked.toJson()['work_order'] as Map)['checked_in_at'],
        '2026-09-23T09:02:00.000Z',
      );
      final summary = checked.workOrder!.copyWith(status: WorkStatus.assigned);
      expect(summary.checkedInAt, checked.workOrder!.checkedInAt);
    });

    test('timeline "Checked in" keys off checked_in_at', () {
      WorkOrder wo({DateTime? checkedInAt, DateTime? startedAt}) => WorkOrder(
        id: 'wo1',
        ref: 'WO-2026-4817',
        outletId: 'o1',
        vehicleId: 'v1',
        customerId: 'c1',
        serviceId: 's1',
        status: WorkStatus.queued,
        checkedInAt: checkedInAt,
        startedAt: startedAt,
      );
      const template = ChecklistTemplate(
        id: 't1',
        name: 'Express',
        category: ServiceCategory.carWash,
        version: 1,
        steps: [
          ChecklistStep(key: 'exterior', title: 'Exterior wash'),
          ChecklistStep(key: 'dry', title: 'Dry'),
        ],
      );
      final waiting = WorkOrderDetail(
        workOrder: wo(),
        template: template,
      ).toTimeline();
      expect(waiting.first.key, 'checked_in');
      expect(waiting.first.state, TimelineEntryState.pending);
      expect(waiting.first.note, 'Waiting for your car');
      // Nothing is current before the car is on site.
      expect(
        waiting.where((e) => e.state == TimelineEntryState.current),
        isEmpty,
      );

      final at = DateTime(2026, 9, 23, 9, 2);
      final checked = WorkOrderDetail(
        workOrder: wo(checkedInAt: at),
        template: template,
      ).toTimeline();
      expect(checked.first.state, TimelineEntryState.done);
      expect(checked.first.at, at);
      expect(checked[1].state, TimelineEntryState.current);

      // Rows without checked_in_at fall back to started_at.
      final legacy = WorkOrderDetail(
        workOrder: wo(startedAt: at),
        template: template,
      ).toTimeline();
      expect(legacy.first.state, TimelineEntryState.done);
      expect(legacy.first.at, at);
    });
  });

  group('API', () {
    late _FakeAdapter adapter;
    late SparklingApi api;

    setUp(() {
      adapter = _FakeAdapter();
      api = SparklingApi(
        baseUrl: 'https://api.test/v1/',
        tokenProvider: () async => 'tok',
        clientApp: 'staff',
        clientVersion: '1.0.0+1',
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('recordPayment posts quotation_id and parses the payment', () async {
      adapter.handler = (o) async => _json({
        'payment': {
          'id': 'p1',
          'quotation_id': 'q1',
          'customer_id': 'c1',
          'provider': 'pos',
          'method': 'cash',
          'amount_cents': 285000,
          'status': 'successful',
          'receipt_no': 'RCP-70007',
          'verified_at': '2026-09-22T08:20:00Z',
        },
      }, status: 201);
      final p = await api.recordPayment(
        RecordPaymentInput(
          quotationId: 'q1',
          method: PaymentMethodKind.cash,
          amountCents: 285000,
          idempotencyKey: 'op-9',
        ),
      );
      expect(p.quotationId, 'q1');
      expect(p.bookingId, isNull);
      expect(p.method, 'cash');
      expect(p.receiptNo, 'RCP-70007');
      expect(p.isVerified, isTrue);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/payments/record');
      expect(req.data, {
        'quotation_id': 'q1',
        'method': 'cash',
        'amount_cents': 285000,
        'idempotency_key': 'op-9',
      });
      expect(req.headers['Idempotency-Key'], 'op-9');
    });

    test('quotation detail exposes payment and amount_due_cents', () async {
      adapter.handler = (o) async => _json({
        'id': 'q1',
        'ref': 'QT-2026-0039',
        'customer_id': 'c1',
        'vehicle_id': 'v1',
        'outlet_id': 'o1',
        'category': 'Bumper',
        'description': 'Scuff',
        'status': 'accepted',
        'amount_cents': 285000,
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'status': 'queued',
          'checked_in_at': null,
        },
        'work_order_ref': 'WO-2026-4819',
        'payment': {
          'id': 'p1',
          'receipt_no': 'RCP-70007',
          'amount_cents': 285000,
          'method': 'cash',
          'verified_at': '2026-09-22T08:20:00Z',
        },
        'amount_due_cents': 0,
      });
      final q = await api.quotation('q1');
      expect(q.workOrder?.awaitingCheckIn, isTrue);
      expect(q.payment?.receiptNo, 'RCP-70007');
      expect(q.isPaid, isTrue);
      expect(q.amountDueCents, 0);
    });
  });

  group('demo store', () {
    late Directory dir;
    late Repositories repos;
    late DemoStore store;
    final today = DateTime.now();

    Future<void> boot({
      AuthUser persona = DemoPersonas.customer,
      bool autoAssignment = false,
    }) async {
      store = DemoStore(
        currentUser: persona,
        clock: () => DateTime(today.year, today.month, today.day, 10, 13),
      );
      store.featureFlags['auto_assignment'] = autoAssignment;
      repos = await SparklingCore.bootstrap(
        demo: true,
        hivePath: dir.path,
        demoStore: store,
        clientApp: persona.role.isStaff ? 'staff' : 'customer',
        demoUser: persona,
      );
    }

    Future<void> signIn(AuthUser persona) async {
      await repos.auth.signInWithEmail(persona.email!, 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sparkling_qwo_');
      HiveStore.reset();
    });

    tearDown(() async {
      await repos.dispose();
      store.dispose();
      await Hive.deleteFromDisk();
      await Hive.close();
      HiveStore.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    BookingInput input({PaymentChoice? method, int daysAhead = 3}) =>
        BookingInput(
          vehicleId: DemoStore.vehPolo,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExecWash,
          slotStart: DateTime(
            today.year,
            today.month,
            today.day,
            14,
          ).add(Duration(days: daysAhead)),
          clientOpId: SparklingApi.newOpId(),
          paymentMethod: method,
        );

    test(
      'seed: confirmed bookings are on the board awaiting check-in',
      () async {
        await boot();
        final next = await repos.customer.booking(DemoStore.bookingNext);
        expect(next.status, BookingStatus.confirmed);
        expect(next.workOrder?.id, DemoStore.woNext);
        expect(next.workOrder?.ref, 'WO-${today.year}-4817');
        expect(next.workOrder?.isCheckedIn, isFalse);
        expect(next.isAwaitingCheckIn, isTrue);
        expect(next.timeline.first.key, 'checked_in');
        expect(next.timeline.first.state, TimelineEntryState.pending);
        // Pending (unpaid card) bookings are not on the board yet.
        await signIn(DemoPersonas.supervisor);
        final pending = await repos.staff.outletBookings(
          outletId: DemoStore.outletGlenVillage,
          status: BookingStatus.pending,
        );
        expect(pending, isNotEmpty);
        expect(pending.every((b) => b.workOrder == null), isTrue);
      },
    );

    test(
      'cash booking → work order awaiting check-in; card after payment',
      () async {
        await boot();
        final cash = await repos.customer.createBooking(
          input(method: PaymentChoice.cash),
        );
        expect(cash.status, BookingStatus.confirmed);
        final wo = cash.workOrder;
        expect(wo, isNotNull);
        expect(wo!.status, WorkStatus.queued);
        expect(wo.isCheckedIn, isFalse);
        expect(wo.awaitingCheckIn, isTrue);
        expect(cash.isAwaitingCheckIn, isTrue);
        final row = store.workOrders.firstWhere((w) => w.id == wo.id);
        expect(row.bookingId, cash.id);
        expect(row.etaAt, cash.slotEnd);
        expect(store.tasks.where((t) => t.workOrderId == wo.id), hasLength(1));
        expect(store.tasks.last.status, WorkStatus.queued);
        expect(store.tasks.last.outletId, DemoStore.outletMenlyn);

        // Card: pending until the sandbox payment verifies.
        final card = await repos.customer.createBooking(
          input(method: PaymentChoice.card, daysAhead: 4),
        );
        expect(card.status, BookingStatus.pending);
        expect(card.workOrder, isNull);
        final intent = await repos.customer.createPaymentIntent(
          bookingId: card.id,
        );
        await repos.customer.confirmSandboxPayment(intent.payment.id);
        final paid = await repos.customer.booking(card.id);
        expect(paid.status, BookingStatus.confirmed);
        expect(paid.workOrder, isNotNull);
        expect(paid.workOrder!.isCheckedIn, isFalse);
        expect(
          store.workOrders.where((w) => w.bookingId == card.id),
          hasLength(1),
        );
      },
    );

    test('booking check-in reuses the work order (no duplicate)', () async {
      await boot();
      final cash = await repos.customer.createBooking(
        input(method: PaymentChoice.cash),
      );
      final woId = cash.workOrder!.id;
      await signIn(DemoPersonas.supervisor);
      final checked = await repos.staff.checkinBooking(
        cash.id,
        bay: 'Bay 4',
        priority: 1,
      );
      expect(checked.status, BookingStatus.inService);
      expect(checked.workOrder!.id, woId);
      expect(checked.workOrder!.isCheckedIn, isTrue);
      expect(checked.workOrder!.bay, 'Bay 4');
      expect(checked.isAwaitingCheckIn, isFalse);
      expect(checked.timeline.first.state, TimelineEntryState.done);
      expect(
        store.workOrders.where((w) => w.bookingId == cash.id),
        hasLength(1),
      );
      final detail = await repos.staff.workOrder(woId);
      expect(detail.workOrder.checkedInBy, DemoPersonas.supervisor.uid);
      expect(detail.workOrder.priority, 1);
      expect(detail.task?.priority, 1);
      expect(detail.events.map((e) => e.event), contains('checked_in'));
      // Idempotent on the work order itself.
      final again = await repos.staff.checkInWorkOrder(woId);
      expect(again.already, isTrue);
    });

    test(
      'walk-in: confirmed → awaiting check-in; check-in reuses it',
      () async {
        await boot(persona: DemoPersonas.technician);
        final thabo = (await repos.staff.searchCustomers('thabo')).single;
        final b = await repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: thabo.vehicles.last.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-walk-1',
            slotStart: DateTime(today.year, today.month, today.day, 15),
          ),
        );
        expect(b.status, BookingStatus.confirmed);
        expect(b.workOrder, isNotNull);
        expect(b.workOrder!.isCheckedIn, isFalse);
        final before = store.workOrders.length;
        final checked = await repos.staff.checkinBooking(b.id, bay: 'Bay 2');
        expect(checked.workOrder!.id, b.workOrder!.id);
        expect(checked.workOrder!.isCheckedIn, isTrue);
        expect(store.workOrders.length, before);

        // Walk-in with `checkin`: a single, checked-in work order.
        final direct = await repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: thabo.vehicles.first.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-walk-2',
            checkin: const WalkInCheckin(bay: 'Bay 1'),
          ),
        );
        expect(direct.status, BookingStatus.inService);
        expect(direct.workOrder!.isCheckedIn, isTrue);
        expect(direct.workOrder!.bay, 'Bay 1');
        expect(
          store.workOrders.where((w) => w.bookingId == direct.id),
          hasLength(1),
        );
      },
    );

    test('accepting a quotation creates its work order at once', () async {
      await boot();
      final before = store.workOrders.length;
      final q = await repos.customer.decideQuotation(
        DemoStore.quotationQuoted,
        accept: true,
      );
      expect(q.status, QuotationStatus.accepted);
      expect(store.workOrders.length, before + 1);
      final wo = q.workOrder!;
      expect(wo.status, WorkStatus.queued);
      expect(wo.isCheckedIn, isFalse);
      expect(wo.awaitingCheckIn, isTrue);
      expect(q.workOrderRef, wo.ref);
      expect(q.payment, isNull);
      expect(q.amountDueCents, 385000);
      expect(q.paymentLabel, 'R 3 850.00 due at the counter');
      final row = store.workOrders.firstWhere((w) => w.id == wo.id);
      expect(row.quotationId, DemoStore.quotationQuoted);
      expect(row.serviceId, DemoStore.svcBumperScuff); // first item's service
      expect(row.outletId, DemoStore.outletMenlyn);
      expect(store.tasks.where((t) => t.workOrderId == wo.id), hasLength(1));

      // Staff see the same summary and the task in the queue.
      await signIn(DemoPersonas.supervisor);
      final staffView = await repos.staff.quotation(DemoStore.quotationQuoted);
      expect(staffView.status, QuotationStatus.accepted);
      expect(staffView.workOrder, wo);
      final queue = await repos.staff.tasks(
        scope: TaskScope.queue,
        outletId: DemoStore.outletMenlyn,
      );
      final task = queue.firstWhere((t) => t.workOrderId == wo.id);
      expect(task.workOrder?.isCheckedIn, isFalse);
    });

    test('checking a quotation work order in converts the quotation', () async {
      await boot(persona: DemoPersonas.supervisor);
      final before = await repos.staff.quotation(DemoStore.quotationAccepted);
      expect(before.status, QuotationStatus.accepted);
      expect(before.workOrder?.id, DemoStore.woAwaitingCheckIn);
      final changes = <DemoChange>[];
      final sub = store.changes.listen(changes.add);
      final result = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
        bay: 'Body 2',
      );
      expect(result.already, isFalse);
      expect(result.workOrder.isCheckedIn, isTrue);
      final after = await repos.staff.quotation(DemoStore.quotationAccepted);
      expect(after.status, QuotationStatus.converted);
      expect(after.workOrder?.isCheckedIn, isTrue);
      expect(after.workOrder?.id, DemoStore.woAwaitingCheckIn);
      await Future<void>.delayed(Duration.zero);
      expect(
        changes.any(
          (c) => c.table == 'quotations' && c.id == DemoStore.quotationAccepted,
        ),
        isTrue,
      );
      await sub.cancel();
      // Manual convert afterwards is a no-op on the same work order.
      final count = store.workOrders.length;
      expect(
        () => repos.staff.convertQuotation(DemoStore.quotationAccepted),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_transition',
          ),
        ),
      );
      expect(store.workOrders.length, count);
    });

    test('convert (staff-side) checks the existing work order in', () async {
      await boot(persona: DemoPersonas.supervisor);
      final count = store.workOrders.length;
      final converted = await repos.staff.convertQuotation(
        DemoStore.quotationAccepted,
      );
      expect(converted.status, QuotationStatus.converted);
      expect(converted.workOrder?.id, DemoStore.woAwaitingCheckIn);
      expect(converted.workOrder?.isCheckedIn, isTrue);
      expect(store.workOrders.length, count);
      final detail = await repos.staff.workOrder(DemoStore.woAwaitingCheckIn);
      expect(detail.workOrder.checkedInBy, DemoPersonas.supervisor.uid);
      expect(detail.events.map((e) => e.event), contains('checked_in'));
    });

    test(
      'record a quotation payment: validations, receipt, once only',
      () async {
        await boot(persona: DemoPersonas.technician);
        // Only accepted / converted quotations can be paid.
        await expectLater(
          repos.staff.recordPayment(
            RecordPaymentInput(
              quotationId: DemoStore.quotationQuoted,
              method: PaymentMethodKind.cash,
              amountCents: 385000,
              idempotencyKey: 'qp-0',
            ),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isConflict, 'conflict', true)
                .having((e) => e.message, 'message', contains('accepted')),
          ),
        );
        // The amount must equal the quoted total.
        await expectLater(
          repos.staff.recordPayment(
            RecordPaymentInput(
              quotationId: DemoStore.quotationAccepted,
              method: PaymentMethodKind.cash,
              amountCents: 285001,
              idempotencyKey: 'qp-1',
            ),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isValidation, 'validation', true)
                .having((e) => e.message, 'message', contains('R 2 850.00')),
          ),
        );
        // Unknown quotation → 404.
        await expectLater(
          repos.staff.recordPayment(
            RecordPaymentInput(
              quotationId: 'nope',
              method: PaymentMethodKind.cash,
              amountCents: 1,
              idempotencyKey: 'qp-2',
            ),
          ),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 404)),
        );

        final changes = <DemoChange>[];
        final sub = store.changes.listen(changes.add);
        final p = await repos.staff.recordPayment(
          RecordPaymentInput(
            quotationId: DemoStore.quotationAccepted,
            method: PaymentMethodKind.cash,
            amountCents: 285000,
            idempotencyKey: 'qp-3',
          ),
        );
        expect(p.status, PaymentStatus.successful);
        expect(p.quotationId, DemoStore.quotationAccepted);
        expect(p.bookingId, isNull);
        expect(p.customerId, 'seed_zanele');
        expect(p.provider, 'pos');
        expect(p.method, 'cash');
        expect(p.receiptNo, matches(RegExp(r'^RCP-7\d{4}$')));
        expect(p.verifiedAt, isNotNull);
        expect(p.receipt?['quotation_ref'], 'QT-${today.year}-0039');
        await Future<void>.delayed(Duration.zero);
        expect(changes.any((c) => c.table == 'payments'), isTrue);
        expect(
          changes.any(
            (c) =>
                c.table == 'quotations' && c.id == DemoStore.quotationAccepted,
          ),
          isTrue,
        );
        expect(
          changes.any(
            (c) =>
                c.table == 'work_orders' && c.id == DemoStore.woAwaitingCheckIn,
          ),
          isTrue,
        );
        await sub.cancel();

        // The quotation now carries the payment; nothing more is due.
        final q = await repos.staff.quotation(DemoStore.quotationAccepted);
        expect(q.status, QuotationStatus.accepted); // payment ≠ check-in
        expect(q.isPaid, isTrue);
        expect(q.payment?.id, p.id);
        expect(q.payment?.receiptNo, p.receiptNo);
        expect(q.payment?.method, 'cash');
        expect(q.payment?.amountCents, 285000);
        expect(q.amountDueCents, 0);
        expect(q.paymentLabel, 'Paid · cash · ${p.receiptNo}');

        // Idempotent replay; a new key is refused as already paid.
        final again = await repos.staff.recordPayment(
          RecordPaymentInput(
            quotationId: DemoStore.quotationAccepted,
            method: PaymentMethodKind.cardTerminal,
            amountCents: 285000,
            idempotencyKey: 'qp-3',
          ),
        );
        expect(again.id, p.id);
        await expectLater(
          repos.staff.recordPayment(
            RecordPaymentInput(
              quotationId: DemoStore.quotationAccepted,
              method: PaymentMethodKind.cash,
              amountCents: 285000,
              idempotencyKey: 'qp-4',
            ),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isConflict, 'conflict', true)
                .having((e) => e.message, 'message', contains('already paid')),
          ),
        );
        // The customer was told, and sees the receipt on the quote.
        expect(
          store.notifications.any(
            (n) =>
                n.recipientId == 'seed_zanele' &&
                n.templateKey == 'payment_successful' &&
                n.body.contains(p.receiptNo!),
          ),
          isTrue,
        );
        store.signInAs(
          const AuthUser(
            uid: 'seed_zanele',
            email: 'zanele@example.com',
            displayName: 'Zanele Mthembu',
            emailVerified: true,
            claims: {'app_role': 'customer', 'outlet_ids': <String>[]},
          ),
        );
        final mine = store.quotationDetail(DemoStore.quotationAccepted);
        expect(mine.payment?.receiptNo, p.receiptNo);
        expect(mine.paymentLabel, 'Paid · cash · ${p.receiptNo}');
      },
    );

    test(
      'quotation payment survives the check-in and replays offline',
      () async {
        await boot(persona: DemoPersonas.supervisor);
        final results = store.applySyncBatch([
          {
            'client_op_id': 'op-sync-qp',
            'kind': SyncKinds.paymentRecord,
            'payload': RecordPaymentInput(
              quotationId: DemoStore.quotationAccepted,
              method: PaymentMethodKind.cardTerminal,
              reference: 'SLIP 12',
              amountCents: 285000,
              idempotencyKey: 'op-sync-qp',
            ).toJson(),
          },
        ]);
        expect(results.single.applied, isTrue);
        final payment = Payment.fromJson(results.single.result!);
        expect(payment.quotationId, DemoStore.quotationAccepted);
        expect(payment.providerRef, 'SLIP 12');
        expect(payment.receiptNo, startsWith('RCP-'));

        await repos.staff.checkInWorkOrder(DemoStore.woAwaitingCheckIn);
        final q = await repos.staff.quotation(DemoStore.quotationAccepted);
        expect(q.status, QuotationStatus.converted);
        expect(q.isPaid, isTrue);
        expect(q.paymentLabel, 'Paid · card terminal · ${payment.receiptNo}');
        // Converted quotations can still be settled (nothing to pay here).
        expect(q.isPaymentDue, isFalse);
      },
    );
  });
}
