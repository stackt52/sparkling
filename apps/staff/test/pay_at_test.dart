import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'test_harness.dart';

/// Pay at check-in / on collection (`bookings.pay_at`) in the staff app: the
/// walk-in flow offers "Pay on collection" (a counter booking settled at the
/// hand-over, nothing recorded now) and the task card names a booking the
/// customer wants to settle when dropping the car off.
void main() {
  Future<void> openWalkIn(WidgetTester tester) async {
    await openFabMenu(tester);
    await tester.tap(find.text('Walk-in booking'));
    await settle(tester);
    expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
  }

  group('walk-in "Pay on collection"', () {
    final h = DemoHarness()..install();

    testWidgets('creates a counter booking with nothing recorded', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      await openWalkIn(tester);
      await search(tester, 'Thabo');
      await tester.tap(find.text('Thabo Nkosi'));
      await settle(tester);
      await tester.tap(find.text('Choose vehicle'));
      await settle(tester);
      await tester.tap(find.text('CJ 12 PZ GP'));
      await settle(tester);
      await tester.tap(find.text('Choose service'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('offer-EXT_WASH')));
      await settle(tester);
      await tester.tap(find.text('Review & confirm'));
      await settle(tester);
      expect(find.text('Step 4 of 4 · Payment & confirm'), findsOneWidget);

      await scrollTo(tester, find.text('Pay on collection'));
      expect(find.text('Pay on collection'), findsOneWidget);
      expect(
        find.textContaining('settled at the counter before the keys'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pay on collection'));
      await settle(tester);
      final confirm = find.textContaining('Confirm walk-in · R');
      await scrollTo(tester, confirm);
      await tester.tap(confirm);
      await settle(tester, frames: 10);

      expect(find.text('Checked in'), findsOneWidget);
      expect(
        find.textContaining('pay on collection at the counter'),
        findsOneWidget,
      );
      expect(find.textContaining('RCP-'), findsNothing);

      final store = h.repos.demoStore!;
      final b = store.bookings.last;
      expect(b.paymentMethod, PaymentChoice.cash);
      expect(b.payAt, PaymentStage.collection);
      expect(b.status, BookingStatus.inService);
      expect(store.payments.where((p) => p.bookingId == b.id), isEmpty);
      final wo = store.workOrders.firstWhere((w) => w.bookingId == b.id);
      expect(store.workOrderDetail(wo.id).workOrder.isCashDue, isTrue);
      await flushIo(tester);
    });
  });

  group('task card', () {
    final h = DemoHarness(
      storeBuilder: () {
        final store = DemoStore(currentUser: DemoPersonas.technician);
        // Pieter's in-progress booking becomes an unpaid "pay at check-in" one.
        final i = store.bookings.indexWhere(
          (b) => b.id == DemoStore.bookingInService,
        );
        store.bookings[i] = Booking.fromJson({
          ...store.bookings[i].toJson(),
          'payment_method': 'cash',
          'pay_at': 'checkin',
        });
        store.payments.removeWhere(
          (p) => p.bookingId == DemoStore.bookingInService,
        );
        return store;
      },
    )..install();

    testWidgets(
      'names the moment the customer chose: "Pay at check-in · R x due"',
      (tester) async {
        await pumpStaffApp(tester, h.repos);
        expect(find.textContaining('Pay at check-in · R'), findsOneWidget);
        expect(find.textContaining('Cash on collection'), findsNothing);
        await flushIo(tester);
      },
    );
  });
}
