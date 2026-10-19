import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/bookings/booking_detail_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// "Pay at check-in" at "Review & pay": beside "Cash on collection" the
/// customer can choose to settle the booking at the counter when dropping the
/// car off. The booking is confirmed without a payment intent with
/// `payment_method: cash` + `pay_at: checkin`, and the confirmation / detail
/// screens say so.
void main() {
  late Repositories repos;
  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  /// Home → book → Menlyn Exterior Wash → first free slot → "Review & pay".
  Future<void> toReviewAndPay(WidgetTester tester, Repositories repos) async {
    await pumpApp(tester, repos);
    await settle(tester);
    await openBookingFlow(tester);
    final offer = find.byKey(const ValueKey('offer-EXT_WASH'));
    await scrollTo(tester, offer);
    await tester.tap(offer);
    await settle(tester, total: const Duration(milliseconds: 500));
    await tester.tap(find.text('Choose date & time'));
    await settle(tester);
    Finder available() => find.byWidgetPredicate(
      (w) => w is SlotChip && w.state == SlotState.available,
    );
    for (var day = 1; available().evaluate().isEmpty && day < 6; day++) {
      await tester.tap(find.byType(DateChip).at(day));
      await settle(tester);
    }
    await tester.tap(available().first);
    await settle(tester, total: const Duration(milliseconds: 500));
    await tester.tap(find.text('Review & pay'));
    await settle(tester);
    expect(find.text('Step 3 of 3 · Payment'), findsOneWidget);
  }

  testWidgets(
    'pay at check-in → confirmed booking, pay_at checkin, amber line',
    (tester) async {
      await toReviewAndPay(tester, repos);
      final checkin = find.byKey(const ValueKey('pay-checkin'));
      await scrollTo(tester, checkin);
      expect(find.text('Pay at check-in'), findsOneWidget);
      expect(find.text('Cash on collection'), findsOneWidget);
      expect(
        find.textContaining('at the counter when you drop your car off'),
        findsOneWidget,
      );

      await tester.tap(checkin);
      await settle(tester, total: const Duration(milliseconds: 500));
      expect(find.text('Confirm booking · pay at check-in'), findsOneWidget);
      expect(find.textContaining('securely'), findsNothing);

      // Switching to collection and back keeps a single selection.
      final cash = find.byKey(const ValueKey('pay-cash'));
      await scrollTo(tester, cash);
      await tester.tap(cash);
      await settle(tester, total: const Duration(milliseconds: 500));
      expect(find.text('Confirm booking · pay on collection'), findsOneWidget);
      await scrollTo(tester, checkin);
      await tester.tap(checkin);
      await settle(tester, total: const Duration(milliseconds: 500));
      expect(find.text('Confirm booking · pay at check-in'), findsOneWidget);

      await tester.tap(find.text('Confirm booking · pay at check-in'));
      await settle(tester, total: const Duration(seconds: 3));
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.byKey(const ValueKey('cash-due-row')), findsOneWidget);
      expect(find.textContaining('Pay at check-in · R '), findsOneWidget);
      expect(find.text('Receipt'), findsNothing);

      final bookings = (await tester.runAsync(
        () => repos.customer.bookings(),
      ))!;
      final created = bookings.firstWhere(
        (b) => b.payAt == PaymentStage.checkin && b.isUpcoming,
      );
      expect(created.status, BookingStatus.confirmed);
      expect(created.paymentMethod, PaymentChoice.cash);
      expect(created.paysAtCheckIn, isTrue);
      expect(created.payment, isNull);
      expect(created.isCashDue, isTrue);

      // Booking detail shows the check-in wording on the amber line.
      await pumpScreen(
        tester,
        repos,
        BookingDetailScreen(bookingId: created.id, initial: created),
      );
      await settle(tester, total: const Duration(seconds: 1));
      await scrollTo(tester, find.byKey(const ValueKey('cash-due-line')));
      expect(find.textContaining('Pay at check-in · R '), findsOneWidget);
    },
  );
}
