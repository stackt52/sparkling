import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/membership/membership_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// Membership plans (docs/MEMBERSHIPS.md) in the customer app: the member
/// view with allowance rings, the non-member plan picker → sandbox payment →
/// activated, and a covered service booking at R 0.
void main() {
  late Repositories repos;

  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  testWidgets('member view renders the plan, allowances and renewal', (
    tester,
  ) async {
    await pumpScreen(tester, repos, const MembershipScreen());
    await settle(tester);

    expect(find.byKey(const ValueKey('member-plan-card')), findsOneWidget);
    expect(find.text('Gold member'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.byType(AllowanceRing), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('Sparkling Washes'), findsOneWidget);
    expect(find.textContaining('3 of 4 left · resets'), findsOneWidget);
    expect(find.textContaining('10% discount on any other'), findsOneWidget);
    expect(find.textContaining('Renews '), findsOneWidget);
    expect(find.textContaining('Last invoice MINV-'), findsOneWidget);
    expect(find.byKey(const ValueKey('change-options')), findsOneWidget);
    expect(find.byKey(const ValueKey('change-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-membership')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-now')), findsNothing);

    // Thabo used a wash this month → changing options is refused (409).
    await tester.tap(find.byKey(const ValueKey('change-options')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('option-G2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-options')));
    await settle(tester);
    expect(find.textContaining('already used'), findsOneWidget);
  });

  testWidgets('non-member picks Platinum, pays in the sandbox and is activated', (
    tester,
  ) async {
    final fresh = await tester.runAsync(bootstrapDemo);
    await tester.runAsync(() => fresh!.membership.cancel(atPeriodEnd: false));
    await pumpApp(tester, fresh!);
    await settle(tester);

    // Home pill now reads Silver; open the Membership tab.
    expect(find.textContaining('Silver'), findsOneWidget);
    await tester.tap(find.text('Membership'));
    await settle(tester);
    expect(find.text('Choose a plan'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-gold')), findsOneWidget);
    expect(find.text('R 295 / month'), findsOneWidget);
    expect(find.textContaining('4 × Sparkling Wash or 8 × Exterior Wash'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('choose-platinum')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Lift the card clear of the bottom navigation bar before tapping.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await settle(tester, total: const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('choose-platinum')));
    await settle(tester);
    expect(find.text('Join Platinum'), findsOneWidget);
    expect(find.byKey(const ValueKey('option-P1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('option-P2')));
    await settle(tester, total: const Duration(milliseconds: 300));
    expect(find.text('Pay R 475.00 securely'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('subscribe-cta')));
    await settle(tester, total: const Duration(seconds: 3));
    expect(find.text('Platinum membership active'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('membership-done-ok')));
    await settle(tester, total: const Duration(seconds: 3));
    // Back on the (still scrolled) membership tab — scroll to the plan card.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, total: const Duration(milliseconds: 500));

    expect(find.text('Platinum member'), findsOneWidget);
    expect(find.text('16/16'), findsOneWidget);
    final me = (await tester.runAsync(() => fresh.membership.me()))!;
    expect(me.isActive, isTrue);
    expect(me.planCode, 'platinum');
    expect(me.selections, {'washes': 'P2'});
    await tester.runAsync(() => fresh.dispose());
  });

  testWidgets('a covered Sparkling Wash books at R 0 with nothing to pay', (
    tester,
  ) async {
    await pumpApp(tester, repos);
    await settle(tester);
    expect(find.text('Gold · 3 washes left'), findsOneWidget);

    await tester.tap(find.byType(QuickActionCard).first);
    await settle(tester);
    final offer = find.byKey(const ValueKey('offer-SPARKLING_WASH'));
    await tester.scrollUntilVisible(offer, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(offer);
    await settle(tester, total: const Duration(milliseconds: 400));
    expect(find.text('Included in your plan · 3 of 4 left'), findsOneWidget);
    // Tap inside the card (its centre can sit under the bottom action bar).
    await tester.tap(find.descendant(of: offer, matching: find.text('R 0')));
    await settle(tester, total: const Duration(milliseconds: 500));
    expect(find.text('R 0'), findsWidgets);
    expect(find.text('Included in your plan'), findsOneWidget);

    await tester.tap(find.text('Choose date & time'));
    await settle(tester);
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

    expect(find.text('Nothing to pay'), findsOneWidget);
    expect(find.textContaining('Included in your plan · 2 of 4 left'), findsOneWidget);
    expect(find.text('R 0.00'), findsWidgets);
    expect(find.text('Payment method'), findsNothing);
    await tester.tap(find.text('Confirm booking · included'));
    await settle(tester, total: const Duration(seconds: 3));

    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.textContaining('included in your plan'), findsOneWidget);
    expect(find.textContaining('Gold plan · 2 washes left'), findsOneWidget);
    final bookings = (await tester.runAsync(() => repos.customer.bookings()))!;
    final created = bookings.firstWhere((b) => b.isIncluded);
    expect(created.totalCents, 0);
    expect(created.status, BookingStatus.confirmed);
    expect(created.discountLabel, 'Included in Gold · 2 of 4 left');
  });
}
