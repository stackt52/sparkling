import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/loyalty/loyalty_screen.dart';
import 'package:sparkling_customer/features/vehicles/scan_review_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

void main() {
  late Repositories repos;

  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  testWidgets('boots in demo mode and shows home for Thabo', (tester) async {
    await pumpApp(tester, repos);
    await settle(tester);

    expect(find.text('Thabo'), findsOneWidget);
    expect(find.text('Book a wash'), findsWidgets);
    expect(find.text('Your vehicles'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('booking flow reaches confirmation', (tester) async {
    await pumpApp(tester, repos);
    await settle(tester);

    await tester.tap(find.byType(QuickActionCard).first);
    await settle(tester);
    expect(find.text('Step 1 of 3 · Choose service'), findsOneWidget);

    // Pick the first wash service (cheapest, sorted by price).
    final firstService = find.byType(RadioCard).first;
    await tester.ensureVisible(firstService);
    await tester.tap(firstService);
    await settle(tester, total: const Duration(milliseconds: 500));
    expect(find.textContaining('Earn '), findsOneWidget);

    await tester.tap(find.text('Choose date & time'));
    await settle(tester);
    expect(find.text('Date & time'), findsOneWidget);

    // Find an available slot; move forward a day if today has none
    // (e.g. after closing time).
    Finder available() => find.byWidgetPredicate(
      (w) => w is SlotChip && w.state == SlotState.available,
    );
    for (var day = 1; available().evaluate().isEmpty && day < 6; day++) {
      await tester.tap(find.byType(DateChip).at(day));
      await settle(tester);
    }
    expect(available(), findsWidgets);
    await tester.tap(available().first);
    await settle(tester, total: const Duration(milliseconds: 500));
    expect(find.textContaining('Free cancellation'), findsOneWidget);

    await tester.tap(find.text('Review & pay'));
    await settle(tester);
    expect(find.text('Step 3 of 3 · Payment'), findsOneWidget);
    expect(find.text('Total due'), findsOneWidget);
    expect(find.textContaining('Gold reward'), findsOneWidget);

    await tester.tap(find.textContaining('securely'));
    await settle(tester, total: const Duration(seconds: 4));

    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.textContaining('pts pending completion'), findsOneWidget);
    expect(find.text('Track service'), findsOneWidget);
    // Draft is cleared after a successful booking (UX-009).
    expect(repos.drafts.has('booking_draft'), isFalse);
  });

  testWidgets('scan review renders parsed disc fields', (tester) async {
    final result = Pdf417DiscParser.parse(Pdf417DiscParser.sampleDiscPayload());
    await pumpScreen(tester, repos, ScanReviewScreen(result: result));
    await settle(tester, total: const Duration(seconds: 1));

    expect(find.text('Confirm vehicle'), findsOneWidget);
    expect(find.text('KL 45 MN GP'), findsOneWidget);
    expect(find.text('Toyota'), findsOneWidget);
    expect(find.text('Corolla Cross'), findsOneWidget);
    expect(find.textContaining('AHTFB3CB'), findsOneWidget); // masked VIN
    expect(
      find.textContaining('nothing is committed silently'),
      findsOneWidget,
    );
    // Thabo already owns KL 45 MN GP → duplicate banner (CUS-015).
    expect(find.textContaining('already exists'), findsOneWidget);
    expect(find.text('Save vehicle'), findsOneWidget);
    expect(find.text('Rescan'), findsOneWidget);
  });

  testWidgets('loyalty screen shows balance and tier', (tester) async {
    await pumpScreen(tester, repos, const LoyaltyScreen());
    await settle(tester);

    final account = (await tester.runAsync(() => repos.loyalty.account()))!;
    expect(find.text(Money.formatPoints(account.balance)), findsOneWidget);
    expect(find.text('Points balance'), findsOneWidget);
    expect(find.textContaining('to Platinum'), findsOneWidget);
    expect(find.text('Redeem points'), findsOneWidget);
    // Ledger sits below the fold of the lazy ListView.
    await tester.scrollUntilVisible(
      find.text('Points activity'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester, total: const Duration(milliseconds: 500));
    expect(find.text('Points activity'), findsOneWidget);
  });
}
