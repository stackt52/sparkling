import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/features/checklist/handover_sheet.dart';

import 'test_harness.dart';

/// Payment at collection with a method choice: Thabo's cash-on-collection
/// `WO-2026-4820` (SPK-2026-0098, R 81) is settled at the hand-over by card
/// terminal (reference kept on the receipt) or by EFT (reference required),
/// then the collection OTP (`73104`) releases the keys.
void main() {
  final h = DemoHarness()..install();
  final ref = 'WO-${DateTime.now().year}-4820';

  Future<void> openSheet(WidgetTester tester, Repositories repos) async {
    await pumpStaffApp(tester, repos);
    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
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
    expect(find.byKey(const ValueKey('handover-cash-due')), findsOneWidget);
  }

  testWidgets('card terminal at hand-over → payment with reference → OTP', (
    tester,
  ) async {
    final repos = h.repos;
    await openSheet(tester, repos);

    // Cash is the default; switch to the card terminal and add the slip no.
    expect(find.text('Record cash payment · R 81.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('handover-payment-method-card')));
    await tester.pump();
    expect(find.text('Record card terminal payment · R 81.00'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('handover-payment-reference')),
      '048213',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);

    expect(find.byKey(const ValueKey('handover-cash-due')), findsNothing);
    expect(
      find.textContaining('R 81.00 card terminal recorded'),
      findsOneWidget,
    );
    final store = (repos.staff as DemoStaffRepository).store;
    final payment = store.payments.firstWhere(
      (p) => p.bookingId == DemoStore.bookingReady,
    );
    expect(payment.status.isVerified, isTrue);
    expect(payment.method, 'card_terminal');
    expect(payment.providerRef, '048213');
    expect(payment.stage, PaymentStage.collection);
    expect(payment.receipt?['stage'], 'collection');

    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '73104',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-released')), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('EFT needs its reference before the payment is recorded', (
    tester,
  ) async {
    final repos = h.repos;
    await openSheet(tester, repos);
    await tester.tap(find.byKey(const ValueKey('handover-payment-method-eft')));
    await tester.pump();
    expect(find.text('Record eft payment · R 81.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);
    // Refused client-side: the step is still there and nothing was recorded.
    expect(find.byKey(const ValueKey('handover-cash-due')), findsOneWidget);
    expect(find.text('Enter the EFT reference first.'), findsOneWidget);
    final store = (repos.staff as DemoStaffRepository).store;
    expect(
      store.payments.any((p) => p.bookingId == DemoStore.bookingReady),
      isFalse,
    );

    await tester.enterText(
      find.byKey(const ValueKey('handover-payment-reference')),
      'FNB-77120',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-cash-due')), findsNothing);
    expect(find.textContaining('R 81.00 eft recorded'), findsOneWidget);
    final payment = store.payments.firstWhere(
      (p) => p.bookingId == DemoStore.bookingReady,
    );
    expect(payment.method, 'eft');
    expect(payment.providerRef, 'FNB-77120');
    await flushIo(tester);
  });
}
