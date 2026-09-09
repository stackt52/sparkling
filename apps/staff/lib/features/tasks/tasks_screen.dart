import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/segmented_pills.dart';
import '../checklist/checklist_screen.dart';
import 'task_card.dart';

/// "My tasks" (2a/2g): outlet header + sync chip, Mine/Queue/Done segments
/// with live counts, task cards and the "Scan disc" FAB. Realtime through
/// `staff.watchTasks`; two-pane with the checklist on tablets (UX-005).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  TaskScope _scope = TaskScope.mine;
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

  void _subscribe() {
    final staff = context.repositories.staff;
    final outletId = context.session.outletId;
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    _tasks.clear();
    _error = null;
    for (final scope in TaskScope.values) {
      _subs[scope] = staff
          .watchTasks(scope: scope, outletId: outletId)
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

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final list = _tasks[_scope];
    final snapshot = _error != null && list == null
        ? AsyncSnapshot<List<Task>>.withError(ConnectionState.active, _error!)
        : list == null
        ? const AsyncSnapshot<List<Task>>.waiting()
        : AsyncSnapshot<List<Task>>.withData(ConnectionState.active, list);

    final master = Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan-disc',
        onPressed: () => context.go(Routes.scan),
        icon: const Icon(Symbols.qr_code_scanner_rounded, fill: 0),
        label: const Text('Scan disc'),
      ),
      body: SafeArea(
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
            Expanded(
              child: AsyncView<List<Task>>(
                snapshot: snapshot,
                onRetry: _subscribe,
                emptyWhen: (l) => l.isEmpty,
                empty: EmptyState(
                  icon: Symbols.checklist_rounded,
                  title: switch (_scope) {
                    TaskScope.mine => 'No tasks assigned to you',
                    TaskScope.queue => 'The queue is empty',
                    TaskScope.done => 'Nothing completed yet today',
                  },
                  text: _scope == TaskScope.mine
                      ? 'Pick one up from the queue or scan a disc to check a vehicle in.'
                      : null,
                ),
                builder: (context, tasks) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
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
                    );
                  },
                ),
              ),
            ),
          ],
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
