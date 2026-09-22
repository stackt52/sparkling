import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/bookings/booking_detail_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// Cash on collection at "Review & pay": offered only while the
/// `cash_on_collection` flag is on, confirms the booking without a payment
/// intent and shows the amber "Cash due on collection" line afterwards.
void main() {
  // One demo bootstrap per test process (Hive boxes are shared).
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

  /// Home → book → Menlyn Exterior Wash → first free slot → "Review & pay".
  Future<void> toReviewAndPay(WidgetTester tester, Repositories repos) async {
    await pumpApp(tester, repos);
    await settle(tester);
    await tester.tap(find.byType(QuickActionCard).first);
    await settle(tester);
    expect(find.text('Step 1 of 3 · Choose service'), findsOneWidget);
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

  group('flag on', () {
    testWidgets('cash option → confirmed booking with cash due', (
      tester,
    ) async {
      await toReviewAndPay(tester, repos);
      final cash = find.byKey(const ValueKey('pay-cash'));
      await scrollTo(tester, cash);
      expect(find.text('Cash on collection'), findsOneWidget);
      expect(
        find.textContaining('in cash at the counter when you collect'),
        findsOneWidget,
      );
      // Saved card is selected by default.
      expect(find.textContaining('securely'), findsOneWidget);

      await tester.tap(cash);
      await settle(tester, total: const Duration(milliseconds: 500));
      expect(find.text('Confirm booking · pay on collection'), findsOneWidget);
      expect(find.textContaining('securely'), findsNothing);

      await tester.tap(find.text('Confirm booking · pay on collection'));
      await settle(tester, total: const Duration(seconds: 3));
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.byKey(const ValueKey('cash-due-row')), findsOneWidget);
      expect(
        find.textContaining('Cash due on collection · R '),
        findsOneWidget,
      );
      expect(find.text('Receipt'), findsNothing);

      final bookings = (await tester.runAsync(() => repos.customer.bookings()))!;
      final created = bookings.firstWhere(
        (b) => b.paymentMethod == PaymentChoice.cash && b.isUpcoming,
      );
      expect(created.status, BookingStatus.confirmed);
      expect(created.payment, isNull);
      expect(created.isCashDue, isTrue);
    });

    testWidgets('409 cash_disabled deselects cash and hides the option', (
      tester,
    ) async {
      await toReviewAndPay(tester, repos);
      final cash = find.byKey(const ValueKey('pay-cash'));
      await scrollTo(tester, cash);
      await tester.tap(cash);
      await settle(tester, total: const Duration(milliseconds: 500));
      // The flag is switched off after the config was fetched.
      repos.demoStore!.featureFlags['cash_on_collection'] = false;
      await tester.tap(find.text('Confirm booking · pay on collection'));
      await settle(tester, total: const Duration(seconds: 2));
      expect(
        find.textContaining('Cash on collection is not available'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay-cash')), findsNothing);
      expect(find.textContaining('securely'), findsOneWidget);
      expect(find.text('Booking confirmed'), findsNothing);
      repos.demoStore!.featureFlags['cash_on_collection'] = true;
    });

    testWidgets('booking detail shows the amber cash-due line', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        repos,
        const BookingDetailScreen(bookingId: DemoStore.bookingReady),
      );
      await settle(tester);
      await scrollTo(tester, find.byKey(const ValueKey('cash-due-line')));
      expect(find.text('Cash due on collection · R 81.00'), findsOneWidget);
      expect(find.textContaining('Payment verified'), findsNothing);
    });

    testWidgets('booking detail shows "Paid · cash" once staff recorded it', (
      tester,
    ) async {
      final store = repos.demoStore!;
      final customer = store.currentUser;
      store.signInAs(DemoPersonas.technician);
      store.recordPayment(
        RecordPaymentInput(
          bookingId: DemoStore.bookingReady,
          method: PaymentMethodKind.cash,
          amountCents: 8100,
          idempotencyKey: 'test-cash-paid-0098',
        ),
      );
      store.signInAs(customer);
      await pumpScreen(
        tester,
        repos,
        const BookingDetailScreen(bookingId: DemoStore.bookingReady),
      );
      await settle(tester);
      await scrollTo(tester, find.textContaining('Paid · cash'));
      expect(find.textContaining('Paid · cash'), findsOneWidget);
      expect(find.byKey(const ValueKey('cash-due-line')), findsNothing);
    });
  });

  group('flag off', () {
    // Same demo store with the flag switched off — the demo config
    // repository reads it on every call.
    setUpAll(() {
      repos.demoStore!.featureFlags['cash_on_collection'] = false;
    });
    tearDownAll(() {
      repos.demoStore!.featureFlags['cash_on_collection'] = true;
    });

    testWidgets('the cash option is absent', (tester) async {
      expect(
        (await tester.runAsync(() => repos.config.config()))!
            .flags
            .cashOnCollection,
        isFalse,
      );
      await toReviewAndPay(tester, repos);
      await scrollTo(tester, find.text('Add card or instant EFT'));
      expect(find.byKey(const ValueKey('pay-cash')), findsNothing);
      expect(find.text('Cash on collection'), findsNothing);
      expect(find.textContaining('securely'), findsOneWidget);
    });
  });
}
