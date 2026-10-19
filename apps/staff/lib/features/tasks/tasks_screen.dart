import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/async_view.dart';
import '../../widgets/fab_menu.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/segmented_pills.dart';
import '../checklist/checklist_screen.dart';
import '../checklist/handover_sheet.dart';
import 'task_card.dart';

/// "today" / "this week" / "this month" for empty-state copy.
String _periodLabel(TaskPeriod p) => switch (p) {
  TaskPeriod.today => 'today',
  TaskPeriod.week => 'this week',
  TaskPeriod.month => 'this month',
  TaskPeriod.all => '',
};

/// "My tasks" (2a/2g): outlet header + sync chip, Mine/Queue/Done segments
/// with live counts, task cards and the quick-action FAB menu. Queue and Done
/// default to today's work with a Today / Week / Month / All period picker
/// (Mine always shows everything open). Realtime through `staff.watchTasks`;
/// two-pane with the checklist on tablets (UX-005).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  TaskScope _scope = TaskScope.mine;
  TaskPeriod _period = TaskPeriod.today;
  final Map<TaskScope, List<Task>> _tasks = {};
  final Map<TaskScope, StreamSubscription<List<Task>>> _subs = {};
  Object? _error;
  String? _selectedWorkOrderId;
  Future<Outlet?>? _outlet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isEmpty) _subscribe();
    _outlet ??= context.repositories.catalogue.outlet(context.session.outletId);
  }

  /// Scopes the period picker applies to; Mine always lists everything open.
  static const _periodScopes = {TaskScope.queue, TaskScope.done};

  void _subscribe({Set<TaskScope>? scopes}) {
    final staff = context.repositories.staff;
    final outletId = context.session.outletId;
    final targets = scopes ?? TaskScope.values.toSet();
    for (final scope in targets) {
      _subs.remove(scope)?.cancel();
      _tasks.remove(scope);
    }
    _error = null;
    for (final scope in targets) {
      _subs[scope] = staff
          .watchTasks(
            scope: scope,
            outletId: outletId,
            period: _periodScopes.contains(scope) ? _period : TaskPeriod.all,
          )
          .listen(
            (list) {
              if (!mounted) return;
              setState(() {
                _tasks[scope] = list;
                _error = null;
              });
              context.syncStatus.markSynced();
            },
            onError: (Object e) {
              if (mounted) setState(() => _error = e);
            },
          );
    }
  }

  void _setPeriod(TaskPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _subscribe(scopes: _periodScopes);
  }

  final _fabMenu = FabMenuController();

  @override
  void dispose() {
    _fabMenu.dispose();
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  void _open(Task task) {
    final id = task.workOrderId;
    if (Breakpoints.isExpanded(context)) {
      setState(() => _selectedWorkOrderId = id);
    } else {
      context.push(Routes.checklist(id));
    }
  }

  Future<void> _start(Task task) async {
    final staff = context.repositories.staff;
    final result = await runMutation(
      context,
      () => staff.transitionTask(
        task,
        TaskTransitionInput(
          to: WorkStatus.inProgress,
          clientOpId: SparklingApi.newOpId(),
        ),
      ),
      queuedLabel: 'Start ${task.ref}',
      onConflict: _subscribe,
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      _open(result);
    }
  }

  Future<void> _handover(Task task) async {
    final wo = task.workOrder;
    final result = await showHandoverSheet(
      context,
      workOrderId: task.workOrderId,
      ref: task.ref,
      customerName: wo?.customerName,
      vehicleLabel: wo?.vehicle?.registrationNo,
      booking: wo?.booking,
    );
    if (result != null && mounted) {
      StaffSnack.show(context, '${task.ref}: keys released');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _tasks[_scope];
    final canSupervise = context.session.canSupervise;
    final snapshot = _error != null && list == null
        ? AsyncSnapshot<List<Task>>.withError(ConnectionState.active, _error!)
        : list == null
        ? const AsyncSnapshot<List<Task>>.waiting()
        : AsyncSnapshot<List<Task>>.withData(ConnectionState.active, list);

    final master = Scaffold(
      backgroundColor: Colors.transparent,
      // FAB menu (M3 Expressive): one primary "+" FAB that expands into the
      // three quick actions — scan disc, walk-in booking, raise quote
      // (STF-010/012). The scrim below closes it.
      floatingActionButton: FabMenu(
        controller: _fabMenu,
        tooltip: 'Quick actions',
        actions: [
          FabMenuAction(
            key: const ValueKey('fab-scan-disc'),
            icon: Symbols.qr_code_scanner_rounded,
            label: 'Scan disc',
            primary: true,
            onPressed: () => context.go(Routes.scan),
          ),
          FabMenuAction(
            key: const ValueKey('fab-walk-in'),
            icon: Symbols.person_add_rounded,
            label: 'Walk-in booking',
            onPressed: () => context.push(Routes.walkIn),
          ),
          FabMenuAction(
            key: const ValueKey('fab-raise-quote'),
            icon: Symbols.request_quote_rounded,
            label: 'Raise quote',
            onPressed: () => context.push(Routes.quoteNew),
          ),
        ],
      ),
      body: FabMenuScrim(
        controller: _fabMenu,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              FutureBuilder<Outlet?>(
                future: _outlet,
                builder: (context, snap) => ScreenHeader(
                  overline: '${snap.data?.name ?? 'Outlet'} · Bay team',
                  title: 'My tasks',
                  trailing: const LiveSyncChip(),
                ),
              ),
              const LiveOfflineBanner(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  _periodScopes.contains(_scope) ? 10 : 16,
                ),
                child: SegmentedPills<TaskScope>(
                  selected: _scope,
                  onChanged: (s) => setState(() => _scope = s),
                  segments: [
                    PillSegment(
                      value: TaskScope.mine,
                      label: 'Mine',
                      count: _tasks[TaskScope.mine]?.length,
                    ),
                    PillSegment(
                      value: TaskScope.queue,
                      label: 'Queue',
                      count: _tasks[TaskScope.queue]?.length,
                    ),
                    PillSegment(
                      value: TaskScope.done,
                      label: 'Done',
                      count: _tasks[TaskScope.done]?.length,
                    ),
                  ],
                ),
              ),
              // Period picker for Queue / Done (today by default).
              if (_periodScopes.contains(_scope))
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SegmentedPills<TaskPeriod>(
                    key: const ValueKey('task-period-pills'),
                    grouped: true,
                    height: 44,
                    selected: _period,
                    onChanged: _setPeriod,
                    segments: const [
                      PillSegment(value: TaskPeriod.today, label: 'Today'),
                      PillSegment(value: TaskPeriod.week, label: 'Week'),
                      PillSegment(value: TaskPeriod.month, label: 'Month'),
                      PillSegment(value: TaskPeriod.all, label: 'All'),
                    ],
                  ),
                ),
              Expanded(
                child: AsyncView<List<Task>>(
                  snapshot: snapshot,
                  onRetry: _subscribe,
                  emptyWhen: (l) => l.isEmpty,
                  empty: EmptyState(
                    icon: Symbols.checklist_rounded,
                    title: switch (_scope) {
                      TaskScope.mine =>
                        canSupervise
                            ? 'Nothing needs you right now'
                            : 'No tasks assigned to you',
                      TaskScope.queue =>
                        _period == TaskPeriod.all
                            ? 'The queue is empty'
                            : 'No work queued ${_periodLabel(_period)}',
                      TaskScope.done =>
                        _period == TaskPeriod.all
                            ? 'Nothing completed yet'
                            : 'Nothing completed ${_periodLabel(_period)}',
                    },
                    text: switch (_scope) {
                      TaskScope.mine =>
                        canSupervise
                            ? 'Your own tasks and sign-off requests from the bay team land here.'
                            : 'Pick one up from the queue or scan a disc to check a vehicle in.',
                      _ =>
                        _period == TaskPeriod.all
                            ? null
                            : 'Pick another period to see earlier or later work.',
                    },
                  ),
                  builder: (context, tasks) => ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: SparklingSpacing.cardGap),
                    itemBuilder: (context, i) {
                      final t = tasks[i];
                      return TaskCard(
                        key: ValueKey(t.id),
                        task: t,
                        selected: t.workOrderId == _selectedWorkOrderId,
                        onOpen: () => _open(t),
                        onStart:
                            (t.status == WorkStatus.assigned ||
                                t.status == WorkStatus.queued)
                            ? () => _start(t)
                            : null,
                        onHandover: t.workOrder?.awaitingCollection ?? false
                            ? () => _handover(t)
                            : null,
                        // Supervisors: the checklist reached its sign-off
                        // step — open it at the supervisor card (STF-033).
                        onVerify: canSupervise && t.awaitingVerification
                            ? () => _open(t)
                            : null,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return MasterDetail(
      master: master,
      masterWidth: 440,
      detail: _selectedWorkOrderId == null
          ? const EmptyState(
              icon: Symbols.checklist_rounded,
              title: 'Select a task',
              text: 'The checklist opens here.',
            )
          : ChecklistView(
              key: ValueKey(_selectedWorkOrderId),
              workOrderId: _selectedWorkOrderId!,
              embedded: true,
              onClose: () => setState(() => _selectedWorkOrderId = null),
            ),
    );
  }
}
