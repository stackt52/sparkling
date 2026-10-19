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
    // Quick actions live behind the "+" FAB menu.
    expect(find.byKey(const ValueKey('fab-menu')), findsOneWidget);
    expect(find.text('Scan disc'), findsNothing);
    await openFabMenu(tester);
    expect(find.text('Scan disc'), findsOneWidget);
    expect(find.text('Walk-in booking'), findsOneWidget);
    expect(find.text('Raise quote'), findsOneWidget);
    // The scrim closes it again.
    await tester.tap(find.byKey(const ValueKey('fab-menu-scrim')));
    await settle(tester);
    expect(find.text('Walk-in booking'), findsNothing);
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
    // The unassigned card sits below the fold once the cards above it carry
    // their payment chips; the list builds lazily.
    await scrollTo(tester, find.text('Claim & start'));
    expect(find.text('Claim & start'), findsWidgets);

    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    expect(find.text('Verified'), findsWidgets);
    await flushIo(tester);
  });

  testWidgets('Queue and Done default to today with a period picker', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    final pills = find.byKey(const ValueKey('task-period-pills'));
    // Mine has no period filter.
    expect(pills, findsNothing);

    int queueCount() {
      final label = tester
          .widgetList<Text>(find.textContaining('Queue ·'))
          .first
          .data!;
      return int.parse(label.split('· ').last);
    }

    await tester.tap(find.textContaining('Queue ·'));
    await settle(tester);
    expect(pills, findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('WO-'), findsWidgets);
    final today = queueCount();

    // Wider periods never show less than today.
    await tester.tap(find.text('All'));
    await settle(tester);
    expect(queueCount(), greaterThanOrEqualTo(today));

    await tester.tap(find.textContaining('Done ·'));
    await settle(tester);
    expect(pills, findsOneWidget);
    await tester.tap(find.text('Today'));
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

  testWidgets('supervisor Mine tab lists work awaiting sign-off', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    final ref = 'WO-${DateTime.now().year}-4821';
    // Pieter's in-progress task is not Johan's until the timeline reaches
    // the supervisor step.
    expect(find.text(ref), findsNothing);
    expect(find.textContaining('Nothing needs you'), findsOneWidget);

    const wo = '30000000-0000-4000-8000-000000000001';
    for (final (key, value) in [('windows', true), ('tyre_pressure', 2.1)]) {
      await pumpUntil(
        tester,
        repos.staff.submitStep(
          wo,
          key,
          StepResultInput(
            status: StepStatus.done,
            clientOpId: SparklingApi.newOpId(),
            value: value,
          ),
        ),
      );
    }
    await settle(tester);

    expect(find.text(ref), findsOneWidget);
    expect(find.textContaining('Awaiting sign-off'), findsOneWidget);
    expect(find.text('Review & sign off'), findsOneWidget);
    expect(find.text('Continue checklist'), findsNothing);

    await tester.tap(find.text('Review & sign off'));
    await settle(tester);
    await scrollTo(tester, find.text('Verify & sign off'));
    expect(find.text('Verify & sign off'), findsOneWidget);
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
