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
import '../quote/quote_widgets.dart';
import 'assign_sheet.dart';

/// Attention filter (STF-061).
enum OpsFilter { all, blocked, overdue, stock }

/// Supervisor ops (2c): 4 KPI tiles, "Needs attention" cards with Reassign /
/// Substitute stock, the unassigned **Assignment queue** (work orders that
/// still await their vehicle check-in carry an "Awaiting check-in" chip and
/// are assigned through the sheet's **Confirm check-in**), team load rows.
/// Realtime via `watchOpsSummary` / `watchTasks`.
class OpsScreen extends StatefulWidget {
  const OpsScreen({super.key});

  @override
  State<OpsScreen> createState() => _OpsScreenState();
}

class _OpsScreenState extends State<OpsScreen> {
  StreamSubscription<OpsSummary>? _sub;
  StreamSubscription<List<Task>>? _doneSub;
  StreamSubscription<List<Task>>? _queueSub;
  StreamSubscription<List<Quotation>>? _quotesSub;
  List<Task> _done = const [];
  List<Task> _queue = const [];
  List<Quotation> _quotes = const [];
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
    _queueSub ??= context.repositories.staff
        .watchTasks(scope: TaskScope.queue, outletId: context.session.outletId)
        .listen(
          (list) {
            if (!mounted) return;
            setState(() {
              _queue = list
                  .where((t) => t.assigneeId == null && t.status.isOpen)
                  .toList();
            });
          },
          onError: (Object _) {
            // Supplementary section; the KPI stream surfaces errors.
          },
        );
    _quotesSub ??= context.repositories.staff
        .watchQuotations(outletId: context.session.outletId)
        .listen(
          (list) {
            if (mounted) setState(() => _quotes = list);
          },
          onError: (Object _) {
            // Supplementary section; the KPI stream surfaces errors.
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
    _queueSub?.cancel();
    _quotesSub?.cancel();
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
      booking: wo?.booking,
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
    Task? task;
    try {
      task = await _findTask(link.id);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
      return;
    }
    if (!mounted) return;
    if (task == null) {
      StaffSnack.show(context, 'Task not found — it may have been completed.');
      return;
    }
    await _assign(task);
  }

  /// Opens the assign sheet for [task] and applies the choice. A 409
  /// `not_checked_in` (vehicle not on site) surfaces the server message and
  /// refreshes so the queue shows the "Awaiting check-in" state.
  Future<void> _assign(Task task) async {
    final staff = context.repositories.staff;
    List<StaffMember> team;
    try {
      team = await staff.team(outletId: context.session.outletId);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
      return;
    }
    if (!mounted) return;
    final choice = await showAssignSheet(context, task: task, team: team);
    if (choice == null || !mounted) return;
    try {
      await staff.assignTask(
        task,
        assigneeId: choice.member.id,
        reason: choice.reason,
      );
      if (mounted && context.syncStatus.state != SyncState.synced) {
        StaffSnack.queued(context, 'Assign ${task.ref}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      StaffHaptics.error(context);
      if (e.isNotCheckedIn) {
        StaffSnack.show(context, e.message);
        _refresh();
      } else if (e.isConflict) {
        await showConflictDialog(context, e, onRefresh: _refresh);
      } else {
        StaffSnack.error(context, e);
      }
      return;
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
      return;
    }
    if (mounted) {
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
          final quickActions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuickAction(
                key: const ValueKey('ops-walk-in'),
                icon: Symbols.person_add_rounded,
                title: 'Walk-in booking',
                subtitle: 'Register a customer, book and check in at the counter',
                onTap: () => context.push(Routes.walkIn),
              ),
              const SizedBox(height: 10),
              _QuickAction(
                key: const ValueKey('ops-raise-quote'),
                icon: Symbols.request_quote_rounded,
                title: 'Raise quote',
                subtitle: 'Itemised repair quote with photos, sent on WhatsApp',
                onTap: () => context.push(Routes.quoteNew),
              ),
            ],
          );
          final recentQuotes = _quotes.take(5).toList();
          final quotes = <Widget>[
            SectionHeader(
              title: 'Quotes',
              trailing: Text(
                '${_quotes.where((q) => q.status == QuotationStatus.quoted).length} awaiting',
                style: SparklingTypography.bodyLarge.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            if (recentQuotes.isEmpty)
              const ListTileCard(
                title: Text('No quotes yet'),
                subtitle: Text('Raise one from the quick action above.'),
              ),
            for (final q in recentQuotes) ...[
              _QuoteRow(quotation: q),
              const SizedBox(height: 10),
            ],
          ];
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
          final unchecked = _queue
              .where((t) => !(t.workOrder?.isCheckedIn ?? true))
              .length;
          final queueList = <Widget>[
            SectionHeader(
              title: 'Assignment queue',
              trailing: Text(
                unchecked > 0
                    ? '$unchecked awaiting check-in'
                    : '${_queue.length} unassigned',
                style: SparklingTypography.bodyLarge.copyWith(
                  color: unchecked > 0
                      ? context.sparkling.onWarningContainer
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
            if (_queue.isEmpty)
              const ListTileCard(
                title: Text('Nothing waiting'),
                subtitle: Text(
                  'Unassigned work orders show here until someone takes them.',
                ),
              ),
            for (final t in _queue) ...[
              _QueueRow(task: t, onAssign: () => _assign(t)),
              const SizedBox(height: 10),
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
                            const SizedBox(height: 14),
                            quickActions,
                            const SizedBox(height: 24),
                            ...attention,
                            const SizedBox(height: 12),
                            ...queueList,
                            const SizedBox(height: 12),
                            ...doneList,
                            const SizedBox(height: 12),
                            ...quotes,
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
                    const SizedBox(height: 14),
                    quickActions,
                    const SizedBox(height: 24),
                    ...attention,
                    const SizedBox(height: 12),
                    ...queueList,
                    const SizedBox(height: 12),
                    ...doneList,
                    const SizedBox(height: 12),
                    ...quotes,
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

/// Unassigned open work order in the ops "Assignment queue": check-in state
/// chip ("Awaiting check-in" until the vehicle is on site) and an Assign CTA
/// that opens the assign sheet.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.task, required this.onAssign});
  final Task task;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final wo = task.workOrder;
    final checkedInAt = wo?.checkedInAt;
    final awaiting = wo != null && !wo.isCheckedIn;
    final detail = [
      wo?.vehicle?.registrationNo,
      wo?.customerName,
      wo?.bay,
    ].whereType<String>().join(' · ');
    final at = wo?.slotStart ?? wo?.etaAt ?? task.dueAt;
    return ListTileCard(
      key: ValueKey('queue-${task.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      borderColor: awaiting ? x.gold.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: awaiting ? x.warningContainer : cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  awaiting ? Symbols.login_rounded : Symbols.assignment_ind_rounded,
                  color: awaiting ? x.onWarningContainer : cs.onPrimaryContainer,
                  fill: 1,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${task.ref} · ${wo?.serviceName ?? task.title}',
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 17,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (awaiting)
                      StatusChip(
                        key: ValueKey('awaiting-checkin-${task.id}'),
                        label: 'Awaiting check-in',
                        tone: StatusChipTone.warning,
                        icon: Symbols.login_rounded,
                        dense: true,
                      )
                    else if (checkedInAt != null)
                      StatusChip(
                        key: ValueKey('checked-in-${task.id}'),
                        label: 'Checked in ${SparklingDates.hhmm(checkedInAt)}',
                        tone: StatusChipTone.success,
                        icon: Symbols.login_rounded,
                        dense: true,
                      ),
                    StatusChip(
                      label: at == null
                          ? task.status.label
                          : '${task.status.label} · ${SparklingDates.hhmm(at)}',
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              PillButton(
                key: ValueKey('queue-assign-${task.id}'),
                label: awaiting ? 'Check in & assign' : 'Assign',
                variant: PillButtonVariant.tonal,
                minHeight: 48,
                onPressed: onAssign,
              ),
            ],
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTileCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.iconTileSmall),
      ),
      child: Icon(icon, color: context.colors.onPrimaryContainer, fill: 1),
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Icon(
      Symbols.chevron_right_rounded,
      color: context.colors.onSurfaceVariant,
    ),
  );
}

/// Recent outlet quotation with its status chip → `/quotes/:id`.
class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quotation});
  final Quotation quotation;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final q = quotation;
    return ListTileCard(
      key: ValueKey('ops-quote-${q.id}'),
      onTap: () => context.push(Routes.quoteDetail(q.id)),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Symbols.request_quote_rounded,
          color: cs.onSecondaryContainer,
          fill: 1,
          size: 20,
        ),
      ),
      title: Text(
        '${q.ref} · ${q.amountCents == null ? q.category : Money.formatZar(q.amountCents!)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [q.customerName, q.vehicleLabel].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusChip(
        label: q.isExpired ? 'Expired' : q.status.label,
        tone: q.isExpired ? StatusChipTone.error : quotationTone(q.status),
        dense: true,
      ),
    );
  }
}
