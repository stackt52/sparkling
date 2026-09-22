import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// Work orders can only be assigned once the vehicle is checked in: the ops
/// "Assignment queue" flags them, the assign sheet disables **Assign** and
/// offers **Confirm check-in**, and the task card / checklist header show
/// the state.
void main() {
  final year = DateTime.now().year;
  final assignBtn = find.byKey(const ValueKey('assign-submit'));
  final confirmBtn = find.byKey(const ValueKey('confirm-check-in'));
  final queueChip = find.byKey(
    ValueKey('awaiting-checkin-${DemoStore.taskAwaitingCheckIn}'),
  );
  final queueAssign = find.byKey(
    ValueKey('queue-assign-${DemoStore.taskAwaitingCheckIn}'),
  );

  Future<void> openOpsQueue(WidgetTester tester, Repositories repos) async {
    await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
    await tester.tap(find.text('Ops'));
    await settle(tester);
    await scrollTo(tester, find.text('Assignment queue'));
    expect(find.text('Assignment queue'), findsOneWidget);
    expect(find.text('1 awaiting check-in'), findsOneWidget);
    await scrollTo(tester, queueAssign);
    expect(queueChip, findsOneWidget);
    expect(find.text('Awaiting check-in'), findsOneWidget);
  }

  group('manual assignment (auto_assignment off)', () {
    final h = DemoHarness(
      storeBuilder: () =>
          DemoStore(currentUser: DemoPersonas.supervisor)
            ..featureFlags['auto_assignment'] = false,
    )..install();

    testWidgets('ops queue: awaiting chip → confirm check-in → assign works', (
      tester,
    ) async {
      await openOpsQueue(tester, h.repos);

      await tester.tap(queueAssign);
      await settle(tester, frames: 10);
      expect(find.text('Assign WO-$year-4819'), findsOneWidget);
      expect(find.byKey(const ValueKey('awaiting-checkin-banner')), findsOneWidget);
      expect(confirmBtn, findsOneWidget);
      // Assignment is locked until the vehicle is on site.
      expect(tester.widget<PillButton>(assignBtn).onPressed, isNull);
      expect(find.textContaining('Assign to'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('check-in-bay')), 'Body 2');
      await tester.tap(confirmBtn);
      await settle(tester, frames: 10);

      expect(confirmBtn, findsNothing);
      final banner = find.byKey(const ValueKey('checked-in-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.textContaining('Checked in ')),
        findsOneWidget,
      );
      expect(find.textContaining('auto-assigned'), findsNothing);
      expect(tester.widget<PillButton>(assignBtn).onPressed, isNotNull);
      expect(find.textContaining('Assign to'), findsOneWidget);
      final detail = await pumpUntil(
        tester,
        h.repos.staff.workOrder(DemoStore.woAwaitingCheckIn),
      );
      expect(detail.workOrder.isCheckedIn, isTrue);
      expect(detail.workOrder.bay, 'Body 2');
      expect(detail.workOrder.assigneeId, isNull);

      await tester.tap(assignBtn);
      await settle(tester, frames: 10);
      expect(find.textContaining('WO-$year-4819 assigned to'), findsOneWidget);
      // Assigned → it leaves the unassigned queue.
      expect(queueChip, findsNothing);
      final after = await pumpUntil(
        tester,
        h.repos.staff.workOrder(DemoStore.woAwaitingCheckIn),
      );
      expect(after.workOrder.assigneeId, isNotNull);
      expect(after.workOrder.status, WorkStatus.assigned);
      await flushIo(tester);
    });

    testWidgets('a stale assign (not checked in) shows the server message', (
      tester,
    ) async {
      final repos = h.repos;
      await pumpStaffApp(tester, repos, persona: DemoPersonas.supervisor);
      final queue = await pumpUntil(
        tester,
        repos.staff.tasks(
          scope: TaskScope.queue,
          outletId: DemoStore.outletMenlyn,
        ),
      );
      final task = queue.firstWhere(
        (t) => t.id == DemoStore.taskAwaitingCheckIn,
      );
      try {
        await pumpUntil(
          tester,
          repos.staff.assignTask(task, assigneeId: 'seed_pieter'),
        );
        fail('expected 409');
      } on ApiException catch (e) {
        expect(e.isNotCheckedIn, isTrue);
        expect(e.message, contains('has not been checked in yet'));
      }
      await flushIo(tester);
    });
  });

  group('auto-assignment on (demo default)', () {
    final h = DemoHarness()..install();

    testWidgets('confirm check-in auto-assigns and the sheet says so', (
      tester,
    ) async {
      await openOpsQueue(tester, h.repos);
      await tester.tap(queueAssign);
      await settle(tester, frames: 10);
      await tester.tap(confirmBtn);
      await settle(tester, frames: 10);
      expect(find.textContaining('Auto-assigned to'), findsOneWidget);
      expect(find.textContaining('currently '), findsOneWidget);
      // Cancel keeps the auto-assignment; the queue row is gone.
      await tester.tap(find.text('Cancel'));
      await settle(tester, frames: 10);
      expect(queueChip, findsNothing);
      final detail = await pumpUntil(
        tester,
        h.repos.staff.workOrder(DemoStore.woAwaitingCheckIn),
      );
      expect(detail.workOrder.isCheckedIn, isTrue);
      expect(detail.workOrder.assigneeId, isNotNull);
      await flushIo(tester);
    });

    testWidgets('task card and checklist header show the check-in state', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      // In-service work order: checked in at the counter.
      await tester.tap(find.text('Continue checklist'));
      await settle(tester, frames: 10);
      final chip = find.byKey(const ValueKey('checked-in-chip'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.textContaining('Checked in ')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, frames: 10);

      await tester.tap(find.textContaining('Queue ·'));
      await settle(tester);
      await scrollTo(tester, queueChip);
      expect(queueChip, findsOneWidget);
      expect(find.text('Awaiting check-in'), findsOneWidget);
      await tester.tap(find.text('WO-$year-4819'));
      await settle(tester, frames: 10);
      expect(find.byKey(const ValueKey('awaiting-checkin-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('checked-in-chip')), findsNothing);
      await flushIo(tester);
    });
  });
}
