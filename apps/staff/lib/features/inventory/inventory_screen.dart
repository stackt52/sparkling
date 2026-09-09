import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import '../../widgets/screen_header.dart';
import 'usage_sheet.dart';

/// Stock (2f): alert banner, search pill, item cards with level bars and
/// "x of y · min z", technician actions (Request reorder / Log usage), manager
/// threshold edits (STF-040..043).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  StreamSubscription<List<InventoryItem>>? _sub;
  List<InventoryItem>? _items;
  Object? _error;
  String _query = '';
  Future<Outlet?>? _outlet;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= _subscribe();
    _outlet ??= context.repositories.catalogue.outlet(context.session.outletId);
  }

  StreamSubscription<List<InventoryItem>> _subscribe() {
    _sub?.cancel();
    return context.repositories.inventory
        .watchItems(outletId: context.session.outletId)
        .listen(
          (items) {
            if (!mounted) return;
            setState(() {
              _items = items;
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
    _search.dispose();
    super.dispose();
  }

  Future<void> _logUsage(InventoryItem item) async {
    final entry = await showUsageSheet(context, item: item);
    if (entry == null || !mounted) return;
    final result = await runMutation(
      context,
      () => context.repositories.inventory.logMovement(
        item,
        InventoryMovementInput(
          delta: -entry.quantity,
          reason: InventoryReason.usage,
          note: entry.note,
          clientOpId: SparklingApi.newOpId(),
        ),
      ),
      queuedLabel: 'Usage of ${item.name}',
      onConflict: _refresh,
    );
    if (result != null && mounted) StaffHaptics.success(context);
  }

  Future<void> _requestReorder(InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request reorder?'),
        content: Text(
          '${item.name} · ${item.levelLabel}\n\nThe outlet manager is notified; '
          'only a manager can place the order (STF-042).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await runMutation(
      context,
      () => context.repositories.inventory.logMovement(
        item,
        InventoryMovementInput(
          delta: 0,
          reason: InventoryReason.reorderRequest,
          clientOpId: SparklingApi.newOpId(),
        ),
      ),
      queuedLabel: 'Reorder request for ${item.name}',
      onConflict: _refresh,
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      StaffSnack.show(context, 'Reorder requested · manager notified');
    }
  }

  Future<void> _editThreshold(InventoryItem item) async {
    final controller = TextEditingController(
      text: item.reorderThreshold % 1 == 0
          ? item.reorderThreshold.toInt().toString()
          : item.reorderThreshold.toString(),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reorder threshold · ${item.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: item.unit),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final result = await runMutation(
      context,
      () => context.repositories.inventory.updateItem(
        item.id,
        reorderThreshold: value,
      ),
      onConflict: _refresh,
    );
    if (result != null && mounted) {
      StaffSnack.show(context, 'Threshold updated · audited');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    final snapshot = _items != null
        ? AsyncSnapshot<List<InventoryItem>>.withData(
            ConnectionState.active,
            _items!,
          )
        : _error != null
        ? AsyncSnapshot<List<InventoryItem>>.withError(
            ConnectionState.active,
            _error!,
          )
        : const AsyncSnapshot<List<InventoryItem>>.waiting();

    final header = FutureBuilder<Outlet?>(
      future: _outlet,
      builder: (context, snap) => ScreenHeader(
        overline: '${snap.data?.name ?? 'Outlet'} store',
        title: 'Stock',
        trailing: const LiveSyncChip(),
      ),
    );

    return SafeArea(
      bottom: false,
      child: AsyncView<List<InventoryItem>>(
        snapshot: snapshot,
        onRetry: _refresh,
        loading: Column(
          children: [header, const Expanded(child: LoadingState())],
        ),
        builder: (context, items) {
          final q = _query.trim().toLowerCase();
          final visible = items.where((i) {
            if (!i.isActive) return false;
            if (q.isEmpty) return true;
            return i.name.toLowerCase().contains(q) ||
                i.sku.toLowerCase().contains(q);
          }).toList()..sort(_sortAlertsFirst);
          final alerts = items.where((i) => i.needsAttention).toList();
          DateTime? notified;
          for (final a in alerts) {
            final at = a.alert?.notifiedAt;
            if (at != null && (notified == null || at.isAfter(notified))) {
              notified = at;
            }
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              header,
              const LiveOfflineBanner(),
              if (alerts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: InfoBanner(
                    tone: InfoTone.error,
                    bordered: true,
                    title:
                        '${alerts.length} item${alerts.length == 1 ? '' : 's'} below reorder threshold',
                    text: notified == null
                        ? 'Manager notified'
                        : 'Manager notified · ${SparklingDates.hhmm(notified)}',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search consumables…',
                    prefixIcon: const Icon(Symbols.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Symbols.close_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: const OutlineInputBorder(
                      borderRadius: SparklingShapes.pillRadius,
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: SparklingShapes.pillRadius,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: SparklingShapes.pillRadius,
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
              if (visible.isEmpty)
                const EmptyState(
                  icon: Symbols.inventory_2_rounded,
                  title: 'No items match',
                ),
              for (final item in visible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _InventoryCard(
                    item: item,
                    canManage: session.isManager,
                    onLogUsage: () => _logUsage(item),
                    onReorder: () => _requestReorder(item),
                    onEditThreshold: () => _editThreshold(item),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: AuditNote(
                  icon: Symbols.verified_user_rounded,
                  text: session.isManager
                      ? 'Manager view — threshold edits and reorders are audited.'
                      : 'Technician view — reorder & threshold edits are manager-only.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static int _sortAlertsFirst(InventoryItem a, InventoryItem b) {
    int rank(InventoryItem i) => switch (i.level) {
      StockLevel.out => 0,
      StockLevel.low => 1,
      StockLevel.ok => 2,
    };
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.compareTo(b.name);
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.canManage,
    required this.onLogUsage,
    required this.onReorder,
    required this.onEditThreshold,
  });

  final InventoryItem item;
  final bool canManage;
  final VoidCallback onLogUsage;
  final VoidCallback onReorder;
  final VoidCallback onEditThreshold;

  static IconData iconFor(InventoryItem item) {
    final n = '${item.sku} ${item.name}'.toLowerCase();
    if (n.contains('tyre') || n.contains('tire')) return Symbols.tire_repair_rounded;
    if (n.contains('wax') || n.contains('polish')) {
      return Symbols.auto_awesome_rounded;
    }
    if (n.contains('towel') || n.contains('cloth') || n.contains('brush')) {
      return Symbols.cleaning_services_rounded;
    }
    if (n.contains('glass')) return Symbols.window_rounded;
    if (n.contains('coat') || n.contains('paint') || n.contains('primer')) {
      return Symbols.format_paint_rounded;
    }
    return Symbols.water_drop_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final level = item.level;
    final state = switch (level) {
      StockLevel.ok => LevelState.ok,
      StockLevel.low => LevelState.low,
      StockLevel.out => LevelState.out,
    };
    final border = switch (level) {
      StockLevel.ok => null,
      StockLevel.low => cs.error.withValues(alpha: 0.5),
      StockLevel.out => cs.error.withValues(alpha: 0.8),
    };
    final Widget chip = switch (level) {
      StockLevel.ok => const StatusChip(
        label: 'OK',
        tone: StatusChipTone.success,
      ),
      StockLevel.low => const StatusChip(
        label: 'LOW',
        tone: StatusChipTone.error,
      ),
      StockLevel.out => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: ShapeDecoration(
          color: SparklingColors.lightError,
          shape: const StadiumBorder(),
        ),
        child: Text(
          'OUT',
          style: SparklingTypography.labelLarge.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: SparklingColors.lightOnError,
          ),
        ),
      ),
    };

    return ListTileCard(
      borderColor: border,
      onTap: item.needsAttention ? null : onLogUsage,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                iconFor(item),
                color: level == StockLevel.ok ? cs.primary : cs.error,
                fill: 1,
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.name,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (canManage) ...[
                IconTileButton(
                  icon: Symbols.edit_rounded,
                  size: 36,
                  radius: 12,
                  tooltip: 'Edit threshold',
                  onPressed: onEditThreshold,
                ),
                const SizedBox(width: 8),
              ],
              chip,
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LinearLevelBar(value: item.fillFraction, state: state),
              ),
              const SizedBox(width: 14),
              Text(
                item.levelLabel,
                style: SparklingTypography.labelLarge.copyWith(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (level == StockLevel.out) ...[
            const SizedBox(height: 10),
            Text(
              item.alert?.managerNotified ?? false
                  ? 'Out of stock · manager notified ${SparklingDates.hhmm(item.alert!.notifiedAt!)}'
                  : 'Out of stock · blocks tasks that need it',
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 14,
                color: cs.error,
              ),
            ),
          ],
          if (item.needsAttention) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                PillButton(
                  label: 'Request reorder',
                  minHeight: 48,
                  onPressed: onReorder,
                ),
                PillButton(
                  label: 'Log usage',
                  variant: PillButtonVariant.outlined,
                  minHeight: 48,
                  onPressed: level == StockLevel.out ? null : onLogUsage,
                ),
              ],
            ),
          ] else if (canManage) ...[
            const SizedBox(height: 4),
            Text(
              'Tap to log usage',
              style: SparklingTypography.bodySmall.copyWith(
                color: x.success.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
