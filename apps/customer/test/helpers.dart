import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/app/app.dart';
import 'package:sparkling_customer/app/app_scope.dart';
import 'package:sparkling_customer/app/app_settings.dart';
import 'package:sparkling_customer/app/session.dart';
import 'package:sparkling_customer/features/booking/booking_flow.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Demo repositories backed by a temporary Hive directory ([store] swaps in
/// a custom [DemoStore], e.g. with a feature flag turned off).
Future<Repositories> bootstrapDemo({DemoStore? store}) async {
  SparklingTypography.useGoogleFonts = false;
  final dir = await Directory.systemTemp.createTemp('sparkling_customer_test');
  final repos = await SparklingCore.bootstrap(
    demo: true,
    clientApp: 'customer',
    hivePath: dir.path,
    demoStore: store,
  );
  // Hive boxes are shared across tests in one process — start clean.
  await repos.clearLocalState(includeDrafts: true);
  return repos;
}

/// Phone-sized test surface (iPhone 16 logical size).
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps real time in small steps so demo repository delays (120–700 ms) and
/// finite animations complete without waiting on infinite spinners.
Future<void> settle(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 2),
}) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> pumpApp(WidgetTester tester, Repositories repos) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(CustomerApp(repositories: repos));
  await settle(tester, total: const Duration(seconds: 1));
}

/// Hosts a single screen with the app scopes it needs (no router).
Future<void> pumpScreen(
  WidgetTester tester,
  Repositories repos,
  Widget screen,
) async {
  usePhoneSurface(tester);
  final session = SessionController(repos);
  final settings = AppSettings(repos.cache);
  final flow = BookingFlowController(repos);
  addTearDown(() {
    session.dispose();
    settings.dispose();
    flow.dispose();
  });
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: AppScope(
        session: session,
        settings: settings,
        bookingFlow: flow,
        child: MaterialApp(theme: SparklingTheme.light(), home: screen),
      ),
    ),
  );
  await settle(tester, total: const Duration(seconds: 1));
}

/// The outermost vertical scrollable on screen (home list, flow steps, …).
Finder verticalScrollable() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

/// Scrolls [verticalScrollable] until [finder] is on screen. Use before
/// asserting on or tapping anything that may sit below the fold — the home
/// hero and banners are built from the time-relative demo seed, so their
/// height (and everything beneath them) shifts with the clock.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: verticalScrollable(),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

/// Taps the first home quick action ("Book a wash") and waits for step 1 of
/// the booking flow. Brings the card into view first: depending on the time
/// of day it lands behind the bottom overlay and a blind tap misses.
Future<void> openBookingFlow(WidgetTester tester) async {
  final quickAction = find.byType(QuickActionCard).first;
  await tester.ensureVisible(quickAction);
  await settle(tester);
  await tester.tap(quickAction);
  await settle(tester);
  expect(find.text('Step 1 of 3 · Choose service'), findsOneWidget);
}
