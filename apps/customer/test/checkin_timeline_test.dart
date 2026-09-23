import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/tracking/tracking_screen.dart';

import 'helpers.dart';

/// Every confirmed booking has its work order at once (awaiting check-in):
/// the tracking screen keeps the "Waiting for check-in" banner until staff
/// confirm the car on site, then the timeline's "Checked in" step keys off
/// `work_order.checked_in_at`.
void main() {
  late Repositories repos;

  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  testWidgets('"Checked in" appears once the booking is checked in', (
    tester,
  ) async {
    final store = repos.demoStore!;
    final next = store.bookingDetail(DemoStore.bookingNext);
    expect(next.workOrder, isNotNull);
    expect(next.isAwaitingCheckIn, isTrue);

    await pumpScreen(
      tester,
      repos,
      const TrackingScreen(bookingId: DemoStore.bookingNext),
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey('awaiting-checkin-banner')),
      findsOneWidget,
    );
    expect(find.text('Waiting for check-in'), findsOneWidget);
    expect(find.text('Checked in'), findsNothing);

    // Staff confirm the car on the same work order (no duplicate).
    final customer = store.currentUser;
    store.signInAs(DemoPersonas.supervisor);
    final checked = store.checkinBooking(DemoStore.bookingNext, bay: 'Bay 1');
    store.signInAs(customer);
    expect(checked.workOrder!.id, next.workOrder!.id);
    expect(checked.workOrder!.isCheckedIn, isTrue);
    await settle(tester);

    expect(find.byKey(const ValueKey('awaiting-checkin-banner')), findsNothing);
    expect(find.text('Checked in'), findsOneWidget);
    expect(
      find.text(
        '${SparklingDates.hhmm(checked.workOrder!.checkedInAt!)} · completed',
      ),
      findsOneWidget,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  });
}
