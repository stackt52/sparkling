import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/quotes/quote_detail_screen.dart';
import 'package:sparkling_customer/features/quotes/quote_widgets.dart';
import 'package:sparkling_customer/features/quotes/quotes_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// Customer quote detail (CUS-030..034): items, photos, one-time decision.
void main() {
  late Repositories repos;
  late DemoStore store;

  setUpAll(() async {
    SparklingTypography.useGoogleFonts = false;
    final dir = await Directory.systemTemp.createTemp('sparkling_quote_test');
    store = DemoStore(currentUser: DemoPersonas.customer);
    repos = await SparklingCore.bootstrap(
      demo: true,
      clientApp: 'customer',
      hivePath: dir.path,
      demoStore: store,
    );
    await repos.clearLocalState(includeDrafts: true);
  });

  /// Raises a fresh quoted quotation for Thabo as the technician.
  Quotation raiseAsStaff() {
    store.signInAs(DemoPersonas.technician);
    try {
      return store.raiseQuotation(
        StaffQuotationInput(
          customerId: 'seed_thabo',
          vehicleId: DemoStore.vehPolo,
          outletId: DemoStore.outletMenlyn,
          category: 'Dent',
          description: 'Door ding on the passenger door.',
          items: const [
            QuoteItemInput(
              label: 'Passenger door dent',
              category: 'Dent',
              amountCents: 150000,
              serviceId: DemoStore.svcPdr,
            ),
          ],
          validUntil: DateTime.now().add(const Duration(days: 7)),
          clientOpId: SparklingApi.newOpId(),
        ),
      );
    } finally {
      store.signInAs(DemoPersonas.customer);
    }
  }

  /// Scrolls the screen's ListView (lazy) until [finder] is built — down
  /// first, then back up (the decision banner sits at the top).
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final list = find.byType(Scrollable).first;
    if (finder.evaluate().isEmpty || !tester.any(finder)) {
      // Back to the top, then walk down until the row is built.
      await tester.drag(list, const Offset(0, 4000), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 200, scrollable: list);
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Lets Hive writes started inside the FakeAsync zone finish.
  Future<void> flushIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }

  testWidgets('quotes list shows the amount and "Action needed" for quoted', (
    tester,
  ) async {
    await pumpScreen(tester, repos, const QuotesScreen());
    await settle(tester);
    expect(find.text('Action needed'), findsOneWidget);
    expect(find.textContaining('R 3 850.00'), findsOneWidget);
    expect(find.textContaining('QT-'), findsOneWidget); // Thabo's only quote
    await flushIo(tester);
  });

  testWidgets('detail shows items, photos and note; accept once → locked', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      repos,
      const QuoteDetailScreen(quotationId: DemoStore.quotationQuoted),
    );
    await settle(tester);

    expect(find.text('Your decision is needed'), findsOneWidget);
    expect(find.textContaining('expires in 14 days'), findsWidgets);
    expect(find.text('Bumper scuff repair & respray'), findsOneWidget);
    expect(find.text('Blend to quarter panel'), findsOneWidget);
    expect(find.byType(CategoryChip), findsNWidgets(2));
    expect(find.text('R 3 200.00'), findsOneWidget);
    expect(find.text('R 3 850.00'), findsOneWidget);
    expect(find.text('Assessed by Sipho Ndlovu'), findsOneWidget);
    await scrollTo(tester, find.text('Damage photos'));
    expect(find.byType(QuotePhotoTile), findsNWidgets(2));
    expect(find.byType(AuthedImage), findsNWidgets(2));
    expect(
      find.text('Parts on hand · 2 working days once the car is in.'),
      findsOneWidget,
    );
    await scrollTo(tester, find.byKey(const ValueKey('quote-accept')));
    expect(find.byKey(const ValueKey('quote-download-pdf')), findsOneWidget);

    // Accept → confirm sheet → locked state.
    await tester.tap(find.byKey(const ValueKey('quote-accept')));
    await settle(tester, total: const Duration(milliseconds: 600));
    expect(find.text('Accept this quote?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-accept-confirm')));
    await settle(tester);
    expect(find.textContaining('accepted.'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('quote-decided-banner')));
    expect(find.byKey(const ValueKey('quote-decided-banner')), findsOneWidget);
    expect(find.textContaining('Accepted on '), findsOneWidget);
    expect(find.textContaining(' in app'), findsWidgets);
    expect(find.byKey(const ValueKey('quote-accept')), findsNothing);
    expect(find.byKey(const ValueKey('quote-decline')), findsNothing);
    expect(find.text('Accepted'), findsOneWidget); // status chip

    final fresh = (await tester.runAsync(
      () => repos.customer.quotation(DemoStore.quotationQuoted),
    ))!;
    expect(fresh.status, QuotationStatus.accepted);
    expect(fresh.decisionSource, QuoteDecisionSource.app);
    await flushIo(tester);
  });

  testWidgets('second decision path → 409 → "Already decided" + refresh', (
    tester,
  ) async {
    final q = raiseAsStaff();
    await pumpScreen(tester, repos, QuoteDetailScreen(quotationId: q.id));
    await settle(tester);
    expect(find.text('Passenger door dent'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('quote-accept')));
    expect(find.byKey(const ValueKey('quote-accept')), findsOneWidget);

    // Meanwhile the quote is declined elsewhere (public link / other device).
    store.decideQuotation(q.id, accept: false, note: 'Went elsewhere');

    await tester.tap(find.byKey(const ValueKey('quote-accept')));
    await settle(tester, total: const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('quote-accept-confirm')));
    await settle(tester);

    expect(find.textContaining('Already decided'), findsWidgets);
    await scrollTo(tester, find.byKey(const ValueKey('quote-decided-banner')));
    expect(find.byKey(const ValueKey('quote-decided-banner')), findsOneWidget);
    expect(find.textContaining('Declined on '), findsOneWidget);
    expect(find.byKey(const ValueKey('quote-accept')), findsNothing);
    await scrollTo(tester, find.text('Went elsewhere'));
    expect(find.text('Went elsewhere'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('accepted quote: booked in awaiting the car, amount due → paid', (
    tester,
  ) async {
    final q = raiseAsStaff();
    // Accepted (in app) → the work order exists at once, awaiting the car.
    final accepted = store.decideQuotation(q.id, accept: true);
    expect(accepted.status, QuotationStatus.accepted);
    expect(accepted.workOrder?.awaitingCheckIn, isTrue);
    await pumpScreen(tester, repos, QuoteDetailScreen(quotationId: q.id));
    await settle(tester);
    expect(find.byKey(const ValueKey('quote-decided-banner')), findsOneWidget);
    expect(find.textContaining('Booked in as WO-'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('quote-work-order')));
    expect(
      find.text('Booked in · ${accepted.workOrder!.ref} awaiting your car'),
      findsOneWidget,
    );
    await scrollTo(tester, find.byKey(const ValueKey('quote-payment')));
    expect(find.text('R 1 500.00 due at the counter'), findsOneWidget);
    expect(find.textContaining('Paid ·'), findsNothing);
    await flushIo(tester);

    // Staff record the cash at the counter → "Paid · cash · RCP-…".
    store.signInAs(DemoPersonas.technician);
    final payment = store.recordPayment(
      RecordPaymentInput(
        quotationId: q.id,
        method: PaymentMethodKind.cash,
        amountCents: 150000,
        idempotencyKey: SparklingApi.newOpId(),
      ),
    );
    store.signInAs(DemoPersonas.customer);
    // A fresh screen (new key → new state) reloads the quote.
    await pumpScreen(
      tester,
      repos,
      QuoteDetailScreen(key: const ValueKey('paid'), quotationId: q.id),
    );
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('quote-payment')));
    expect(find.text('Paid · cash · ${payment.receiptNo}'), findsOneWidget);
    expect(find.textContaining('due at the counter'), findsNothing);
    // Still "Accepted" — the check-in is what converts it.
    expect(find.text('Accepted'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('decline asks for an optional note', (tester) async {
    final q = raiseAsStaff();
    await pumpScreen(tester, repos, QuoteDetailScreen(quotationId: q.id));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('quote-decline')));
    await tester.tap(find.byKey(const ValueKey('quote-decline')));
    await settle(tester, total: const Duration(milliseconds: 600));
    expect(find.text('Decline this quote?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('quote-decline-note')),
      'Too expensive',
    );
    await tester.tap(find.byKey(const ValueKey('quote-decline-confirm')));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('quote-decided-banner')));
    expect(find.textContaining('Declined on '), findsOneWidget);
    await scrollTo(tester, find.text('Too expensive'));
    expect(find.text('Too expensive'), findsOneWidget);
    final fresh = (await tester.runAsync(() => repos.customer.quotation(q.id)))!;
    expect(fresh.status, QuotationStatus.declined);
    expect(fresh.decisionNote, 'Too expensive');
    await flushIo(tester);
  });
}
