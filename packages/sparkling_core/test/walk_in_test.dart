import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Demo-mode contract for the staff walk-in flow (STF-010/012):
/// customer search + registration, vehicles on behalf of a customer,
/// walk-in bookings (capacity, pricing, check-in) and POS payment records.
void main() {
  late Directory dir;
  late Repositories repos;
  late DemoStore store;
  final today = DateTime.now();

  Future<void> boot({DemoStore? custom}) async {
    store =
        custom ??
        DemoStore(
          currentUser: DemoPersonas.technician,
          // Wednesday-ish 10:13 local — inside opening hours of every outlet.
          clock: () => DateTime(today.year, today.month, today.day, 10, 13),
        );
    repos = await SparklingCore.bootstrap(
      demo: true,
      hivePath: dir.path,
      demoStore: store,
      clientApp: 'staff',
      demoUser: DemoPersonas.technician,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sparkling_walkin_');
    HiveStore.reset();
    await boot();
  });

  tearDown(() async {
    await repos.dispose();
    store.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    HiveStore.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('models', () {
    test('CustomerInput normalises SA phone numbers to E.164', () {
      expect(CustomerInput.normalisePhone('082 123 4567'), '+27821234567');
      expect(CustomerInput.normalisePhone('+27 82 123 4567'), '+27821234567');
      expect(CustomerInput.normalisePhone('27821234567'), '+27821234567');
      expect(CustomerInput.phoneKey('+27 83 111 2222'), '27831112222');
    });

    test('WalkInBookingInput serialises the staff contract', () {
      final json = const WalkInBookingInput(
        customerId: 'c',
        vehicleId: 'v',
        outletId: 'o',
        serviceId: 's',
        clientOpId: 'op',
        checkin: WalkInCheckin(bay: 'Bay 2', priority: 1),
      ).toJson();
      expect(json['walk_in'], isTrue);
      expect(json['customer_id'], 'c');
      expect(json.containsKey('slot_start'), isFalse);
      expect(json['checkin'], {'bay': 'Bay 2', 'priority': 1});
      final back = WalkInBookingInput.fromJson(json);
      expect(back.isNow, isTrue);
      expect(back.checkin?.bay, 'Bay 2');
    });

    test('ApiException.existingCustomer reads object or list details', () {
      final fromObject = ApiException.fromEnvelope({
        'error': {
          'code': 'conflict',
          'message': 'dup',
          'details': {
            'existing_customer': {'id': 'seed_thabo', 'full_name': 'Thabo'},
          },
        },
      }, statusCode: 409);
      expect(fromObject.isConflict, isTrue);
      expect(fromObject.existingCustomer?['id'], 'seed_thabo');
      final fromList = ApiException.fromEnvelope({
        'error': {
          'code': 'conflict',
          'message': 'dup',
          'details': [
            {'existing_customer': {'id': 'x'}},
          ],
        },
      }, statusCode: 409);
      expect(fromList.existingCustomer?['id'], 'x');
      expect(fromList.existingVehicleId, isNull);
    });
  });

  group('search', () {
    test('matches name, phone, e-mail and plate (min 2 chars)', () async {
      final byName = await repos.staff.searchCustomers('thabo');
      expect(byName.map((c) => c.fullName), ['Thabo Nkosi']);
      final thabo = byName.single;
      expect(thabo.loyalty?.tier, LoyaltyTier.gold);
      expect(thabo.vehicles.map((v) => v.registrationNo), [
        'KL 45 MN GP',
        'CJ 12 PZ GP',
      ]);
      expect(thabo.vehicles.first.discVerified, isTrue);

      expect(
        (await repos.staff.searchCustomers('083 111 3333')).single.fullName,
        'Naledi Mokoena',
      );
      expect(
        (await repos.staff.searchCustomers('0831114444')).single.fullName,
        'Sipho Dlamini',
      );
      expect(
        (await repos.staff.searchCustomers('zanele@example')).single.fullName,
        'Zanele Mthembu',
      );
      expect(
        (await repos.staff.searchCustomers('hr88')).single.fullName,
        'Naledi Mokoena',
      );
      expect(
        (await repos.staff.searchCustomers('KL 45 MN')).single.fullName,
        'Thabo Nkosi',
      );
      expect(await repos.staff.searchCustomers('t'), isEmpty);
      expect(await repos.staff.searchCustomers('nobody'), isEmpty);
      // Staff profiles never appear.
      expect(await repos.staff.searchCustomers('pieter'), isEmpty);
    });
  });

  group('register', () {
    test('creates a walkin_ profile, is idempotent, and dedupes', () async {
      final input = CustomerInput(
        fullName: 'Lindiwe Zulu',
        phone: '072 555 0199',
        email: 'Lindiwe@Example.com',
        whatsappOptIn: true,
        clientOpId: 'op-c1',
      );
      final c = await repos.staff.createCustomer(input);
      expect(c.id, startsWith('walkin_'));
      expect(c.isWalkIn, isTrue);
      expect(c.phone, '+27725550199');
      expect(c.email, 'lindiwe@example.com');
      expect(c.loyalty, isNull);
      expect(c.vehicles, isEmpty);
      expect(c.initials, 'LZ');

      // Same client_op_id → same customer.
      final again = await repos.staff.createCustomer(input);
      expect(again.id, c.id);

      // Now searchable.
      expect(
        (await repos.staff.searchCustomers('lindiwe')).single.id,
        c.id,
      );

      // Duplicate phone (different formatting) → 409 with the existing row.
      try {
        await repos.staff.createCustomer(
          const CustomerInput(
            fullName: 'L Zulu',
            phone: '+27 72 555 0199',
            clientOpId: 'op-c2',
          ),
        );
        fail('expected conflict');
      } on ApiException catch (e) {
        expect(e.isConflict, isTrue);
        expect(e.existingCustomer?['id'], c.id);
        expect(CustomerSummary.fromJson(e.existingCustomer!).fullName,
            'Lindiwe Zulu');
      }

      // Duplicate e-mail of a seeded app customer.
      try {
        await repos.staff.createCustomer(
          const CustomerInput(
            fullName: 'Someone',
            phone: '061 000 0000',
            email: 'THABO@example.com',
            clientOpId: 'op-c3',
          ),
        );
        fail('expected conflict');
      } on ApiException catch (e) {
        expect(e.existingCustomer?['id'], 'seed_thabo');
      }
    });

    test('validates name and phone', () async {
      expect(
        () => repos.staff.createCustomer(
          const CustomerInput(fullName: 'X', phone: '0821', clientOpId: 'v1'),
        ),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'v', true)),
      );
    });

    test('customers cannot use the staff routes', () async {
      await repos.auth.signInWithEmail('thabo@example.com', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        () => repos.staff.searchCustomers('thabo'),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'f', true)),
      );
    });
  });

  group('vehicles for a customer', () {
    test('creates, detects duplicates, force adds', () async {
      final c = await repos.staff.createCustomer(
        const CustomerInput(
          fullName: 'Lindiwe Zulu',
          phone: '072 555 0199',
          clientOpId: 'op-c1',
        ),
      );
      final v = await repos.staff.createCustomerVehicle(
        c.id,
        const VehicleInput(registrationNo: 'ND 123 456', make: 'Kia'),
      );
      expect(v.customerId, c.id);
      expect(v.registrationNo, 'ND 123 456');
      expect(v.discVerified, isFalse);
      expect(
        (await repos.staff.searchCustomers('nd123')).single.vehicles.single.id,
        v.id,
      );

      try {
        await repos.staff.createCustomerVehicle(
          c.id,
          const VehicleInput(registrationNo: 'nd123456'),
        );
        fail('expected conflict');
      } on ApiException catch (e) {
        expect(e.isConflict, isTrue);
        expect(e.existingVehicleId, v.id);
      }
      final forced = await repos.staff.createCustomerVehicle(
        c.id,
        const VehicleInput(registrationNo: 'ND 123 456'),
        force: true,
      );
      expect(forced.id, isNot(v.id));

      // Another customer may own the same plate (no cross-customer clash).
      final other = await repos.staff.createCustomerVehicle(
        'seed_thabo',
        const VehicleInput(registrationNo: 'ND 123 456'),
      );
      expect(other.customerId, 'seed_thabo');
    });
  });

  group('walk-in booking', () {
    test(
      'books now on the slot grid, confirmed, no plan benefit on Exterior Wash, checks in',
      () async {
        final thabo = (await repos.staff.searchCustomers('thabo')).single;
        final polo = thabo.vehicles.firstWhere(
          (v) => v.registrationNo == 'CJ 12 PZ GP',
        );
        final catalogue = await repos.catalogue.outletServices(
          DemoStore.outletMenlyn,
        );
        final express = catalogue.byCode('EXT_WASH')!;

        final b = await repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: polo.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: express.id,
            clientOpId: 'op-b1',
            checkin: const WalkInCheckin(bay: 'Bay 3', priority: 2),
          ),
        );
        expect(b.customerId, 'seed_thabo');
        expect(b.slotStart, DateTime(today.year, today.month, today.day, 10));
        expect(b.slotEnd.difference(b.slotStart).inMinutes,
            express.durationMinutes);
        expect(b.priceCents, express.priceFor(VehicleSize.small));
        // Exterior Wash is a Gold entitlement service (G2) — Thabo chose G1,
        // and the Gold discount only covers *other* services → full price.
        expect(b.discountCents, 0);
        expect(b.totalCents, b.priceCents);
        expect(b.discountLabel, isNull);
        expect(b.membership?.planCode, 'gold');
        expect(b.membership?.benefit, isNull);
        expect(b.pendingSync, isFalse);
        // Checked in immediately → in_service with a work order + task.
        expect(b.status, BookingStatus.inService);
        expect(b.workOrder, isNotNull);
        expect(b.workOrder!.bay, 'Bay 3');
        expect(b.vehicle?.registrationNo, 'CJ 12 PZ GP');
        expect(b.notes, 'Walk-in');
        final queue = await repos.staff.tasks(scope: TaskScope.queue);
        expect(
          queue.any((t) => t.workOrderId == b.workOrder!.id),
          isTrue,
        );
        expect(store.workOrders.last.priority, 2);

        // Idempotent replay.
        final again = await repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: polo.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: express.id,
            clientOpId: 'op-b1',
          ),
        );
        expect(again.id, b.id);
      },
    );

    test('without check-in stays confirmed; silver tier has no discount',
        () async {
      final c = await repos.staff.createCustomer(
        const CustomerInput(
          fullName: 'Lindiwe Zulu',
          phone: '072 555 0199',
          clientOpId: 'op-c1',
        ),
      );
      final v = await repos.staff.createCustomerVehicle(
        c.id,
        const VehicleInput(registrationNo: 'ND 123 456'),
      );
      final slot = DateTime(today.year, today.month, today.day, 14, 0);
      final b = await repos.staff.createWalkInBooking(
        WalkInBookingInput(
          customerId: c.id,
          vehicleId: v.id,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-b2',
          slotStart: slot,
        ),
      );
      expect(b.status, BookingStatus.confirmed);
      expect(b.workOrder, isNull);
      expect(b.slotStart, slot);
      expect(b.discountCents, 0);
      expect(b.discountLabel, isNull);
      expect(b.totalCents, b.priceCents);
      expect(b.payment, isNull);
      // Visible in the outlet list for the scan-review plate match.
      final outletList = await repos.staff.outletBookings(
        outletId: DemoStore.outletMenlyn,
      );
      expect(outletList.any((x) => x.id == b.id), isTrue);
    });

    test('rejects a full outlet (capacity = bays) with 409 conflict',
        () async {
      final sandton = store.outletById(DemoStore.outletMenlyn)!;
      store.outlets[store.outlets.indexOf(sandton)] = sandton.copyWith(
        bayCount: 1,
      );
      // Seed already has Thabo's Sparkling Wash in service at 10:00 at Menlyn.
      final thabo = (await repos.staff.searchCustomers('thabo')).single;
      try {
        await repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: thabo.vehicles.last.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-b3',
          ),
        );
        fail('expected conflict');
      } on ApiException catch (e) {
        expect(e.isConflict, isTrue);
        expect(e.message, contains('busy'));
      }
    });

    test('rejects other outlets, foreign vehicles and customer callers',
        () async {
      final thabo = (await repos.staff.searchCustomers('thabo')).single;
      final naledi = (await repos.staff.searchCustomers('naledi')).single;
      // Pieter works at Menlyn only.
      expect(
        () => repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: thabo.vehicles.first.id,
            outletId: DemoStore.outletGlenVillage,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-x1',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'f', true)),
      );
      expect(
        () => repos.staff.createWalkInBooking(
          WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: naledi.vehicles.first.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-x2',
          ),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.isValidation, 'v', true),
        ),
      );
    });
  });

  group('record payment', () {
    late Booking booking;

    setUp(() async {
      final thabo = (await repos.staff.searchCustomers('thabo')).single;
      booking = await repos.staff.createWalkInBooking(
        WalkInBookingInput(
          customerId: thabo.id,
          vehicleId: thabo.vehicles.last.id,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-pay-b',
        ),
      );
    });

    test('amount must match the booking total', () async {
      expect(
        () => repos.staff.recordPayment(
          RecordPaymentInput(
            bookingId: booking.id,
            method: PaymentMethodKind.cash,
            amountCents: booking.totalCents + 100,
            idempotencyKey: 'pay-1',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isValidation, 'validation', true)
              .having((e) => e.message, 'message', contains('total')),
        ),
      );
    });

    test('cash record is successful with a receipt, idempotent, once only',
        () async {
      final changes = <DemoChange>[];
      final sub = store.changes.listen(changes.add);
      final p = await repos.staff.recordPayment(
        RecordPaymentInput(
          bookingId: booking.id,
          method: PaymentMethodKind.cardTerminal,
          reference: 'SLIP 4471',
          amountCents: booking.totalCents,
          idempotencyKey: 'pay-2',
        ),
      );
      expect(p.status, PaymentStatus.successful);
      expect(p.provider, 'pos');
      expect(p.receiptNo, matches(RegExp(r'^RCP-7\d{4}$')));
      expect(p.verifiedAt, isNotNull);
      expect(p.isVerified, isTrue);
      expect(p.providerRef, 'SLIP 4471');
      expect(p.receipt?['method'], 'card_terminal');
      expect(p.pendingSync, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(changes.any((c) => c.table == 'payments'), isTrue);
      await sub.cancel();

      // Booking now carries the payment summary.
      final detail = (await repos.staff.outletBookings(
        outletId: DemoStore.outletMenlyn,
      )).firstWhere((b) => b.id == booking.id);
      expect(detail.isPaid, isTrue);
      expect(detail.payment?.receiptNo, p.receiptNo);

      // Same idempotency key → same payment; new key → already paid.
      final again = await repos.staff.recordPayment(
        RecordPaymentInput(
          bookingId: booking.id,
          method: PaymentMethodKind.cash,
          amountCents: booking.totalCents,
          idempotencyKey: 'pay-2',
        ),
      );
      expect(again.id, p.id);
      expect(
        () => repos.staff.recordPayment(
          RecordPaymentInput(
            bookingId: booking.id,
            method: PaymentMethodKind.cash,
            amountCents: booking.totalCents,
            idempotencyKey: 'pay-3',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'c', true)),
      );
      // Customer got a payment notification.
      expect(
        store.notifications.any(
          (n) =>
              n.recipientId == 'seed_thabo' &&
              n.templateKey == 'payment_successful' &&
              n.body.contains(p.receiptNo!),
        ),
        isTrue,
      );
    });
  });

  group('offline sync batch', () {
    test('booking.create_walk_in and payment.record replay through the store',
        () async {
      final thabo = (await repos.staff.searchCustomers('thabo')).single;
      final input = WalkInBookingInput(
        customerId: thabo.id,
        vehicleId: thabo.vehicles.last.id,
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcExtWash,
        clientOpId: 'op-sync-b',
      );
      final results = store.applySyncBatch([
        {
          'client_op_id': 'op-sync-b',
          'kind': SyncKinds.bookingCreateWalkIn,
          'payload': input.toJson(),
        },
      ]);
      expect(results.single.applied, isTrue);
      final booking = Booking.fromJson(results.single.result!);
      expect(booking.status, BookingStatus.confirmed);

      final pay = store.applySyncBatch([
        {
          'client_op_id': 'op-sync-p',
          'kind': SyncKinds.paymentRecord,
          'payload': RecordPaymentInput(
            bookingId: booking.id,
            method: PaymentMethodKind.cash,
            amountCents: booking.totalCents,
            idempotencyKey: 'op-sync-p',
          ).toJson(),
        },
      ]);
      expect(pay.single.applied, isTrue);
      expect(Payment.fromJson(pay.single.result!).receiptNo, startsWith('RCP-'));

      // Capacity conflict surfaces as a conflict result, not a crash.
      final sandton = store.outletById(DemoStore.outletMenlyn)!;
      store.outlets[store.outlets.indexOf(sandton)] = sandton.copyWith(
        bayCount: 0,
      );
      final clash = store.applySyncBatch([
        {
          'client_op_id': 'op-sync-c',
          'kind': SyncKinds.bookingCreateWalkIn,
          'payload': WalkInBookingInput(
            customerId: thabo.id,
            vehicleId: thabo.vehicles.last.id,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcExtWash,
            clientOpId: 'op-sync-c',
          ).toJson(),
        },
      ]);
      expect(clash.single.status, SyncStatus.conflict);
    });
  });
}
