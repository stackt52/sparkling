import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// Membership plans at the counter (docs/MEMBERSHIPS.md "Staff app"):
/// the customer step's plan pill and Membership tile, **Enrol in a plan**
/// (plan → options → cash) and a walk-in for a covered service whose total
/// is only the add-ons.
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

  Future<void> registerCustomer(WidgetTester tester, String name, String phone) async {
    await tester.tap(find.text('Register new customer'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.enterText(
      find.descendant(
        of: find.byType(PhoneNumberField),
        matching: find.byType(TextField),
      ),
      phone,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, 'Register customer'));
    await settle(tester);
    expect(find.text(name), findsOneWidget);
  }

  group('technician', () {
    final h = DemoHarness()..install();

    testWidgets('customer step shows the plan pill and remaining washes', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      await openWalkIn(tester);
      await search(tester, 'Zanele');
      expect(find.text('Black · 8 washes left'), findsOneWidget);
      await tester.tap(find.text('Zanele Mthembu'));
      await settle(tester);
      expect(find.byKey(const ValueKey('customer-plan-pill')), findsOneWidget);
      expect(find.byKey(const ValueKey('customer-membership')), findsOneWidget);
      expect(find.text('Black member'), findsOneWidget);
      expect(find.textContaining('8 of 10 sparkling wash'), findsOneWidget);
      expect(find.textContaining('Renews '), findsOneWidget);

      // The Membership sheet shows the plan card, allowances and the open
      // renewal invoice → record the payment at the counter.
      await tester.tap(find.byKey(const ValueKey('customer-membership')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sheet-plan-card')), findsOneWidget);
      expect(find.byType(AllowanceRing), findsNWidgets(3));
      expect(find.text('8/10'), findsOneWidget);
      final record = find.byKey(const ValueKey('record-renewal-payment'));
      expect(record, findsOneWidget);
      expect(find.textContaining('R 850.00'), findsWidgets);
      await tester.tap(record);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('renewal-cash')));
      await settle(tester, frames: 8);
      expect(find.textContaining('Black renewed'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-renewal-payment')), findsNothing);
      final zanele = await pumpUntil(
        tester,
        h.repos.staff.customerMembership('seed_zanele'),
      );
      expect(zanele.openInvoice, isNull);
      expect(zanele.allowanceFor('B1')!.used, 0, reason: 'new period');
      await flushIo(tester);
    });

    testWidgets(
      'enrol a new customer in Black (cash) → covered detail at add-on price',
      (tester) async {
        await pumpStaffApp(tester, h.repos);
        await openWalkIn(tester);
        await registerCustomer(tester, 'Bongani Dlamini', '083 555 0100');
        expect(find.text('Walk-in'), findsOneWidget);
        expect(find.byKey(const ValueKey('customer-membership-none')), findsOneWidget);

        // Enrol in a plan: Black, default options B1 + B3, cash.
        await tester.tap(find.byKey(const ValueKey('enrol-cta')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('sheet-enrol')));
        await settle(tester);
        expect(find.text('Enrol Bongani in a plan'), findsOneWidget);
        await scrollTo(tester, find.byKey(const ValueKey('enrol-plan-black')));
        await tester.tap(find.byKey(const ValueKey('enrol-plan-black')));
        await settle(tester);
        await scrollTo(tester, find.byKey(const ValueKey('enrol-option-B1')));
        expect(find.byKey(const ValueKey('enrol-option-B1')), findsOneWidget);
        await scrollTo(tester, find.byKey(const ValueKey('enrol-option-B3')));
        expect(find.byKey(const ValueKey('enrol-option-B3')), findsOneWidget);
        await scrollTo(tester, find.byKey(const ValueKey('enrol-confirm')));
        expect(find.text('Enrol · R 850.00 cash'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('enrol-confirm')));
        await settle(tester, frames: 8);
        expect(find.textContaining('is now a Black member'), findsOneWidget);
        // Back on the membership sheet → plan card; close it.
        expect(find.byKey(const ValueKey('sheet-plan-card')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await settle(tester);
        expect(find.text('Black · 10 washes left'), findsOneWidget);
        expect(find.byKey(const ValueKey('customer-membership')), findsOneWidget);
        // Let the enrolment snack clear so it does not sit over the CTA.
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);

        final customers = await pumpUntil(tester, h.repos.staff.searchCustomers('Bongani'));
        final enrolled = await pumpUntil(
          tester,
          h.repos.staff.customerMembership(customers.single.id),
        );
        expect(enrolled.isActive, isTrue);
        expect(enrolled.planCode, 'black');
        expect(enrolled.selections, {'washes': 'B1', 'detail': 'B3'});
        expect(enrolled.invoices.single.isPaid, isTrue);

        // Vehicle → covered Auto Detail Complete + odour add-on → R 180 total.
        await tester.tap(find.text('Choose vehicle'));
        await settle(tester);
        await tester.tap(find.text('Add manually'));
        await settle(tester);
        await tester.enterText(find.byType(TextFormField).first, 'bd 45 kk gp');
        await tester.tap(find.text('Save vehicle'));
        await settle(tester);
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        await tester.tap(find.text('Choose service'));
        await settle(tester);

        final detail = find.byKey(const ValueKey('offer-AUTO_DETAIL_COMPLETE'));
        await scrollTo(tester, detail);
        expect(
          find.descendant(of: detail, matching: find.text('R 0')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detail, matching: find.textContaining('Included in plan · 1 of 1 left')),
          findsOneWidget,
        );
        await tester.tap(detail);
        await settle(tester);
        await scrollTo(tester, find.byKey(const ValueKey('addon-ADDON_ODOUR')));
        await tester.tap(find.byKey(const ValueKey('addon-ADDON_ODOUR')));
        await settle(tester);
        expect(find.text('R 180'), findsOneWidget); // bottom bar = add-on only
        expect(find.textContaining('Included in plan'), findsWidgets);

        await scrollTo(tester, find.text('Now (walk-in)'));
        await tester.tap(find.text('Review & confirm'));
        await settle(tester);
        expect(find.text('Included in Black · 0 of 1 left'), findsOneWidget);
        expect(find.text('R 180.00'), findsWidgets);
        expect(find.byKey(const ValueKey('nothing-to-pay')), findsNothing);
        await scrollTo(tester, find.textContaining('Confirm walk-in · R 180'));
        await tester.tap(find.textContaining('Confirm walk-in · R 180'));
        await settle(tester, frames: 10);

        expect(find.text('Checked in'), findsOneWidget);
        await scrollTo(tester, find.text('Included in Black · 0 of 1 left'));
        expect(find.text('Included in Black · 0 of 1 left'), findsOneWidget);
        final bookings = await pumpUntil(
          tester,
          h.repos.staff.outletBookings(outletId: DemoStore.outletMenlyn),
        );
        final created = bookings.firstWhere((b) => b.customerId == customers.single.id);
        expect(created.isIncluded, isTrue);
        expect(created.priceCents, 85000);
        expect(created.discountCents, 85000);
        expect(created.addonsCents, 18000);
        expect(created.totalCents, 18000);
        expect(created.isPaid, isTrue);
        final after = await pumpUntil(
          tester,
          h.repos.staff.customerMembership(customers.single.id),
        );
        expect(after.allowanceFor('B3')!.remaining, 0);
        await flushIo(tester);
      },
    );

    testWidgets('a covered Sparkling Wash walk-in has nothing to pay', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      await openWalkIn(tester);
      await search(tester, 'Thabo');
      await tester.tap(find.text('Thabo Nkosi'));
      await settle(tester);
      await tester.tap(find.text('Choose vehicle'));
      await settle(tester);
      await tester.tap(find.text('KL 45 MN GP'));
      await settle(tester);
      await tester.tap(find.text('Choose service'));
      await settle(tester);
      final wash = find.byKey(const ValueKey('offer-SPARKLING_WASH'));
      await scrollTo(tester, wash);
      await tester.tap(wash);
      await settle(tester);
      expect(find.text('R 0'), findsWidgets);
      expect(find.text('Included in plan'), findsWidgets);
      await scrollTo(tester, find.text('Now (walk-in)'));
      await tester.tap(find.text('Review & confirm'));
      await settle(tester);
      expect(find.byKey(const ValueKey('nothing-to-pay')), findsOneWidget);
      expect(find.text('Included in Gold · 2 of 4 left'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      await scrollTo(tester, find.textContaining('Confirm walk-in · R 0'));
      await tester.tap(find.textContaining('Confirm walk-in · R 0'));
      await settle(tester, frames: 10);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.textContaining('Nothing to pay · included in plan'), findsOneWidget);
      final thabo = await pumpUntil(tester, h.repos.staff.customerMembership('seed_thabo'));
      expect(thabo.allowances.single.remaining, 2);
      await flushIo(tester);
    });
  });
}
