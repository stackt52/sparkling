import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/router.dart';
import 'package:sparkling_staff/features/scanner/scan_review_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// Walk-in booking flow (STF-010/012) on the demo repositories.
void main() {
  Future<void> openWalkIn(WidgetTester tester) async {
    await tester.tap(find.text('Walk-in booking'));
    await settle(tester);
    expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    // 300 ms debounce + demo latency.
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
  }

  group('technician', () {
    final h = DemoHarness()..install();

    testWidgets('searching "Thabo" finds him with tier and plates', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      await openWalkIn(tester);

      await search(tester, 'Thabo');
      expect(find.text('Thabo Nkosi'), findsOneWidget);
      expect(find.text('Gold · 3 washes left'), findsOneWidget);
      expect(find.text('KL 45 MN GP'), findsOneWidget);
      expect(find.text('CJ 12 PZ GP'), findsOneWidget);

      // Selecting shows the summary card and unlocks the vehicle step.
      await tester.tap(find.text('Thabo Nkosi'));
      await settle(tester);
      expect(find.text('Change'), findsOneWidget);
      await tester.tap(find.text('Choose vehicle'));
      await settle(tester);
      expect(find.text('Step 2 of 4 · Vehicle'), findsOneWidget);
      expect(find.text('Disc verified'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
      await flushIo(tester);
    });

    testWidgets(
      'register → add vehicle → Exterior wash now → cash → confirmation with receipt',
      (tester) async {
        await pumpStaffApp(tester, h.repos);
        await openWalkIn(tester);

        // Step 1 — register a new customer.
        await tester.tap(find.text('Register new customer'));
        await settle(tester);
        expect(find.text('Register customer'), findsWidgets);
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'Lindiwe Zulu');
        await tester.enterText(fields.at(1), '072 555 0199');
        await tester.pump();
        expect(find.text('Saved as +27725550199'), findsOneWidget);
        await tester.tap(find.widgetWithText(PillButton, 'Register customer'));
        await settle(tester);
        expect(find.text('Lindiwe Zulu'), findsOneWidget);
        expect(find.text('Walk-in'), findsOneWidget); // no loyalty account yet
        await tester.tap(find.text('Choose vehicle'));
        await settle(tester);

        // Step 2 — no vehicles on file → add manually.
        expect(find.text('No vehicles on file'), findsOneWidget);
        await tester.tap(find.text('Add manually'));
        await settle(tester);
        await tester.enterText(find.byType(TextFormField).first, 'nd 123 456');
        await tester.tap(find.text('Save vehicle'));
        await settle(tester);
        expect(find.text('ND 123 456'), findsWidgets);
        // Let the "added" snack clear so it does not sit over the CTA.
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        await tester.tap(find.text('Choose service'));
        await settle(tester);

        // Step 3 — outlet card is locked to Menlyn; pick Exterior wash only, now.
        expect(find.text('Step 3 of 4 · Service & time'), findsOneWidget);
        expect(find.text('Sparkling Auto Care Centre Menlyn'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('offer-EXT_WASH')));
        await settle(tester);
        expect(find.textContaining('Earn '), findsOneWidget);
        await scrollTo(tester, find.text('Now (walk-in)'));
        expect(find.text('Now (walk-in)'), findsOneWidget);
        await tester.tap(find.text('Review & confirm'));
        await settle(tester);

        // Step 4 — cash is the default, check-in on; confirm.
        expect(find.text('Step 4 of 4 · Payment & confirm'), findsOneWidget);
        expect(find.text('Total due'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        await scrollTo(tester, find.text('Check in now'));
        expect(find.text('Check in now'), findsOneWidget);
        final confirm = find.textContaining('Confirm walk-in · R');
        expect(confirm, findsOneWidget);
        await tester.tap(confirm);
        await settle(tester, frames: 10);

        // Confirmation: checked in, receipt number, checklist link.
        expect(find.text('Checked in'), findsOneWidget);
        expect(find.textContaining('RCP-7'), findsOneWidget);
        expect(find.textContaining('SPK-'), findsOneWidget);
        await scrollTo(tester, find.textContaining('WO-'));
        expect(find.textContaining('WO-'), findsOneWidget);
        expect(find.byType(ConfettiBlob), findsOneWidget);
        expect(find.text('Open checklist'), findsOneWidget);
        expect(find.text('New walk-in'), findsOneWidget);

        // The booking landed in the store as a walk-in with a POS payment.
        final store = h.repos.staff;
        final outletBookings = await pumpUntil(
          tester,
          store.outletBookings(outletId: DemoStore.outletMenlyn),
        );
        final created = outletBookings.firstWhere(
          (b) => b.vehicle?.registrationNo == 'ND 123 456',
        );
        expect(created.status, BookingStatus.inService);
        expect(created.isPaid, isTrue);
        expect(created.customerId, startsWith('walkin_'));

        // Draft is cleared after success.
        expect(h.repos.drafts.has('walk_in_draft'), isFalse);

        // "Open checklist" lands on the new work order.
        await tester.tap(find.text('Open checklist'));
        await settle(tester, frames: 8);
        expect(find.textContaining(created.workOrder!.ref), findsWidgets);
        await flushIo(tester);
      },
    );

    testWidgets('scan review offers "Create walk-in booking" for an unknown plate', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      final router = GoRouter.of(tester.element(find.text('My tasks')));
      router.push(
        Routes.scanReview,
        extra: const ScanReviewArgs(
          result: DiscScanResult(registrationNo: 'ZZ99ZZGP', rawHash: 'h'),
          manual: true,
        ),
      );
      await settle(tester, frames: 8);
      expect(find.text('No booking for ZZ 99 ZZ GP'), findsOneWidget);
      expect(find.textContaining('not available'), findsNothing);
      await tester.tap(find.text('Create walk-in booking'));
      await settle(tester, frames: 8);

      // The scanned plate seeds the customer search.
      expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('No customer matches “ZZ 99 ZZ GP”'), findsOneWidget);
      expect(find.text('Register new customer'), findsOneWidget);
      await flushIo(tester);
    });
  });

  group('capacity', () {
    final h = DemoHarness(
      storeBuilder: () {
        final store = DemoStore(currentUser: DemoPersonas.technician);
        final i = store.outlets.indexWhere(
          (o) => o.id == DemoStore.outletMenlyn,
        );
        store.outlets[i] = store.outlets[i].copyWith(bayCount: 0);
        return store;
      },
    )..install();

    testWidgets('no bay free → conflict message, flow returns to slot picker', (
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
      // Exterior Wash is a Gold plan service (G2) — Thabo chose G1, so no
      // discount applies; the bottom bar shows the plain total.
      expect(find.text('Total'), findsOneWidget);
      await tester.tap(find.text('Review & confirm'));
      await settle(tester);
      await tester.tap(find.textContaining('Confirm walk-in · R'));
      await settle(tester, frames: 10);

      expect(find.textContaining('bays are busy'), findsOneWidget);
      // Back on step 3 with "Pick a slot" pre-selected and no confirmation.
      expect(find.text('Step 3 of 4 · Service & time'), findsOneWidget);
      await scrollTo(tester, find.textContaining('Available slots'), delta: 400);
      expect(find.textContaining('Available slots'), findsOneWidget);
      expect(find.text('Checked in'), findsNothing);
      await flushIo(tester);
    });
  });

  group('supervisor', () {
    final h = DemoHarness()..install();

    testWidgets('ops screen quick action opens the walk-in flow', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos, persona: DemoPersonas.supervisor);
      await tester.tap(find.text('Ops'));
      await settle(tester);
      await scrollTo(tester, find.byKey(const ValueKey('ops-walk-in')));
      await tester.tap(find.byKey(const ValueKey('ops-walk-in')));
      await settle(tester);
      expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
      await flushIo(tester);
    });
  });
}
