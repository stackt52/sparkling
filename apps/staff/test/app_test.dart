import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

void main() {
  final h = DemoHarness()..install();

  testWidgets('boots in demo mode as technician and shows My tasks', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);

    expect(find.text('My tasks'), findsOneWidget);
    expect(find.text('WO-${DateTime.now().year}-4821'), findsOneWidget);
    expect(find.text('Continue checklist'), findsOneWidget);
    expect(find.text('4/7 steps'), findsOneWidget);
    expect(find.byType(SyncChip), findsOneWidget);
    expect(find.text('Scan disc'), findsOneWidget);
    // Technicians get Scan instead of Ops in the nav bar.
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Ops'), findsNothing);
    await flushIo(tester);
  });

  testWidgets('Queue segment lists unassigned work and Done lists verified', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);

    await tester.tap(find.textContaining('Queue ·'));
    await settle(tester);
    expect(find.textContaining('WO-'), findsWidgets);
    expect(find.text('Claim & start'), findsWidgets);

    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    expect(find.text('Verified'), findsWidgets);
    await flushIo(tester);
  });

  testWidgets('supervisor sees Ops destination and the sign-in flow works', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    expect(find.text('Ops'), findsWidgets);

    // Sign out → persona picker → back in as technician.
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.ensureVisible(find.text('Switch demo persona'));
    await settle(tester);
    await tester.tap(find.text('Switch demo persona'));
    await settle(tester);
    expect(find.text('Outlet staff sign in'), findsOneWidget);
    await tester.tap(find.text('Pieter van der Merwe'));
    await settle(tester);
    expect(find.text('My tasks'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('light theme renders the task list', (tester) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.tap(find.text('Light'));
    await settle(tester);
    await tester.tap(find.text('Tasks'));
    await settle(tester);
    final theme = Theme.of(tester.element(find.text('My tasks')));
    expect(theme.brightness, Brightness.light);
    expect(find.text('WO-${DateTime.now().year}-4821'), findsOneWidget);
    await flushIo(tester);
  });
}
