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

/// Cash on collection: `GET /config` flags, `POST /bookings
/// { payment_method: 'cash' }`, the 409 reasons and the staff hand-over rule
/// (`pickup/verify` refuses until the cash was recorded).
void main() {
  group('models & API', () {
    late _FakeAdapter adapter;
    late SparklingApi api;

    setUp(() {
      adapter = _FakeAdapter();
      api = SparklingApi(
        baseUrl: 'https://api.test/v1',
        tokenProvider: () async => 'tok',
        clientApp: 'customer',
        clientVersion: '1.0.0+1',
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('GET /config parses the public flags without auth', () async {
      adapter.handler = (o) async => _json({
        'flags': {
          'cash_on_collection': true,
          'payments_sandbox': false,
          'whatsapp_enabled': true,
          'future_flag': true,
        },
      });
      final cfg = await api.config();
      expect(cfg.flags.cashOnCollection, isTrue);
      expect(cfg.flags.paymentsSandbox, isFalse);
      expect(cfg.flags.whatsappEnabled, isTrue);
      expect(cfg.flags['future_flag'], isTrue);
      expect(cfg.flags['missing'], isFalse);
      expect(cfg.fetchedAt, isNotNull);
      final req = adapter.requests.single;
      expect(req.uri.path, '/v1/config');
      expect(req.headers.containsKey('Authorization'), isFalse);
      // Round-trips through the cache format.
      final back = AppConfig.fromJson(cfg.toJson());
      expect(back.flags, cfg.flags);
      expect(AppConfig.defaults.flags.cashOnCollection, isFalse);
      expect(AppConfig.fromJson(const {}).flags.cashOnCollection, isFalse);
    });

    test('BookingInput carries payment_method and Booking parses it', () {
      final json = BookingInput(
        vehicleId: 'v',
        outletId: 'o',
        serviceId: 's',
        slotStart: DateTime.utc(2026, 9, 22, 8),
        clientOpId: 'op',
        paymentMethod: PaymentChoice.cash,
      ).toJson();
      expect(json['payment_method'], 'cash');
      expect(
        BookingInput.fromJson(json).paymentMethod,
        PaymentChoice.cash,
      );
      expect(
        BookingInput(
          vehicleId: 'v',
          outletId: 'o',
          serviceId: 's',
          slotStart: DateTime.utc(2026, 9, 22, 8),
          clientOpId: 'op',
        ).toJson().containsKey('payment_method'),
        isFalse,
      );

      final b = Booking.fromJson({
        'id': 'b1',
        'ref': 'SPK-2026-0100',
        'customer_id': 'c',
        'status': 'confirmed',
        'slot_start': '2026-09-22T08:00:00Z',
        'slot_end': '2026-09-22T08:30:00Z',
        'total_cents': 8100,
        'payment_method': 'cash',
      });
      expect(b.paymentMethod, PaymentChoice.cash);
      expect(b.isCashOnCollection, isTrue);
      expect(b.isCashDue, isTrue);
      expect(b.toJson()['payment_method'], 'cash');
      final paid = b.copyWith(
        payment: const PaymentSummary(
          id: 'p',
          status: PaymentStatus.successful,
          amountCents: 8100,
        ),
      );
      expect(paid.isCashDue, isFalse);
      expect(paid.paymentMethod, PaymentChoice.cash);
      expect(
        Booking.fromJson({...b.toJson(), 'payment_method': null}).paymentMethod,
        isNull,
      );
      expect(PaymentChoice.fromDb('bitcoin'), isNull);
    });

    test('work-order booking expansion reports cash due', () {
      final wo = WorkOrder.fromJson({
        'id': 'w',
        'ref': 'WO-2026-1',
        'outlet_id': 'o',
        'vehicle_id': 'v',
        'customer_id': 'c',
        'service_id': 's',
        'status': 'verified',
        'booking': {
          'id': 'b',
          'ref': 'SPK-2026-0100',
          'status': 'completed',
          'total_cents': 8100,
          'payment_method': 'cash',
          'paid': false,
        },
      });
      expect(wo.isCashOnCollection, isTrue);
      expect(wo.isCashDue, isTrue);
      expect(wo.booking!.totalCents, 8100);
      final settled = wo.copyWith(booking: wo.booking!.copyWith(paid: true));
      expect(settled.isCashDue, isFalse);
      expect(settled.isCashOnCollection, isTrue);
      expect(WorkOrder.fromJson(wo.toJson()).booking, wo.booking);

      final card = WorkOrderCard.fromJson({
        'id': 'w',
        'ref': 'WO-2026-1',
        'status': 'verified',
        'booking': {'id': 'b', 'total_cents': 100, 'payment_method': 'card'},
      });
      expect(card.isCashOnCollection, isFalse);
      expect(card.isCashDue, isFalse);
    });

    test('409 reasons: cash_disabled and payment_due', () {
      final disabled = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': 'Cash on collection is not available at the moment',
          'details': {'reason': 'cash_disabled'},
        },
      }, statusCode: 409);
      expect(disabled.isCashDisabled, isTrue);
      expect(disabled.isPaymentDue, isFalse);
      expect(disabled.isByQuote, isFalse);

      final due = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': 'Cash payment of R 81.00 is due',
          'details': {
            'reason': 'payment_due',
            'booking_id': 'b1',
            'amount_cents': 8100,
            'method': 'cash',
          },
        },
      }, statusCode: 409);
      expect(due.isPaymentDue, isTrue);
      expect(due.paymentDueCents, 8100);
      expect(due.paymentDueBookingId, 'b1');
      expect(due.isCashDisabled, isFalse);

      // Reason at the top level of the error object also works.
      final flat = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': 'x',
          'reason': 'payment_due',
          'amount_cents': '500',
        },
      }, statusCode: 409);
      expect(flat.isPaymentDue, isTrue);
      expect(flat.paymentDueCents, 500);
    });

    test('ApiConfigRepository caches for the session and falls back', () async {
      final dir = await Directory.systemTemp.createTemp('sparkling_cfg_');
      HiveStore.reset();
      await HiveStore.ensureInitialized(path: dir.path);
      final cache = await LocalCache.open(boxName: 'cfg_test');
      addTearDown(() async {
        await Hive.deleteFromDisk();
        await Hive.close();
        HiveStore.reset();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      var calls = 0;
      adapter.handler = (o) async {
        calls++;
        return _json({
          'flags': {'cash_on_collection': true},
        });
      };
      final repo = ApiConfigRepository(api: api, cache: cache);
      expect(repo.current, isNull);
      final a = await repo.config();
      final b = await repo.config();
      expect(a.flags.cashOnCollection, isTrue);
      expect(b, same(a));
      expect(calls, 1);
      expect(repo.current, same(a));

      // Forced refetch hits the API again.
      await repo.config(force: true);
      expect(calls, 2);

      // Unreachable API → last known config from disk (fresh repository).
      adapter.handler = (o) async => throw DioException.connectionError(
        requestOptions: o,
        reason: 'offline',
      );
      final fresh = ApiConfigRepository(api: api, cache: cache);
      final fallback = await fresh.config();
      expect(fallback.flags.cashOnCollection, isTrue);
      // …and the safe defaults without any cache.
      final bare = ApiConfigRepository(api: api);
      expect((await bare.config()).flags.cashOnCollection, isFalse);
    });
  });

  group('demo store', () {
    late Directory dir;
    late Repositories repos;
    late DemoStore store;
    final today = DateTime.now();

    Future<void> boot({AuthUser persona = DemoPersonas.customer}) async {
      store = DemoStore(
        currentUser: persona,
        clock: () => DateTime(today.year, today.month, today.day, 10, 13),
      );
      repos = await SparklingCore.bootstrap(
        demo: true,
        hivePath: dir.path,
        demoStore: store,
        clientApp: persona.role.isStaff ? 'staff' : 'customer',
        demoUser: persona,
      );
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sparkling_cash_');
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

    BookingInput input({PaymentChoice? method}) => BookingInput(
      vehicleId: DemoStore.vehPolo,
      outletId: DemoStore.outletMenlyn,
      serviceId: DemoStore.svcExecWash,
      slotStart: DateTime(today.year, today.month, today.day, 14).add(
        const Duration(days: 3),
      ),
      clientOpId: SparklingApi.newOpId(),
      paymentMethod: method,
    );

    test('config exposes the demo flags (cash on by default)', () async {
      await boot();
      final cfg = await repos.config.config();
      expect(cfg.flags.cashOnCollection, isTrue);
      expect(cfg.flags.paymentsSandbox, isTrue);
      expect(cfg.flags.whatsappEnabled, isFalse);
      expect(repos.config.current, cfg);
      store.featureFlags['cash_on_collection'] = false;
      expect((await repos.config.config()).flags.cashOnCollection, isFalse);
    });

    test('cash booking is confirmed at once with no payment', () async {
      await boot();
      final b = await repos.customer.createBooking(
        input(method: PaymentChoice.cash),
      );
      expect(b.status, BookingStatus.confirmed);
      expect(b.paymentMethod, PaymentChoice.cash);
      expect(b.totalCents, greaterThan(0));
      expect(b.payment, isNull);
      expect(b.isCashDue, isTrue);
      final detail = await repos.customer.booking(b.id);
      expect(detail.isCashDue, isTrue);
      expect(detail.status, BookingStatus.confirmed);

      // Card stays pending until the payment verifies.
      final card = await repos.customer.createBooking(
        input(method: PaymentChoice.card),
      );
      expect(card.status, BookingStatus.pending);
      expect(card.paymentMethod, PaymentChoice.card);
      expect(card.isCashDue, isFalse);
    });

    test('cash is refused with cash_disabled when the flag is off', () async {
      await boot();
      store.featureFlags['cash_on_collection'] = false;
      await expectLater(
        repos.customer.createBooking(input(method: PaymentChoice.cash)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isCashDisabled, 'isCashDisabled', isTrue)
              .having((e) => e.statusCode, 'status', 409)
              .having(
                (e) => e.message,
                'message',
                contains('Cash on collection is not available'),
              ),
        ),
      );
      // Nothing was created.
      expect(store.bookings.where((b) => b.paymentMethod?.isCash ?? false)
          .where((b) => b.id != DemoStore.bookingReady), isEmpty);
    });

    test('pickup verify: payment_due → record cash → collected', () async {
      await boot(persona: DemoPersonas.technician);
      final staff = repos.staff;
      final detail = await staff.workOrder(DemoStore.woReady);
      expect(detail.workOrder.isCashDue, isTrue);
      expect(detail.workOrder.booking!.totalCents, 8100);
      expect(detail.task?.workOrder?.isCashDue, isTrue);
      final done = await staff.tasks(scope: TaskScope.done);
      final card = done.firstWhere((t) => t.workOrderId == DemoStore.woReady);
      expect(card.workOrder!.isCashOnCollection, isTrue);

      await expectLater(
        staff.verifyPickupOtp(DemoStore.woReady, '73104'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isPaymentDue, 'isPaymentDue', isTrue)
              .having((e) => e.paymentDueCents, 'amount', 8100)
              .having(
                (e) => e.paymentDueBookingId,
                'booking',
                DemoStore.bookingReady,
              ),
        ),
      );
      // The OTP attempt was not consumed by the refusal.
      expect(
        store.workOrders.firstWhere((w) => w.id == DemoStore.woReady).isCollected,
        isFalse,
      );

      final payment = await staff.recordPayment(
        RecordPaymentInput(
          bookingId: DemoStore.bookingReady,
          method: PaymentMethodKind.cash,
          amountCents: 8100,
          idempotencyKey: SparklingApi.newOpId(),
        ),
      );
      expect(payment.status.isVerified, isTrue);
      expect(payment.receipt?['method'], 'cash');
      final after = await staff.workOrder(DemoStore.woReady);
      expect(after.workOrder.isCashDue, isFalse);
      expect(after.workOrder.booking!.paid, isTrue);

      final result = await staff.verifyPickupOtp(DemoStore.woReady, '73104');
      expect(result.verified, isTrue);
      expect(
        store.workOrders.firstWhere((w) => w.id == DemoStore.woReady).isCollected,
        isTrue,
      );

      // The customer now sees the booking as paid by cash.
      store.signInAs(DemoPersonas.customer);
      final booking = store.bookingDetail(DemoStore.bookingReady);
      expect(booking.isPaid, isTrue);
      expect(booking.isCashDue, isFalse);
      expect(booking.paymentMethod, PaymentChoice.cash);
    });
  });
}
