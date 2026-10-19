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

const _wo = {
  'id': 'wo1',
  'ref': 'WO-2026-4819',
  'outlet_id': 'o1',
  'vehicle_id': 'v1',
  'customer_id': 'c1',
  'service_id': 's1',
  'status': 'queued',
  'checked_in_at': '2026-09-22T08:15:00Z',
  'checked_in_by': 'u1',
};

const _payment = {
  'id': 'p1',
  'booking_id': 'b1',
  'customer_id': 'c1',
  'provider': 'pos',
  'method': 'eft',
  'provider_ref': 'FNB-77120',
  'amount_cents': 12000,
  'currency': 'ZAR',
  'status': 'successful',
  'receipt_no': 'RCP-70001',
  'recorded_by': 'u1',
  'stage': 'checkin',
  'verified_at': '2026-09-22T08:15:00Z',
};

/// Payments at check-in and at collection (migration 0022): the API bodies the
/// check-in / hand-over calls send, the `stage` on payments, and the demo
/// store mirror (EFT reference rule, stage inference, payment carried by the
/// check-in / OTP calls, customer pay-now once the car is in).
void main() {
  group('models', () {
    test('CounterPaymentInput serialises and converts to a record body', () {
      const eft = CounterPaymentInput(
        method: PaymentMethodKind.eft,
        reference: ' FNB-77120 ',
        amountCents: 12000,
        idempotencyKey: 'op-1',
      );
      expect(eft.isMissingReference, isFalse);
      expect(eft.toJson(), {
        'method': 'eft',
        'reference': 'FNB-77120',
        'amount_cents': 12000,
        'idempotency_key': 'op-1',
      });
      final record = eft.toRecord(bookingId: 'b1', stage: PaymentStage.checkin);
      expect(record.toJson(), {
        'booking_id': 'b1',
        'method': 'eft',
        'reference': 'FNB-77120',
        'amount_cents': 12000,
        'idempotency_key': 'op-1',
        'stage': 'checkin',
      });
      expect(
        RecordPaymentInput.fromJson(record.toJson()).stage,
        PaymentStage.checkin,
      );

      const noRef = CounterPaymentInput(
        method: PaymentMethodKind.eft,
        amountCents: 100,
        idempotencyKey: 'op-2',
      );
      expect(noRef.isMissingReference, isTrue);
      const cash = CounterPaymentInput(
        method: PaymentMethodKind.cash,
        amountCents: 100,
        idempotencyKey: 'op-3',
      );
      expect(cash.isMissingReference, isFalse);
      expect(cash.toJson().containsKey('reference'), isFalse);
      expect(PaymentMethodKind.fromDb('eft'), PaymentMethodKind.eft);
      expect(PaymentMethodKind.eft.label, 'EFT');
      expect(PaymentStage.fromDb('collection'), PaymentStage.collection);
      expect(PaymentStage.fromDb('later'), isNull);
    });

    test('Payment, check-in and hand-over results carry the payment', () {
      final p = Payment.fromJson(_payment);
      expect(p.stage, PaymentStage.checkin);
      expect(p.method, 'eft');
      expect(Payment.fromJson(p.toJson()).stage, PaymentStage.checkin);

      final checkIn = WorkOrderCheckInResult.fromJson({
        'work_order': _wo,
        'task': null,
        'already': false,
        'payment': _payment,
      });
      expect(checkIn.payment?.receiptNo, 'RCP-70001');
      expect(
        WorkOrderCheckInResult.fromJson(checkIn.toJson()).payment,
        checkIn.payment,
      );
      expect(
        WorkOrderCheckInResult.fromJson({'work_order': _wo, 'already': true})
            .payment,
        isNull,
      );

      final verify = PickupVerifyResult.fromJson({
        'work_order': _wo,
        'collected_at': '2026-09-22T10:00:00Z',
        'collected': true,
        'payment': {..._payment, 'stage': 'collection'},
      });
      expect(verify.verified, isTrue);
      expect(verify.payment?.stage, PaymentStage.collection);
    });

    test('Booking.canPayNow — unpaid and live, not once collected', () {
      Booking make(
        String status, {
        Map<String, dynamic>? payment,
        Map<String, dynamic>? wo,
      }) => Booking.fromJson({
        'id': 'b1',
        'ref': 'SPK-2026-0100',
        'customer_id': 'c',
        'status': status,
        'slot_start': '2026-09-22T08:00:00Z',
        'slot_end': '2026-09-22T08:30:00Z',
        'total_cents': 12000,
        'payment': payment,
        'work_order': wo,
      });
      expect(make('confirmed').canPayNow, isTrue);
      expect(make('in_service').canPayNow, isTrue);
      expect(make('completed').canPayNow, isTrue);
      expect(make('cancelled').canPayNow, isFalse);
      expect(
        make(
          'in_service',
          payment: {'id': 'p', 'status': 'successful', 'amount_cents': 12000},
        ).canPayNow,
        isFalse,
      );
      expect(
        make(
          'in_service',
          payment: {'id': 'p', 'status': 'pending', 'amount_cents': 12000},
        ).canPayNow,
        isTrue,
      );
      expect(
        make(
          'completed',
          wo: {
            'id': 'w',
            'ref': 'WO-1',
            'status': 'verified',
            'collected_at': '2026-09-22T10:00:00Z',
          },
        ).canPayNow,
        isFalse,
      );
    });
  });

  group('API bodies', () {
    late _FakeAdapter adapter;
    late SparklingApi api;

    setUp(() {
      adapter = _FakeAdapter();
      api = SparklingApi(
        baseUrl: 'https://api.test/v1',
        tokenProvider: () async => 'tok',
        clientApp: 'staff',
        clientVersion: '1.0.0+1',
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    const payment = CounterPaymentInput(
      method: PaymentMethodKind.cardTerminal,
      reference: '048213',
      amountCents: 12000,
      idempotencyKey: 'pos-ci-0001',
    );

    test('checkInWorkOrder sends payment and parses it back', () async {
      adapter.handler = (o) async => _json({
        'work_order': _wo,
        'task': null,
        'already': false,
        'payment': {
          ..._payment,
          'method': 'card_terminal',
          'provider_ref': '048213',
        },
      }, status: 201);
      final r = await api.checkInWorkOrder(
        'wo1',
        bay: 'Bay 2',
        payment: payment,
      );
      expect(adapter.requests.single.data, {
        'bay': 'Bay 2',
        'payment': {
          'method': 'card_terminal',
          'reference': '048213',
          'amount_cents': 12000,
          'idempotency_key': 'pos-ci-0001',
        },
      });
      expect(r.workOrder.isCheckedIn, isTrue);
      expect(r.payment?.method, 'card_terminal');
      expect(r.payment?.stage, PaymentStage.checkin);
    });

    test('checkinBooking sends payment and the booking carries it', () async {
      adapter.handler = (o) async => _json({
        'booking': {
          'id': 'b1',
          'ref': 'SPK-2026-0100',
          'customer_id': 'c1',
          'status': 'in_service',
          'slot_start': '2026-09-22T08:00:00Z',
          'slot_end': '2026-09-22T08:30:00Z',
          'total_cents': 12000,
          'payment_method': 'card',
        },
        'work_order': _wo,
        'task': null,
        'created': false,
        'payment': _payment,
      });
      final b = await api.checkinBooking(
        'b1',
        bay: 'Bay 1',
        priority: 1,
        payment: payment,
      );
      final req = adapter.requests.single;
      expect(req.uri.path, '/v1/bookings/b1/checkin');
      expect((req.data as Map)['payment'], payment.toJson());
      expect(b.isPaid, isTrue);
      expect(b.payment?.receiptNo, 'RCP-70001');
      expect(b.payment?.method, 'eft');
    });

    test('verifyPickupOtp sends payment with the OTP', () async {
      adapter.handler = (o) async => _json({
        'work_order': _wo,
        'collected_at': '2026-09-22T10:00:00Z',
        'collected': true,
        'payment': {..._payment, 'stage': 'collection'},
      });
      final r = await api.verifyPickupOtp('wo1', '48213', payment: payment);
      expect(adapter.requests.single.data, {
        'otp': '48213',
        'payment': payment.toJson(),
      });
      expect(r.verified, isTrue);
      expect(r.payment?.stage, PaymentStage.collection);
      // Without a payment the body is just the OTP, as before.
      adapter.requests.clear();
      await api.verifyPickupOtp('wo1', '48213');
      expect(adapter.requests.single.data, {'otp': '48213'});
    });

    test('recordPayment carries stage and the EFT reference', () async {
      adapter.handler = (o) async =>
          _json({'payment': _payment, 'duplicate': false}, status: 201);
      final p = await api.recordPayment(
        const RecordPaymentInput(
          bookingId: 'b1',
          method: PaymentMethodKind.eft,
          reference: 'FNB-77120',
          amountCents: 12000,
          idempotencyKey: 'pos-eft-0001',
          stage: PaymentStage.checkin,
        ),
      );
      expect(adapter.requests.single.data, {
        'booking_id': 'b1',
        'method': 'eft',
        'reference': 'FNB-77120',
        'amount_cents': 12000,
        'idempotency_key': 'pos-eft-0001',
        'stage': 'checkin',
      });
      expect(p.stage, PaymentStage.checkin);
    });
  });

  group('demo store', () {
    late Directory dir;
    late Repositories repos;
    late DemoStore store;

    Future<void> boot({AuthUser persona = DemoPersonas.supervisor}) async {
      dir = await Directory.systemTemp.createTemp('sparkling_counter_pay_');
      HiveStore.reset();
      store = DemoStore(currentUser: persona)
        ..featureFlags['auto_assignment'] = false;
      repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: 'staff',
        hivePath: dir.path,
        demoUser: persona,
        demoStore: store,
      );
    }

    tearDown(() async {
      await repos.dispose();
      await Hive.deleteFromDisk();
      await Hive.close();
      HiveStore.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('check-in of a quotation work order with an EFT payment records it at stage checkin', () async {
      await boot();
      final quote = await repos.staff.quotation(DemoStore.quotationAccepted);
      expect(quote.isPaymentDue, isTrue);
      final result = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
        bay: 'Body 2',
        payment: CounterPaymentInput(
          method: PaymentMethodKind.eft,
          reference: 'EFT-2200',
          amountCents: quote.amountDueCents,
          idempotencyKey: 'test-ci-eft-1',
        ),
      );
      expect(result.already, isFalse);
      expect(result.workOrder.isCheckedIn, isTrue);
      expect(result.payment, isNotNull);
      expect(result.payment!.status.isVerified, isTrue);
      expect(result.payment!.quotationId, DemoStore.quotationAccepted);
      expect(result.payment!.method, 'eft');
      expect(result.payment!.providerRef, 'EFT-2200');
      expect(result.payment!.stage, PaymentStage.checkin);
      expect(result.payment!.receiptNo, isNotNull);
      final after = await repos.staff.quotation(DemoStore.quotationAccepted);
      expect(after.isPaid, isTrue);
      expect(after.status, QuotationStatus.converted);
      // A repeated check-in with the same payment key is idempotent.
      final again = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
        payment: CounterPaymentInput(
          method: PaymentMethodKind.eft,
          reference: 'EFT-2200',
          amountCents: quote.amountDueCents,
          idempotencyKey: 'test-ci-eft-1',
        ),
      );
      expect(again.already, isTrue);
      expect(again.payment?.id, result.payment!.id);
      expect(
        store.payments.where(
          (p) => p.quotationId == DemoStore.quotationAccepted,
        ),
        hasLength(1),
      );
    });

    test('a refused payment (EFT without reference, wrong amount) leaves the check-in untouched', () async {
      await boot();
      await expectLater(
        repos.staff.checkInWorkOrder(
          DemoStore.woAwaitingCheckIn,
          payment: const CounterPaymentInput(
            method: PaymentMethodKind.eft,
            amountCents: 285000,
            idempotencyKey: 'test-ci-eft-2',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isValidation,
            'validation',
            isTrue,
          ),
        ),
      );
      await expectLater(
        repos.staff.checkInWorkOrder(
          DemoStore.woAwaitingCheckIn,
          payment: const CounterPaymentInput(
            method: PaymentMethodKind.cash,
            amountCents: 1,
            idempotencyKey: 'test-ci-eft-3',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isValidation,
            'validation',
            isTrue,
          ),
        ),
      );
      final detail = await repos.staff.workOrder(DemoStore.woAwaitingCheckIn);
      expect(detail.workOrder.isCheckedIn, isFalse);
      expect(
        store.payments.any((p) => p.quotationId == DemoStore.quotationAccepted),
        isFalse,
      );
    });

    test('booking check-in with a card-terminal payment confirms and settles an unpaid booking', () async {
      // Ayesha (manager) covers both outlets; the booking is at Glen Village.
      await boot(persona: DemoPersonas.manager);
      // Make Thabo's next booking unpaid (its online payment never completed).
      store.payments.removeWhere((p) => p.bookingId == DemoStore.bookingNext);
      final before = store.bookingDetail(DemoStore.bookingNext);
      expect(before.isPaymentDue, isTrue);
      final booking = await repos.staff.checkinBooking(
        DemoStore.bookingNext,
        bay: 'Bay 1',
        payment: CounterPaymentInput(
          method: PaymentMethodKind.cardTerminal,
          reference: '048213',
          amountCents: before.totalCents,
          idempotencyKey: 'test-bci-1',
        ),
      );
      expect(booking.status, BookingStatus.inService);
      expect(booking.isPaid, isTrue);
      expect(booking.payment?.method, 'card_terminal');
      final payment = store.payments.firstWhere(
        (p) => p.bookingId == DemoStore.bookingNext,
      );
      expect(payment.stage, PaymentStage.checkin);
      expect(payment.receipt?['stage'], 'checkin');
      expect(payment.receipt?['reference'], '048213');
      final tasks = await repos.staff.tasks(
        scope: TaskScope.queue,
        outletId: DemoStore.outletGlenVillage,
      );
      final card = tasks
          .where((t) => t.workOrder?.booking?.id == DemoStore.bookingNext)
          .firstOrNull;
      if (card != null) {
        expect(card.workOrder!.isPaymentDue, isFalse);
        expect(card.workOrder!.booking!.paid, isTrue);
      }
    });

    test('hand-over with a cash payment settles cash on collection and releases the keys in one call', () async {
      await boot(persona: DemoPersonas.technician);
      final staff = repos.staff;
      final detail = await staff.workOrder(DemoStore.woReady);
      expect(detail.workOrder.isCashDue, isTrue);
      // Still refused without a payment …
      await expectLater(
        staff.verifyPickupOtp(DemoStore.woReady, '73104'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isPaymentDue,
            'isPaymentDue',
            isTrue,
          ),
        ),
      );
      // … a wrong amount refuses the whole call …
      await expectLater(
        staff.verifyPickupOtp(
          DemoStore.woReady,
          '73104',
          payment: const CounterPaymentInput(
            method: PaymentMethodKind.cash,
            amountCents: 1,
            idempotencyKey: 'test-hv-0',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isValidation,
            'validation',
            isTrue,
          ),
        ),
      );
      expect(
        store.payments.any((p) => p.bookingId == DemoStore.bookingReady),
        isFalse,
      );
      // … and the right one records the payment (stage collection) and hands over.
      final result = await staff.verifyPickupOtp(
        DemoStore.woReady,
        '73104',
        payment: const CounterPaymentInput(
          method: PaymentMethodKind.cash,
          reference: 'till 2',
          amountCents: 8100,
          idempotencyKey: 'test-hv-1',
        ),
      );
      expect(result.verified, isTrue);
      expect(result.payment, isNotNull);
      expect(result.payment!.stage, PaymentStage.collection);
      expect(result.payment!.method, 'cash');
      expect(result.payment!.providerRef, 'till 2');
      expect(
        store.workOrders
            .firstWhere((w) => w.id == DemoStore.woReady)
            .isCollected,
        isTrue,
      );
      final after = await staff.workOrder(DemoStore.woReady);
      expect(after.workOrder.isCashDue, isFalse);
      expect(after.workOrder.booking!.paid, isTrue);
    });

    test('standalone record infers the stage from the booking and accepts EFT with a reference', () async {
      // The manager covers both outlets (bookingReady is Menlyn, bookingNext
      // Glen Village).
      await boot(persona: DemoPersonas.manager);
      // bookingReady is completed → collection.
      final collection = await repos.staff.recordPayment(
        const RecordPaymentInput(
          bookingId: DemoStore.bookingReady,
          method: PaymentMethodKind.eft,
          reference: 'FNB-1',
          amountCents: 8100,
          idempotencyKey: 'test-rec-1',
        ),
      );
      expect(collection.stage, PaymentStage.collection);
      expect(collection.method, 'eft');
      // EFT without a reference is a 400, like the API.
      store.payments.removeWhere((p) => p.bookingId == DemoStore.bookingNext);
      final nextTotal = store.bookingDetail(DemoStore.bookingNext).totalCents;
      await expectLater(
        repos.staff.recordPayment(
          RecordPaymentInput(
            bookingId: DemoStore.bookingNext,
            method: PaymentMethodKind.eft,
            amountCents: nextTotal,
            idempotencyKey: 'test-rec-2',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isValidation,
            'validation',
            isTrue,
          ),
        ),
      );
      // bookingNext is confirmed (awaiting check-in) → booking; an explicit stage wins.
      final explicit = await repos.staff.recordPayment(
        RecordPaymentInput(
          bookingId: DemoStore.bookingNext,
          method: PaymentMethodKind.cash,
          amountCents: nextTotal,
          idempotencyKey: 'test-rec-3',
          stage: PaymentStage.checkin,
        ),
      );
      expect(explicit.stage, PaymentStage.checkin);
    });

    test(
      'the customer can pay an unpaid booking in-app once the car is ready',
      () async {
        await boot(persona: DemoPersonas.customer);
        final booking = await repos.customer.booking(DemoStore.bookingReady);
        expect(booking.canPayNow, isTrue);
        expect(booking.isCashOnCollection, isTrue);
        final intent = await repos.customer.createPaymentIntent(
          bookingId: booking.id,
        );
        expect(intent.payment.stage, PaymentStage.collection);
        final paid = await repos.customer.confirmSandboxPayment(
          intent.payment.id,
        );
        expect(paid.status.isVerified, isTrue);
        final after = await repos.customer.booking(DemoStore.bookingReady);
        expect(after.isPaid, isTrue);
        expect(after.canPayNow, isFalse);
        expect(after.isCashDue, isFalse);
        // Paid in-app: the hand-over no longer needs a counter payment.
        store.signInAs(DemoPersonas.supervisor);
        final result = store.verifyPickupOtp(DemoStore.woReady, '73104');
        expect(result.verified, isTrue);
        expect(result.payment, isNull);
      },
    );
  });
}
