import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/bookings/booking_detail_screen.dart';
import 'package:sparkling_customer/features/bookings/pay_now_sheet.dart';

import 'helpers.dart';

/// "Pay now" on an unpaid booking once the car is in: Thabo's cash-on-
/// collection SPK-2026-0098 (R 81) is ready for collection and unpaid, so the
/// detail offers **Pay now · R 81.00**; paying through the saved card
/// (sandbox provider) marks the booking paid and clears the cash-due line.
void main() {
  late Repositories repos;
  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  Finder vertical() => find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 160, scrollable: vertical());
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('booking detail: Pay now → saved card → paid', (tester) async {
    final store = repos.demoStore!;
    final before = store.bookingDetail(DemoStore.bookingReady);
    expect(before.canPayNow, isTrue);
    expect(before.isCashDue, isTrue);

    await pumpScreen(
      tester,
      repos,
      const BookingDetailScreen(bookingId: DemoStore.bookingReady),
    );
    await settle(tester);
    final payNow = find.byKey(const ValueKey('pay-now'));
    await scrollTo(tester, payNow);
    expect(find.text('Pay now · R 81.00'), findsOneWidget);

    await tester.tap(payNow);
    await settle(tester);
    expect(find.byType(PayNowSheet), findsOneWidget);
    expect(find.text('Pay R 81.00'), findsOneWidget);
    // The default saved card is preselected; pay.
    await tester.tap(find.byKey(const ValueKey('pay-now-confirm')));
    await settle(tester, total: const Duration(seconds: 3));

    expect(find.byType(PayNowSheet), findsNothing);
    expect(find.textContaining('Paid R 81.00'), findsOneWidget);
    final after = store.bookingDetail(DemoStore.bookingReady);
    expect(after.isPaid, isTrue);
    expect(after.canPayNow, isFalse);
    expect(after.isCashDue, isFalse);
    final payment = store.payments.firstWhere(
      (p) => p.bookingId == DemoStore.bookingReady,
    );
    expect(payment.status.isVerified, isTrue);
    expect(payment.stage, PaymentStage.collection);
    await settle(tester);
    expect(find.byKey(const ValueKey('pay-now')), findsNothing);
    expect(find.byKey(const ValueKey('cash-due-line')), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  });
}
