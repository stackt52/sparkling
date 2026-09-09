import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/features/checklist/checklist_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

void main() {
  final h = DemoHarness()..install();

  testWidgets('checklist shows 4/7 and completing a step advances', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);

    await tester.tap(find.text('Continue checklist'));
    await settle(tester);

    expect(find.byType(ChecklistView), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);
    expect(find.text('Windows inside & out'), findsOneWidget);
    expect(find.text('REQUIRED'), findsOneWidget);
    await scrollTo(tester, find.text('Supervisor verification'));
    expect(find.text('Supervisor verification'), findsOneWidget);
    await scrollTo(tester, find.textContaining('Works offline'));
    expect(find.textContaining('Works offline'), findsOneWidget);

    // Complete the current (confirm) step.
    await scrollTo(tester, find.text('Complete step'));
    await tester.tap(find.text('Complete step'));
    await settle(tester);

    await scrollTo(tester, find.text('5/7'));
    expect(find.text('5/7'), findsOneWidget);
    // The numeric step is now current, with its mono input.
    await scrollTo(tester, find.text('Tyre pressure check'));
    expect(find.text('Tyre pressure check'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Numeric validation: out of range is rejected client-side.
    await tester.enterText(find.byType(TextField), '9');
    await scrollTo(tester, find.text('Complete step'));
    await tester.tap(find.text('Complete step'));
    await settle(tester);
    expect(find.textContaining('Must be at most'), findsOneWidget);
    expect(find.text('6/7'), findsNothing);

    await tester.enterText(find.byType(TextField), '2.2');
    await scrollTo(tester, find.text('Complete step'));
    await tester.tap(find.text('Complete step'));
    await settle(tester);
    await scrollTo(tester, find.text('6/7'));
    expect(find.text('6/7'), findsOneWidget);

    // Technician cannot verify; sees "Complete task" instead.
    await scrollTo(tester, find.text('Complete task'));
    expect(find.text('Complete task'), findsOneWidget);
    expect(find.text('Verify & sign off'), findsNothing);

    await tester.tap(find.text('Complete task'));
    await settle(tester);
    await scrollTo(tester, find.text('Task completed'));
    expect(find.text('Task completed'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('supervisor can verify once required steps pass', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    // Finish the technician steps directly through the repository.
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

    await tester.tap(find.textContaining('Queue ·'));
    await settle(tester);
    await tester.tap(find.text('Continue checklist').first);
    await settle(tester);

    expect(find.text('6/7'), findsOneWidget);
    await scrollTo(tester, find.text('Verify & sign off'));
    expect(find.text('Verify & sign off'), findsOneWidget);
    await tester.tap(find.text('Verify & sign off'));
    await settle(tester, frames: 10);
    await scrollTo(tester, find.text('7/7'));
    expect(find.text('7/7'), findsOneWidget);
    expect(find.textContaining('Signed off'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('mark blocked records a reason and blocks the task', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.text('Continue checklist'));
    await settle(tester);

    await scrollTo(tester, find.text('Mark blocked'));
    await tester.tap(find.text('Mark blocked'));
    await settle(tester);
    await tester.tap(find.text('Equipment fault'));
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, 'Mark blocked').last);
    await settle(tester, frames: 10);

    await scrollTo(tester, find.text('Blocked'));
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Equipment fault'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await flushIo(tester);
  });
}
