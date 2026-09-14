import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/booking/booking_widgets.dart';
import 'package:sparkling_customer/features/booking/service_select_screen.dart';
import 'package:sparkling_customer/features/vehicles/scan_review_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// Catalogue pricing model in the booking flow: grouped offers priced for the
/// vehicle size, add-ons, by-quote routing and the size selector.
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

  Future<void> openBooking(WidgetTester tester) async {
    await pumpApp(tester, repos);
    await settle(tester);
    await tester.tap(find.byType(QuickActionCard).first);
    await settle(tester);
    expect(find.text('Step 1 of 3 · Choose service'), findsOneWidget);
  }

  testWidgets(
    'large vehicle → Glen Village → interior detailing + odour add-on → R 880',
    (tester) async {
      await openBooking(tester);
      // Thabo's first vehicle is the Corolla Cross (large).
      expect(find.text('KL 45 MN GP'), findsOneWidget);
      expect(find.textContaining('large vehicle'), findsOneWidget);

      // Switch to Glen Village.
      await tester.tap(find.byType(OutletSelectorCard));
      await settle(tester);
      await tester.tap(find.text('Sparkling Elite Centre Glen Village'));
      await settle(tester);
      expect(find.text('Sparkling Elite Centre Glen Village'), findsOneWidget);

      // Groups render as section headers.
      expect(find.text('Car Wash Options'), findsOneWidget);
      await scrollTo(tester, find.text('Combinations'));
      expect(find.text('Combinations'), findsOneWidget);

      // Auto detailing interior for a large vehicle: from R 700.
      final interior = find.byKey(const ValueKey('offer-AUTO_DETAIL_INTERIOR'));
      await scrollTo(tester, interior);
      expect(
        find.descendant(of: interior, matching: find.text('R 700')),
        findsOneWidget,
      );
      await tester.tap(interior);
      await settle(tester, total: const Duration(milliseconds: 500));
      expect(find.textContaining('Earn '), findsOneWidget);

      // Add-ons of the Combinations group appear; tick odour removal.
      await scrollTo(tester, find.text('Add-ons'));
      expect(find.text('Add-ons'), findsOneWidget);
      final odour = find.byKey(const ValueKey('addon-ADDON_ODOUR'));
      await scrollTo(tester, odour);
      expect(
        find.descendant(of: odour, matching: find.text('+ R 180')),
        findsOneWidget,
      );
      await tester.tap(odour);
      await settle(tester, total: const Duration(milliseconds: 500));
      // Bottom bar: R 880 less Thabo's Gold −10 % (other services).
      expect(find.text('R 792'), findsOneWidget);
      expect(find.text('Gold −10%'), findsWidgets);

      await tester.tap(find.text('Choose date & time'));
      await settle(tester);
      expect(find.text('R 792'), findsOneWidget);
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

      // Payment summary: base, add-on, subtotal before the Gold discount.
      expect(find.text('Step 3 of 3 · Payment'), findsOneWidget);
      expect(find.text('R 700.00'), findsOneWidget);
      expect(find.text('Add to any Combo: Odour Removal'), findsOneWidget);
      expect(find.text('R 180.00'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('R 880.00'), findsOneWidget);
      expect(find.textContaining('Gold −10%'), findsOneWidget);
      expect(find.text('R 792.00'), findsOneWidget); // total after −10 %
      expect(find.textContaining('VAT'), findsNothing);

      await tester.tap(find.textContaining('securely'));
      await settle(tester, total: const Duration(seconds: 4));
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.textContaining('Add-on · Add to any Combo'), findsOneWidget);

      final bookings = (await tester.runAsync(() => repos.customer.bookings()))!;
      final created = bookings.firstWhere((b) => b.addons.isNotEmpty);
      expect(created.vehicleSize, VehicleSize.large);
      expect(created.priceCents, 70000);
      expect(created.addonsCents, 18000);
      expect(created.totalCents, 79200);
    },
  );

  testWidgets('by-quote card opens the quote request with the service', (
    tester,
  ) async {
    await openBooking(tester);
    final tar = find.byKey(const ValueKey('offer-TAR_REMOVAL'));
    await scrollTo(tester, tar);
    expect(
      find.descendant(of: tar, matching: find.text('By quote')),
      findsOneWidget,
    );
    await tester.tap(tar);
    await settle(tester);
    expect(find.text('Repair quote'), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-preselected-service')), findsOneWidget);
    expect(find.text('Tar Removal | Excess Mud'), findsOneWidget);
    expect(find.textContaining('Quote for Tar Removal'), findsOneWidget);
  });

  testWidgets('auto body offers show excl. VAT and the total adds 15 %', (
    tester,
  ) async {
    await openBooking(tester);
    final headlight = find.byKey(const ValueKey('offer-HEADLIGHT_RENEWAL'));
    await scrollTo(tester, headlight);
    expect(
      find.descendant(of: headlight, matching: find.text('excl. VAT')),
      findsOneWidget,
    );
    await tester.tap(headlight);
    await settle(tester, total: const Duration(milliseconds: 500));
    // R 400 less Gold −10 % (other services) + 15 % VAT in the bottom bar.
    expect(find.text('Gold −10%'), findsWidgets);
    expect(find.text('R 414'), findsOneWidget);
    expect(find.byType(ServiceOfferCard), findsWidgets);
  });

  testWidgets('scan review derives the size from the disc description', (
    tester,
  ) async {
    final result = Pdf417DiscParser.parse(Pdf417DiscParser.sampleDiscPayload());
    await pumpScreen(tester, repos, ScanReviewScreen(result: result));
    await settle(tester, total: const Duration(seconds: 1));
    await scrollTo(tester, find.text('Vehicle size'));
    expect(find.text('Vehicle size'), findsOneWidget);
    // "Sedan (closed top)" → small, prefilled from the disc.
    expect(find.textContaining('from your licence disc'), findsOneWidget);
    expect(find.textContaining('Hatch, sedan'), findsOneWidget);
    await tester.tap(find.text('Large'));
    await tester.pump();
    expect(find.textContaining('SUV, bakkie'), findsOneWidget);
  });
}
