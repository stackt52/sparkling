import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/app_settings.dart';
import 'package:sparkling_staff/app/scope.dart';
import 'package:sparkling_staff/app/session.dart';
import 'package:sparkling_staff/app/sync_status.dart';
import 'package:sparkling_staff/features/checklist/handover_sheet.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// Hosts a single widget with the app scopes (no router). Returns the
/// cleanup to run at the end of the test (the session's idle timer must be
/// cancelled before the framework checks for pending timers).
Future<Future<void> Function()> pumpHosted(
  WidgetTester tester,
  Repositories repos,
  Widget child,
) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettings(repos.drafts);
  final session = SessionController(repos);
  final sync = SyncStatusController(repos);
  Future<void> cleanup() async {
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
    session.dispose();
    settings.dispose();
  }
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: AppScope(
        settings: settings,
        session: session,
        sync: sync,
        child: MaterialApp(
          theme: SparklingTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await settle(tester);
  return cleanup;
}

/// Cash on collection at the hand-over: Thabo's `WO-2026-4820`
/// (SPK-2026-0098, R 81) is cash on collection and unpaid, so the sheet
/// first records the cash (`POST /payments/record`) and only then accepts
/// the collection OTP (`73104`).
void main() {
  final h = DemoHarness()..install();
  final ref = 'WO-${DateTime.now().year}-4820';

  testWidgets('Done list chip → hand-over: record cash → OTP accepted', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);

    // The task card flags the cash booking.
    await scrollTo(tester, find.text(ref));
    expect(
      find.text('Cash on collection · R 81.00 due'),
      findsOneWidget,
    );
    final card = find.ancestor(
      of: find.text(ref),
      matching: find.byWidgetPredicate((w) => w.key is ValueKey<String>),
    );
    await tester.tap(
      find.descendant(of: card.first, matching: find.text('Hand over vehicle')),
    );
    await settle(tester);

    // Cash step first: no OTP field yet.
    expect(find.byType(HandoverSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-cash-due')), findsOneWidget);
    expect(find.text('Cash due · R 81.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsNothing);
    expect(find.text('Verify & release keys'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-cash-due')), findsNothing);
    expect(
      find.byKey(const ValueKey('handover-cash-recorded')),
      findsOneWidget,
    );
    expect(find.textContaining('R 81.00 cash recorded'), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsOneWidget);

    final store = (repos.staff as DemoStaffRepository).store;
    final payment = store.payments.firstWhere(
      (p) => p.bookingId == DemoStore.bookingReady,
    );
    expect(payment.status.isVerified, isTrue);
    expect(payment.amountCents, 8100);
    expect(payment.receipt?['method'], 'cash');

    // Now the OTP releases the keys.
    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '73104',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-released')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(
      store.workOrders.firstWhere((w) => w.id == DemoStore.woReady).isCollected,
      isTrue,
    );
    // Card chip flips to paid.
    await scrollTo(tester, find.text(ref));
    expect(find.text('Cash on collection · paid'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('verify without booking context: 409 payment_due shows the '
      'cash step', (tester) async {
    final repos = h.repos;
    // Host the sheet directly, as a caller without the `booking` expansion.
    final cleanup = await pumpHosted(
      tester,
      repos,
      const HandoverSheet(workOrderId: DemoStore.woReady, ref: 'WO-4820'),
    );
    expect(find.byKey(const ValueKey('handover-otp-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '73104',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);

    expect(find.byKey(const ValueKey('handover-cash-due')), findsOneWidget);
    expect(find.text('Cash due · R 81.00'), findsOneWidget);
    expect(find.textContaining('is due before the keys are released'), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-record-cash')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('handover-otp-field')),
      '73104',
    );
    await tester.pump();
    await tester.tap(find.text('Verify & release keys'));
    await settle(tester);
    expect(find.byKey(const ValueKey('handover-released')), findsOneWidget);
    await flushIo(tester);
    await cleanup();
  });

  testWidgets('checklist header and hand-over card show the cash due', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    await tester.tap(find.text('Tasks'));
    await settle(tester);
    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    await scrollTo(tester, find.text(ref));
    await tester.tap(find.text(ref));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('cash-on-collection-chip')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('handover-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('handover-cash-due-line')),
      findsOneWidget,
    );
    expect(find.textContaining('Cash due · R 81.00'), findsOneWidget);
    await flushIo(tester);
  });
}
