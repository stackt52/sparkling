import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Pay at check-in or on collection (`bookings.pay_at`): a counter booking
/// (`payment_method: cash`) says when the customer settles it — at the counter
/// when the car is dropped off (`checkin`) or when it is collected
/// (`collection`, the default). Online bookings carry `booking`.
void main() {
  group('models', () {
    test('Booking and BookingInput round-trip pay_at; helpers read it', () {
      final json = {
        'id': 'b1',
        'ref': 'SPK-2026-0001',
        'customer_id': 'c1',
        'vehicle_id': 'v1',
        'outlet_id': 'o1',
        'service_id': 's1',
        'slot_start': '2026-10-20T08:00:00.000Z',
        'slot_end': '2026-10-20T08:30:00.000Z',
        'status': 'confirmed',
        'total_cents': 15000,
        'payment_method': 'cash',
        'pay_at': 'checkin',
      };
      final b = Booking.fromJson(json);
      expect(b.payAt, PaymentStage.checkin);
      expect(b.isCashOnCollection, isTrue);
      expect(b.paysAtCheckIn, isTrue);
      expect(b.counterPaymentLabel, 'Pay at check-in');
      expect(b.isCashDue, isTrue);
      expect(b.toJson()['pay_at'], 'checkin');
      final later = b.copyWith(payment: null);
      expect(later.payAt, PaymentStage.checkin);
      final collection = Booking.fromJson({...json, 'pay_at': 'collection'});
      expect(collection.paysAtCheckIn, isFalse);
      expect(collection.counterPaymentLabel, 'Cash on collection');
      // Older rows without the column still read as cash on collection.
      final legacy = Booking.fromJson({...json}..remove('pay_at'));
      expect(legacy.payAt, isNull);
      expect(legacy.counterPaymentLabel, 'Cash on collection');

      final input = BookingInput(
        vehicleId: 'v1',
        outletId: 'o1',
        serviceId: 's1',
        slotStart: DateTime.utc(2026, 10, 20, 8),
        clientOpId: 'op-1',
        paymentMethod: PaymentChoice.cash,
        payAt: PaymentStage.checkin,
      );
      expect(input.toJson()['pay_at'], 'checkin');
      // pay_at only travels with a counter booking.
      final card = BookingInput(
        vehicleId: 'v1',
        outletId: 'o1',
        serviceId: 's1',
        slotStart: DateTime.utc(2026, 10, 20, 8),
        clientOpId: 'op-2',
        paymentMethod: PaymentChoice.card,
        payAt: PaymentStage.checkin,
      );
      expect(card.toJson().containsKey('pay_at'), isFalse);
      expect(BookingInput.fromJson(input.toJson()).payAt, PaymentStage.checkin);

      final wob = WorkOrderBooking.fromJson({
        'id': 'b1',
        'total_cents': 15000,
        'payment_method': 'cash',
        'pay_at': 'checkin',
        'paid': false,
      });
      expect(wob.paysAtCheckIn, isTrue);
      expect(wob.counterPaymentLabel, 'Pay at check-in');
      expect(wob.copyWith(paid: true).payAt, PaymentStage.checkin);
      expect(wob.toJson()['pay_at'], 'checkin');
    });

    test('WalkInBookingInput sends payment_method + pay_at for "pay on collection"', () {
      const later = WalkInBookingInput(
        customerId: 'c1',
        vehicleId: 'v1',
        outletId: 'o1',
        serviceId: 's1',
        clientOpId: 'op-3',
        paymentMethod: PaymentChoice.cash,
        payAt: PaymentStage.collection,
      );
      expect(later.paysOnCollection, isTrue);
      expect(later.toJson()['payment_method'], 'cash');
      expect(later.toJson()['pay_at'], 'collection');
      expect(
        WalkInBookingInput.fromJson(later.toJson()).paysOnCollection,
        isTrue,
      );
      const now = WalkInBookingInput(
        customerId: 'c1',
        vehicleId: 'v1',
        outletId: 'o1',
        serviceId: 's1',
        clientOpId: 'op-4',
      );
      expect(now.paysOnCollection, isFalse);
      expect(now.toJson().containsKey('pay_at'), isFalse);
    });
  });

  group('demo store', () {
    late Directory dir;
    late Repositories repos;
    late DemoStore store;

    Future<void> boot({AuthUser persona = DemoPersonas.customer}) async {
      dir = await Directory.systemTemp.createTemp('sparkling_pay_at_');
      HiveStore.reset();
      store = DemoStore(currentUser: persona)
        ..featureFlags['auto_assignment'] = false;
      repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: persona.role.isStaff ? 'staff' : 'customer',
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

    BookingInput input(
      String op, {
      PaymentChoice? method,
      PaymentStage? payAt,
    }) => BookingInput(
      vehicleId: DemoStore.vehCorolla,
      outletId: DemoStore.outletMenlyn,
      serviceId: DemoStore.svcExtWash,
      slotStart: DateTime.now()
          .add(const Duration(days: 2))
          .copyWith(
            hour: 10,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          ),
      clientOpId: op,
      paymentMethod: method,
      payAt: payAt,
    );

    test('customer: pay at check-in confirms the booking, stores pay_at and shows on the staff card', () async {
      await boot();
      final b = await repos.customer.createBooking(
        input(
          'op-payat-1',
          method: PaymentChoice.cash,
          payAt: PaymentStage.checkin,
        ),
      );
      expect(b.status, BookingStatus.confirmed);
      expect(b.payAt, PaymentStage.checkin);
      expect(b.paysAtCheckIn, isTrue);
      expect(b.isCashDue, isTrue);
      expect(store.payments.where((p) => p.bookingId == b.id), isEmpty);
      // Default: cash → collection; card → booking.
      final later = await repos.customer.createBooking(
        input(
          'op-payat-2',
          method: PaymentChoice.cash,
        ).copyWithSlot(const Duration(hours: 1)),
      );
      expect(later.payAt, PaymentStage.collection);
      expect(later.paysAtCheckIn, isFalse);
      final online = await repos.customer.createBooking(
        input(
          'op-payat-3',
          method: PaymentChoice.card,
        ).copyWithSlot(const Duration(hours: 2)),
      );
      expect(online.status, BookingStatus.pending);
      expect(online.payAt, PaymentStage.booking);

      // The work order's booking expansion carries it for the staff check-in form.
      final wo = store.workOrders.firstWhere((w) => w.bookingId == b.id);
      final detail = store.workOrderDetail(wo.id);
      expect(detail.workOrder.booking?.payAt, PaymentStage.checkin);
      expect(detail.workOrder.booking?.paysAtCheckIn, isTrue);
      expect(detail.workOrder.isCashDue, isTrue);
    });

    test('flag off refuses pay at check-in like cash on collection', () async {
      await boot();
      store.featureFlags['cash_on_collection'] = false;
      await expectLater(
        repos.customer.createBooking(
          input(
            'op-payat-4',
            method: PaymentChoice.cash,
            payAt: PaymentStage.checkin,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isCashDisabled,
            'cashDisabled',
            isTrue,
          ),
        ),
      );
    });

    test('staff walk-in "pay on collection": confirmed, nothing recorded, keys held until paid', () async {
      await boot(persona: DemoPersonas.technician);
      final b = await repos.staff.createWalkInBooking(
        WalkInBookingInput(
          customerId: DemoPersonas.customer.uid,
          vehicleId: DemoStore.vehCorolla,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-walk-payat-1',
          checkin: const WalkInCheckin(bay: 'Bay 2'),
          paymentMethod: PaymentChoice.cash,
          payAt: PaymentStage.collection,
        ),
      );
      expect(b.status, BookingStatus.inService);
      expect(b.paymentMethod, PaymentChoice.cash);
      expect(b.payAt, PaymentStage.collection);
      expect(b.isCashDue, isTrue);
      expect(store.payments.where((p) => p.bookingId == b.id), isEmpty);
      final wo = store.workOrders.firstWhere((w) => w.bookingId == b.id);
      expect(store.workOrderDetail(wo.id).workOrder.isCashDue, isTrue);
      // A walk-in paid at the counter now is "at check-in".
      final now = await repos.staff.createWalkInBooking(
        WalkInBookingInput(
          customerId: DemoPersonas.customer.uid,
          vehicleId: DemoStore.vehCorolla,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-walk-payat-2',
        ),
      );
      expect(now.payAt, PaymentStage.checkin);
      expect(now.isCashOnCollection, isFalse);
    });
  });
}

extension on BookingInput {
  BookingInput copyWithSlot(Duration shift) => BookingInput(
    vehicleId: vehicleId,
    outletId: outletId,
    serviceId: serviceId,
    slotStart: slotStart.add(shift),
    clientOpId: clientOpId,
    paymentMethod: paymentMethod,
    payAt: payAt,
  );
}
