import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/app_settings.dart';
import 'package:sparkling_staff/app/scope.dart';
import 'package:sparkling_staff/app/session.dart';
import 'package:sparkling_staff/app/sync_status.dart';
import 'package:sparkling_staff/features/checklist/handover_sheet.dart';
import 'package:sparkling_staff/features/quote/quote_confirmation_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// Hosts a single widget with the app scopes (no router). Returns the
/// cleanup to run at the end of the test.
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
        child: MaterialApp(theme: SparklingTheme.light(), home: child),
      ),
    ),
  );
  await settle(tester);
  return cleanup;
}

/// Quotation work orders: Zanele's `WO-2026-4819` comes from the accepted
/// (unpaid) `QT-2026-0039`, so the checklist shows "Quote · R 2 850.00 due"
/// with **Record cash payment** (`POST /payments/record { quotation_id }`)
/// and "Paid · RCP-…" once settled; task cards from bookings carry the
/// booking ref; the raise-quote confirmation shows the work-order state.
void main() {
  final h = DemoHarness()..install();
  final year = DateTime.now().year;

  testWidgets('checklist: Quote · R x due → Record cash payment → Paid · RCP', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.textContaining('Queue ·'));
    await settle(tester);
    await scrollTo(tester, find.text('WO-$year-4819'));
    await tester.tap(find.text('WO-$year-4819'));
    await settle(tester, frames: 10);

    final chip = find.byKey(const ValueKey('quote-payment-chip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Quote · R 2 850.00 due')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('awaiting-checkin-chip')), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('quote-payment-card')));
    expect(find.byKey(const ValueKey('quote-payment-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-record-cash')));
    await settle(tester);

    // The hand-over sheet's cash step, targeting the quotation.
    expect(find.byType(RecordCashSheet), findsOneWidget);
    expect(find.byType(CashDueStep), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-cash-due')), findsOneWidget);
    expect(find.text('Quote · R 2 850.00 due'), findsWidgets);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester, frames: 10);
    expect(find.byType(RecordCashSheet), findsNothing);

    final store = (repos.staff as DemoStaffRepository).store;
    final payment = store.payments.firstWhere(
      (p) => p.quotationId == DemoStore.quotationAccepted,
    );
    expect(payment.status.isVerified, isTrue);
    expect(payment.amountCents, 285000);
    expect(payment.bookingId, isNull);
    expect(payment.receipt?['method'], 'cash');
    final quote = store.quotationDetail(DemoStore.quotationAccepted);
    expect(quote.isPaid, isTrue);
    expect(quote.amountDueCents, 0);
    // Payment ≠ check-in: the quote stays accepted until the car arrives.
    expect(quote.status, QuotationStatus.accepted);

    // Back to the header (lazy list): the chip now reads Paid · RCP-….
    await scrollTo(tester, chip);
    expect(
      find.descendant(
        of: chip,
        matching: find.text('Paid · ${payment.receiptNo}'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quote-payment-card')), findsNothing);
    await flushIo(tester);
  });

  testWidgets('hand-over sheet of an unpaid quotation job starts with the '
      'cash step', (tester) async {
    final repos = h.repos;
    final store = (repos.staff as DemoStaffRepository).store;
    final quote = store.quotationDetail(DemoStore.quotationAccepted);
    final cleanup = await pumpHosted(
      tester,
      repos,
      Scaffold(
        body: HandoverSheet(
          workOrderId: DemoStore.woAwaitingCheckIn,
          ref: 'WO-$year-4819',
          quotation: quote,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('handover-quote-chip')), findsOneWidget);
    expect(find.text('Quote · R 2 850.00 due'), findsWidgets);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('handover-record-cash')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('handover-cash-recorded')),
      findsOneWidget,
    );
    expect(find.textContaining('R 2 850.00 cash recorded'), findsOneWidget);
    expect(find.byKey(const ValueKey('handover-otp-field')), findsOneWidget);
    expect(
      store.payments.any((p) => p.quotationId == DemoStore.quotationAccepted),
      isTrue,
    );
    await flushIo(tester);
    await cleanup();
  });

  testWidgets(
    'raise-quote confirmation shows the work order and payment state',
    (tester) async {
      final repos = h.repos;
      final cleanup = await pumpHosted(
        tester,
        repos,
        const QuoteConfirmationScreen(quotationId: DemoStore.quotationAccepted),
      );
      await settle(tester, frames: 8);
      expect(find.text('WO-$year-4819 · awaiting check-in'), findsOneWidget);
      expect(find.text('R 2 850.00 due'), findsOneWidget);
      expect(find.byKey(const ValueKey('quote-work-order-note')), findsNothing);
      await flushIo(tester);
      await cleanup();

      // A quote that is still `quoted` explains what happens on acceptance.
      final cleanup2 = await pumpHosted(
        tester,
        repos,
        const QuoteConfirmationScreen(quotationId: DemoStore.quotationQuoted),
      );
      await settle(tester, frames: 8);
      expect(
        find.byKey(const ValueKey('quote-work-order-note')),
        findsOneWidget,
      );
      expect(
        find.textContaining('created the moment Thabo accepts'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quote-work-order-chip')), findsNothing);
      await flushIo(tester);
      await cleanup2();
    },
  );

  testWidgets('task cards from bookings show the booking ref', (tester) async {
    await pumpStaffApp(tester, h.repos);
    // Pieter's in-service Sparkling Wash is booking SPK-0091 in Bay 2.
    expect(find.text('WO-$year-4821'), findsOneWidget);
    expect(
      find.text('KL 45 MN GP  ·  SPK-$year-0091  ·  Bay 2'),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('Queue ·'));
    await settle(tester);
    // Quotation work orders have no booking ref.
    await scrollTo(tester, find.text('WO-$year-4819'));
    expect(find.text('BW 33 RG GP'), findsOneWidget);
    await flushIo(tester);
  });
}
