import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/adaptive.dart';
import '../../widgets/async_view.dart';
import '../../widgets/avatar_tile.dart';
import '../../widgets/feedback.dart';
import '../../widgets/kpi_tile.dart';
import '../../widgets/live_sync_chip.dart';
import '../../widgets/screen_header.dart';
import '../checklist/handover_sheet.dart';
import 'assign_sheet.dart';

/// Attention filter (STF-061).
enum OpsFilter { all, blocked, overdue, stock }

/// Supervisor ops (2c): 4 KPI tiles, "Needs attention" cards with Reassign /
/// Substitute stock, team load rows. Realtime via `watchOpsSummary`.
class OpsScreen extends StatefulWidget {
  const OpsScreen({super.key});

  @override
  State<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends State<OpsScreen> {
  StreamSubscription<OpsSummary>? _sub;
  StreamSubscription<List<Task>>? _doneSub;
  List<Task> _done = const [];
  OpsSummary? _summary;
  Object? _error;
  OpsFilter _filter = OpsFilter.all;
  DateTime? _date;
  bool _showAll = false;
  Future<Outlet?>? _outlet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= _subscribe();
    _doneSub ??= context.repositories.staff
        .watchTasks(scope: TaskScope.done, outletId: context.session.outletId)
        .listen(
          (list) {
            if (mounted) setState(() => _done = list);
          },
          onError: (Object _) {
            // The KPI stream surfaces errors; the done list is supplementary.
          },
        );
    _outlet ??= context.repositories.catalogue.outlet(context.session.outletId);
  }

