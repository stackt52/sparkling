import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/features/quote/items_step.dart';
import 'package:sparkling_staff/features/quote/raise_quote_controller.dart';

import 'test_harness.dart';

/// Catalogue pricing model in the staff flows: grouped offers priced for the
/// customer's vehicle size, add-ons, by-quote → raise quote, VAT-inclusive
/// prefill on the quote item sheet.
void main() {
  Future<void> openWalkIn(WidgetTester tester) async {
    await tester.tap(find.text('Walk-in booking'));
    await settle(tester);
    expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
  }

  /// Walk-in flow up to step 3 for Sipho's Hilux (a large bakkie).
  Future<void> toServiceStep(WidgetTester tester, DemoHarness h) async {
    await pumpStaffApp(tester, h.repos);
    await openWalkIn(tester);
    await search(tester, 'Sipho');
    await tester.tap(find.text('Sipho Dlamini'));
    await settle(tester);
    await tester.tap(find.text('Choose vehicle'));
    await settle(tester);
    expect(find.textContaining('Large vehicle'), findsOneWidget);
    await tester.tap(find.text('DN 07 KX GP'));
    await settle(tester);
    await tester.tap(find.text('Choose service'));
    await settle(tester);
    expect(find.text('Step 3 of 4 · Service & time'), findsOneWidget);
    expect(find.text('Sparkling Auto Care Centre Menlyn'), findsOneWidget);
    expect(find.textContaining('DN 07 KX GP · Large'), findsOneWidget);
  }

  group('walk-in catalogue', () {
    final h = DemoHarness()..install();

    testWidgets(
      'large vehicle → interior detailing + odour add-on → total with add-on',
      (tester) async {
        await toServiceStep(tester, h);

        // Groups render as headers; Combinations carries the add-on.
        expect(find.text('Car Wash Options'), findsOneWidget);
        await scrollTo(tester, find.text('Combinations'));
        final interior = find.byKey(
          const ValueKey('offer-AUTO_DETAIL_INTERIOR'),
        );
        await scrollTo(tester, interior);
        // Menlyn interior detailing, large: from R 700.
        expect(
          find.descendant(of: interior, matching: find.text('R 700')),
          findsOneWidget,
        );
        await tester.tap(interior);
        await settle(tester);
        expect(find.textContaining('Earn '), findsOneWidget);

        await scrollTo(tester, find.text('Add-ons'));
        final odour = find.byKey(const ValueKey('addon-ADDON_ODOUR'));
        await scrollTo(tester, odour);
        expect(
          find.descendant(of: odour, matching: find.text('+ R 180')),
          findsOneWidget,
        );
        await tester.tap(odour);
        await settle(tester);
        // Sipho is Platinum (P1: Sparkling Wash) — the plan_services discount
        // does not reach interior detailing, so the estimate is the full R 880.
        expect(find.textContaining('Platinum −'), findsNothing);
        expect(find.textContaining('1 add-on'), findsOneWidget);
        expect(find.text('R 880'), findsOneWidget);

        await scrollTo(tester, find.text('Now (walk-in)'));
        await tester.tap(find.text('Review & confirm'));
        await settle(tester);

        // Step 4 — summary lists the add-on and subtotal before discount.
        expect(find.text('Step 4 of 4 · Payment & confirm'), findsOneWidget);
        expect(find.text('R 700.00'), findsOneWidget);
        expect(find.text('Add to any Combo: Odour Removal'), findsOneWidget);
        expect(find.text('R 180.00'), findsOneWidget);
        expect(find.text('Subtotal'), findsOneWidget);
        expect(find.text('R 880.00'), findsWidgets); // subtotal + total
        final confirm = find.textContaining('Confirm walk-in · R 880');
        expect(confirm, findsOneWidget);
        await tester.tap(confirm);
        await settle(tester, frames: 10);

        expect(find.text('Checked in'), findsOneWidget);
        await scrollTo(tester, find.textContaining('Add-on · Add to any Combo'));
        expect(find.textContaining('Add-on · Add to any Combo'), findsOneWidget);

        final bookings = await pumpUntil(
          tester,
          h.repos.staff.outletBookings(outletId: DemoStore.outletMenlyn),
        );
        final created = bookings.firstWhere((b) => b.addons.isNotEmpty);
        expect(created.vehicleSize, VehicleSize.large);
        expect(created.priceCents, 70000);
        expect(created.addonsCents, 18000);
        expect(created.discountCents, 0);
        expect(created.totalCents, 88000);
        expect(created.membership?.planCode, 'platinum');
        expect(created.isPaid, isTrue);
        await flushIo(tester);
      },
    );

    testWidgets('auto body offer adds 15 % VAT to the total', (tester) async {
      await toServiceStep(tester, h);
      final headlight = find.byKey(const ValueKey('offer-HEADLIGHT_RENEWAL'));
      await scrollTo(tester, headlight);
      expect(
        find.descendant(of: headlight, matching: find.text('excl. VAT')),
        findsOneWidget,
      );
      await tester.tap(headlight);
      await settle(tester);
      // R 400 + 15 % VAT = R 460 (no plan discount on auto body for P1).
      expect(find.textContaining('Incl. VAT'), findsOneWidget);
      expect(find.text('R 460'), findsOneWidget);
      await flushIo(tester);
    });

    testWidgets('by-quote offer jumps to raise quote with customer + vehicle', (
      tester,
    ) async {
      await toServiceStep(tester, h);
      final tar = find.byKey(const ValueKey('offer-TAR_REMOVAL'));
      await scrollTo(tester, tar);
      expect(
        find.descendant(of: tar, matching: find.text('By quote')),
        findsOneWidget,
      );
      await scrollTo(tester, find.byKey(const ValueKey('raise-quote-TAR_REMOVAL')));
      await tester.tap(find.byKey(const ValueKey('raise-quote-TAR_REMOVAL')));
      await settle(tester);
      // Customer and vehicle carried over → lands on the items step.
      expect(find.text('Raise quote'), findsOneWidget);
      expect(find.text('Step 3 of 4 · What needs attention'), findsOneWidget);
      expect(find.text('DN 07 KX GP'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('quote-description')))
            .controller!
            .text,
        startsWith('Quote for Tar Removal'),
      );
      await flushIo(tester);
    });
  });

  group('raise quote catalogue', () {
    final h = DemoHarness()..install();

    testWidgets('item sheet lists auto-body offers excl. VAT and prefills ×1.15', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      await tester.tap(find.byKey(const ValueKey('fab-raise-quote')));
      await settle(tester);
      await search(tester, 'Thabo');
      await tester.tap(find.text('Thabo Nkosi'));
      await settle(tester);
      await tester.tap(find.text('Choose vehicle'));
      await settle(tester);
      await tester.tap(find.text('CJ 12 PZ GP'));
      await settle(tester);
      await tester.tap(find.text('What needs attention'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('quote-add-item')));
      await settle(tester);
      // Bumper → BUMPER_SCUFF linked with its incl-VAT amount prefilled.
      await tester.tap(find.byKey(const ValueKey('quote-cat-Bumper')));
      await tester.pump();
      expect(
        find.textContaining('Linked · From R 2 150 excl. VAT'),
        findsOneWidget,
      );
      final amount = tester.widget<TextFormField>(
        find.byKey(const ValueKey('quote-item-amount')),
      );
      expect(amount.controller!.text, '2472.50'); // 215000 × 1.15

      // Pick another service from the sheet: headlight renewal R 400 → 460.
      await tester.tap(find.byKey(const ValueKey('quote-item-service')));
      await settle(tester);
      final headlight = find.byKey(
        const ValueKey('quote-service-HEADLIGHT_RENEWAL'),
      );
      await scrollTo(
        tester,
        headlight,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      expect(find.text('From R 400 excl. VAT'), findsOneWidget);
      await tester.ensureVisible(headlight);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('From R 400 excl. VAT'));
      await settle(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('quote-item-amount')))
            .controller!
            .text,
        '460',
      );
      await tester.tap(find.byKey(const ValueKey('quote-item-save')));
      await settle(tester);
      expect(find.text('R 460.00'), findsWidgets);
      expect(find.byType(ItemsStep), findsOneWidget);
      expect(RaiseQuoteController.maxPhotos, 10);
      await flushIo(tester);
    });
  });
}
