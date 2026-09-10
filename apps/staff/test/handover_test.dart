import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/features/checklist/handover_sheet.dart';

import 'test_harness.dart';

void main() {
  final h = DemoHarness()..install();

  testWidgets('Done list → hand-over sheet: wrong OTP, then keys released', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);

    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    // Both verified work orders wait for collection.
    expect(find.text('Hand over vehicle'), findsNWidgets(2));

    final ref = 'WO-${DateTime.now().year}-4822';
    await scrollTo(tester, find.text(ref));
    final card = find.ancestor(
      of: find.text(ref),
      matching: find.byWidgetPredicate((w) => w.key is ValueKey<String>),
    );
    await tester.tap(
      find.descendant(of: card.first, matching: find.text('Hand over vehicle')),
    );
    await settle(tester);

    expect(find.byType(HandoverSheet), findsOneWidget);
    expect(find.text('Verify & release keys'), findsOneWidget);
    expect(find.text('Resend OTP to customer'), findsOneWidget);
    expect(find.textContaining(ref), findsWidgets);

    // Wrong code → error banner with attempts left, field cleared.
    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '11111',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-error')), findsOneWidget);
    expect(find.textContaining('4 attempts left'), findsWidgets);

    // Correct code (seeded 48213) → released state.
    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '48213',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-released')), findsOneWidget);
    expect(find.textContaining('Keys released · collected at'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.byType(HandoverSheet), findsNothing);
    // The card now shows the release time instead of the CTA.
    expect(find.text('Hand over vehicle'), findsOneWidget);
    expect(find.textContaining('Keys released'), findsWidgets);
    expect(
      (h.repos.staff as DemoStaffRepository).store.workOrders
          .firstWhere((w) => w.id == DemoStore.woVerified)
          .isCollected,
      isTrue,
    );
    await flushIo(tester);
  });

  testWidgets('five wrong codes lock the sheet; resend re-enables it', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    await tester.tap(find.text('Hand over vehicle').first);
    await settle(tester);

    for (var i = 0; i < 5; i++) {
      await tester.enterText(
        find.byKey(const ValueKey('handover-otp-field')),
        '00000',
      );
      await tester.pump();
      await tester.tap(find.text('Verify & release keys'));
      await settle(tester);
    }
    expect(find.text('Too many attempts'), findsOneWidget);
    expect(find.textContaining('send the customer a new OTP'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('handover-resend')));
    await settle(tester);
    expect(find.textContaining('resend in'), findsOneWidget);
    expect(find.text('Too many attempts'), findsNothing);
    // Cooldown counts down (60 s client side).
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Resend OTP to customer'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    await flushIo(tester);
  });

  testWidgets('checklist of a verified work order offers the hand-over card', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    await tester.tap(find.text('Tasks'));
    await settle(tester);
    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    await tester.tap(find.text('WO-${DateTime.now().year}-4822'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-card')), findsOneWidget);
    expect(find.text('Awaiting collection'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('ops "Done today" lists work awaiting collection', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    await tester.tap(find.text('Ops'));
    await settle(tester);
    await scrollTo(tester, find.text('Done today'));
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('2 awaiting collection'), findsOneWidget);
    await scrollTo(tester, find.text('Hand over').first);
    expect(find.text('Hand over'), findsNWidgets(2));
    await flushIo(tester);
  });
}