  StreamSubscription<OpsSummary> _subscribe() {
    _sub?.cancel();
    return context.repositories.staff
        .watchOpsSummary(outletId: context.session.outletId)
        .listen(
          (s) {
            if (!mounted) return;
            setState(() {
              _summary = s;
              _error = null;
            });
            context.syncStatus.markSynced();
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = e);
          },
        );
  }

  void _refresh() => setState(() => _sub = _subscribe());

  @override
  void dispose() {
    _sub?.cancel();
    _doneSub?.cancel();
    super.dispose();
  }

  Future<void> _handover(Task task) async {
    final wo = task.workOrder;
    final result = await showHandoverSheet(
      context,
      workOrderId: task.workOrderId,
      ref: task.ref,
      customerName: wo?.customerName,
      vehicleLabel: wo?.vehicle?.registrationNo,
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      StaffSnack.show(context, '${task.ref}: keys released');
    }
  }

  List<AttentionItem> _filtered(OpsSummary s) {
    Iterable<AttentionItem> items = s.needsAttention;
    items = switch (_filter) {
      OpsFilter.all => items,
      OpsFilter.blocked => items.where((i) => i.kind == AttentionKind.blocked),
      OpsFilter.overdue => items.where(
        (i) => i.kind == AttentionKind.overdueSla,
      ),
      OpsFilter.stock => items.where(
        (i) =>
            i.kind == AttentionKind.lowStock ||
            i.kind == AttentionKind.outOfStock,
      ),
    };
    final d = _date;
    if (d != null) {
      items = items.where((i) {
        final at = i.since;
        if (at == null) return true;
        return at.year == d.year && at.month == d.month && at.day == d.day;
      });
    }
    return items.toList();
  }

  Future<Task?> _findTask(String id) async {
    final staff = context.repositories.staff;
    final outletId = context.session.outletId;
    for (final scope in TaskScope.values) {
      final list = await staff.tasks(scope: scope, outletId: outletId);
      final t = list.where((t) => t.id == id).firstOrNull;
      if (t != null) return t;
    }
    return null;
  }

  Future<void> _reassign(AttentionItem item) async {
    final link = item.link;
    if (link == null || link.type != 'task') return;
    final staff = context.repositories.staff;
    final outletId = context.session.outletId;
    Task? task;
    List<StaffMember> team;
    try {
      task = await _findTask(link.id);
      team = await staff.team(outletId: outletId);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
      return;
    }
    if (!mounted) return;
    if (task == null) {
      StaffSnack.show(context, 'Task not found — it may have been completed.');
      return;
    }
    final choice = await showAssignSheet(context, task: task, team: team);
    if (choice == null || !mounted) return;
    final result = await runMutation(
      context,
      () => staff.assignTask(
        task!,
        assigneeId: choice.member.id,
        reason: choice.reason,
      ),
      queuedLabel: 'Assign ${task.ref}',
      onConflict: _refresh,
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      StaffSnack.show(
        context,
        '${task.ref} assigned to ${choice.member.firstName}',
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter floor view',
                  style: SparklingTypography.headlineSmall.copyWith(
                    color: ctx.colors.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in OpsFilter.values)
                      ChoiceChip(
                        label: Text(_filterLabel(f)),
                        selected: _filter == f,
                        onSelected: (_) {
                          setState(() => _filter = f);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: _date == null
                            ? 'Today'
                            : SparklingDates.dayMonth(_date!),
                        icon: Symbols.event_available_rounded,
                        variant: PillButtonVariant.tonal,
                        expand: true,
                        onPressed: () async {
                          await _pickDate();
                          setSheet(() {});
                        },
                      ),
                    ),
                    if (_date != null) ...[
                      const SizedBox(width: 10),
                      PillButton(
                        label: 'Clear',
                        variant: PillButtonVariant.outlined,
                        onPressed: () {
                          setState(() => _date = null);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _filterLabel(OpsFilter f) => switch (f) {
    OpsFilter.all => 'All',
    OpsFilter.blocked => 'Blocked',
    OpsFilter.overdue => 'Overdue SLA',
    OpsFilter.stock => 'Stock',
  };

  void _toggleFilter(OpsFilter f) =>
      setState(() => _filter = _filter == f ? OpsFilter.all : f);

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final snapshot = _summary != null
        ? AsyncSnapshot<OpsSummary>.withData(ConnectionState.active, _summary!)
        : _error != null
        ? AsyncSnapshot<OpsSummary>.withError(ConnectionState.active, _error!)
        : const AsyncSnapshot<OpsSummary>.waiting();

    final header = FutureBuilder<Outlet?>(
      future: _outlet,
      builder: (context, snap) => ScreenHeader(
        overline:
            '${session.isManager ? 'Manager' : 'Supervisor'} · ${snap.data?.name ?? 'Outlet'}',
        title: "Today's floor",
        trailing: IconTileButton(
          icon: Symbols.tune_rounded,
          tooltip: 'Filters',
          selected: _filter != OpsFilter.all || _date != null,
          onPressed: _openFilters,
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: AsyncView<OpsSummary>(
        snapshot: snapshot,
        onRetry: _refresh,
        loading: Column(
          children: [
            header,
            const Expanded(child: LoadingState()),
          ],
        ),
        builder: (context, s) {
          final items = _filtered(s);
          final visible = _showAll ? items : items.take(3).toList();
          final kpis = _KpiRow(
            counts: s.counts,
            filter: _filter,
            onToggle: _toggleFilter,
          );
          final attention = <Widget>[
            SectionHeader(
              title: 'Needs attention',
              actionLabel: items.length > 3
                  ? (_showAll ? 'Show less' : 'View all')
                  : null,
              onAction: () => setState(() => _showAll = !_showAll),
            ),
            if (items.isEmpty)
              ListTileCard(
                leading: Icon(
                  Symbols.task_alt_rounded,
                  color: context.sparkling.success,
                  fill: 1,
                ),
                title: const Text('All clear'),
                subtitle: Text(
                  _filter == OpsFilter.all && _date == null
                      ? 'No blocked or overdue work right now.'
                      : 'Nothing matches the current filter.',
                ),
              ),
            for (final item in visible) ...[
              _AttentionCard(
                item: item,
                onReassign: () => _reassign(item),
                onSubstitute: () => context.go(Routes.inventory),
              ),
              const SizedBox(height: 12),
            ],
          ];
          final awaiting = _done
              .where((t) => t.workOrder?.awaitingCollection ?? false)
              .toList();
          final collected = _done
              .where((t) => t.workOrder?.isCollected ?? false)
              .toList();
          final doneList = <Widget>[
            SectionHeader(
              title: 'Done today',
              trailing: Text(
                awaiting.isEmpty
                    ? '${_done.length} verified'
                    : '${awaiting.length} awaiting collection',
                style: SparklingTypography.bodyLarge.copyWith(
                  color: awaiting.isEmpty
                      ? context.colors.onSurfaceVariant
                      : context.colors.primary,
                ),
              ),
            ),
            if (_done.isEmpty)
              const ListTileCard(
                title: Text('Nothing verified yet'),
                subtitle: Text(
                  'Verified work shows here until it is collected.',
                ),
              ),
            for (final t in awaiting) ...[
              _DoneRow(task: t, onHandover: () => _handover(t)),
              const SizedBox(height: 10),
            ],
            for (final t in collected) ...[
              _DoneRow(task: t),
              const SizedBox(height: 10),
            ],
          ];
          final team = <Widget>[
            SectionHeader(
              title: 'Team load',
              trailing: Text(
                '${s.teamLoad.where((t) => t.availability != AvailabilityStatus.off).length} on shift',
                style: SparklingTypography.bodyLarge.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final row in s.teamLoad) ...[
              _TeamRow(row: row),
              const SizedBox(height: 10),
            ],
          ];

          if (Breakpoints.isExpanded(context)) {
            return Column(
              children: [
                header,
                const LiveOfflineBanner(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 10, 24),
                          children: [
                            kpis,
                            const SizedBox(height: 24),
                            ...attention,
                            const SizedBox(height: 12),
                            ...doneList,
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(10, 0, 20, 24),
                          children: team,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              header,
              const LiveOfflineBanner(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    kpis,
                    const SizedBox(height: 24),
                    ...attention,
                    const SizedBox(height: 12),
                    ...doneList,
                    const SizedBox(height: 12),
                    ...team,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.counts,
    required this.filter,
    required this.onToggle,
  });
  final OpsCounts counts;
  final OpsFilter filter;
  final ValueChanged<OpsFilter> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: KpiTile(
            value: '${counts.inProgress}',
            label: 'In progress',
            tone: StatTone.azure,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: KpiTile(value: '${counts.queued}', label: 'Queued'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: KpiTile(
            value: '${counts.blocked}',
            label: 'Blocked',
            tone: StatTone.error,
            selected: filter == OpsFilter.blocked,
            onTap: () => onToggle(OpsFilter.blocked),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: KpiTile(
            value: '${counts.done}',
            label: 'Done',
            tone: StatTone.success,
          ),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.item,
    required this.onReassign,
    required this.onSubstitute,
  });
  final AttentionItem item;
  final VoidCallback onReassign;
  final VoidCallback onSubstitute;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final blocked = item.kind == AttentionKind.blocked;
    final overdue = item.kind == AttentionKind.overdueSla;
    final stock =
        item.kind == AttentionKind.lowStock ||
        item.kind == AttentionKind.outOfStock;
    final (IconData icon, Color iconBg, Color iconFg, Color border) = blocked
        ? (
            Symbols.block_rounded,
            cs.errorContainer,
            cs.onErrorContainer,
            cs.error.withValues(alpha: 0.55),
          )
        : overdue
        ? (
            Symbols.schedule_rounded,
            SparklingColors.goldDeep.withValues(alpha: 0.25),
            SparklingColors.goldDeep,
            SparklingColors.goldDeep.withValues(alpha: 0.7),
          )
        : (
            Symbols.inventory_2_rounded,
            x.warningContainer,
            x.onWarningContainer,
            x.gold.withValues(alpha: 0.5),
          );
    final since = item.since;
    var title = item.title;
    if (since != null) {
      final diff = DateTime.now().difference(since);
      final span = diff.inHours > 0
          ? '${diff.inHours} h ${diff.inMinutes % 60} min'
          : '${diff.inMinutes} min';
      title += overdue ? ' · SLA +$span' : ' · $span';
    }
    final showReassign = item.actions.contains('reassign');
    final showSubstitute = item.actions.contains('substitute_stock') || stock;

    return ListTileCard(
      borderColor: border,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                ),
                child: Icon(icon, size: 18, color: iconFg, fill: 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (item.detail != null) ...[
            const SizedBox(height: 6),
            Text(
              item.detail!,
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (showReassign || showSubstitute) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (showReassign)
                  PillButton(
                    label: 'Reassign',
                    minHeight: 48,
                    onPressed: onReassign,
                  ),
                if (showSubstitute)
                  PillButton(
                    label: stock ? 'Open stock' : 'Substitute stock',
                    variant: PillButtonVariant.outlined,
                    minHeight: 48,
                    onPressed: onSubstitute,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.row});
  final TeamLoadRow row;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final available = row.isAvailable;
    final off = row.availability == AvailabilityStatus.off;
    return ListTileCard(
      opacity: off ? 0.55 : 1,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AvatarTile(
            initials: row.initials,
            size: 48,
            radius: 14,
            tone: AvatarTile.toneFor(row.staffId),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                available
                    ? LinearLevelBar(value: 0.25, state: LevelState.ok)
                    : LinearLevelBar.progress(
                        value: row.load,
                        gradient: const LinearGradient(
                          colors: [
                            SparklingColors.azure,
                            SparklingColors.azure,
                          ],
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            off ? 'Off shift' : row.label,
            style: SparklingTypography.titleMedium.copyWith(
              color: available ? x.success : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Verified work order in the ops "Done today" list: hand-over CTA while the
/// customer has not collected, otherwise the release time.
class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.task, this.onHandover});
  final Task task;
  final VoidCallback? onHandover;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final wo = task.workOrder;
    final collectedAt = wo?.collectedAt;
    final subtitle = [
      wo?.vehicle?.registrationNo,
      wo?.customerName,
      if (task.completedAt != null)
        'verified ${SparklingDates.hhmm(task.completedAt!)}',
    ].whereType<String>().join(' · ');
    return ListTileCard(
      key: ValueKey('done-${task.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      borderColor: collectedAt == null
          ? cs.primary.withValues(alpha: 0.4)
          : null,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: collectedAt == null ? cs.primaryContainer : x.successContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          collectedAt == null ? Symbols.key_rounded : Symbols.check_rounded,
          color: collectedAt == null ? cs.primary : x.onSuccessContainer,
          fill: 1,
          size: 20,
        ),
      ),
      title: Text(
        '${task.ref} · ${wo?.serviceName ?? task.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        collectedAt == null
            ? subtitle
            : 'Keys released ${SparklingDates.hhmm(collectedAt)}${subtitle.isEmpty ? '' : ' · $subtitle'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: collectedAt == null && onHandover != null
          ? PillButton(
              label: 'Hand over',
              icon: Symbols.key_rounded,
              variant: PillButtonVariant.tonal,
              minHeight: 48,
              onPressed: onHandover,
            )
          : null,
    );
  }
}
