import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/widgets/kpi_tile.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

void main() {
  final h = DemoHarness()..install();

  testWidgets('ops screen shows the 4 stat tiles for a supervisor', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);

    await tester.tap(find.text('Ops'));
    await settle(tester);

    expect(find.text("Today's floor"), findsOneWidget);
    expect(find.byType(KpiTile), findsNWidgets(4));
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('blocked'), findsWidgets);
    expect(find.text('Reassign'), findsWidgets);
    await scrollTo(tester, find.text('Team load'));
    expect(find.text('Team load'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('assign sheet reassigns a blocked task', (tester) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    await tester.tap(find.text('Ops'));
    await settle(tester);

    await tester.tap(find.text('Reassign').first);
    await settle(tester, frames: 10);
    expect(find.textContaining('Reassign WO-'), findsOneWidget);
    expect(find.byType(RadioCard), findsWidgets);
    await scrollTo(tester, find.textContaining('actor, time and reason'));
    expect(find.textContaining('actor, time and reason'), findsOneWidget);

    final assign = find.textContaining('Assign to');
    expect(assign, findsOneWidget);
    await tester.tap(assign);
    await settle(tester, frames: 10);
    expect(find.textContaining('assigned to'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('inventory shows the OUT item and the alert banner', (
    tester,
  ) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);

    await tester.tap(find.text('Stock'));
    await settle(tester);

    expect(find.text('Stock'), findsWidgets);
    expect(find.text('OUT'), findsOneWidget);
    expect(find.text('Interior shampoo 5L'), findsOneWidget);
    expect(find.text('LOW'), findsWidgets);
    expect(find.textContaining('below reorder threshold'), findsOneWidget);
    expect(find.text('Request reorder'), findsWidgets);
    await scrollTo(tester, find.textContaining('manager-only'));
    expect(find.textContaining('manager-only'), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('leaderboard renders the podium and badges', (tester) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos);
    await tester.tap(find.text('Rank'));
    await settle(tester);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.byType(PodiumWidget), findsOneWidget);
    expect(find.text('Your badges'), findsOneWidget);
    expect(find.byType(BadgeTile), findsWidgets);
    await tester.tap(find.text('Month'));
    await settle(tester);
    expect(find.byType(PodiumWidget), findsOneWidget);
    await flushIo(tester);
  });

  testWidgets('tablet layout uses a rail and two panes', (tester) async {
    final repos = h.repos;
    await pumpStaffApp(tester, repos, size: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Select a task'), findsOneWidget);
    await tester.tap(find.text('Continue checklist'));
    await settle(tester);
    // Checklist opened in the detail pane, list still visible.
    expect(find.text('My tasks'), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);
    await flushIo(tester);
  });
}
