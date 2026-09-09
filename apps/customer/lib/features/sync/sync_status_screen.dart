import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';

/// Offline / sync status surface: connectivity, queued operations, retry.
class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  StreamSubscription<bool>? _conn;
  StreamSubscription<List<QueuedOperation>>? _queue;
  bool _online = true;
  List<QueuedOperation> _ops = const [];
  bool _syncing = false;
  SyncReport? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conn != null) return;
    final repos = context.repos;
    _online = repos.connectivity.lastKnown;
    _ops = repos.offlineQueue.all;
    _conn = repos.connectivity.online.listen((v) {
      if (mounted) setState(() => _online = v);
    });
    _queue = repos.offlineQueue.changes.listen((ops) {
      if (mounted) setState(() => _ops = ops);
    });
  }

  @override
  void dispose() {
    _conn?.cancel();
    _queue?.cancel();
    super.dispose();
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final report = await context.repos.offlineQueue.sync(force: true);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final repos = context.repos;
    final pending = _ops.where((o) => o.isPending).toList();
    final others = _ops.where((o) => !o.isPending).toList();
    final lastSync = repos.cache.latestSync();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Sync status',
              subtitle: 'Changes made offline are queued and replayed',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (!_online)
                    OfflineBanner(
                      lastSyncLabel: lastSync == null
                          ? null
                          : SparklingDates.hhmm(lastSync),
                      margin: const EdgeInsets.only(bottom: 12),
                      onRetry: () => repos.connectivity.isOnline(),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Connection',
                          value: _online ? 'Online' : 'Offline',
                          tone: _online ? StatTone.success : StatTone.error,
                          icon: _online
                              ? Symbols.cloud_done_rounded
                              : Symbols.cloud_off_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'Queued',
                          value: '${pending.length}',
                          tone: pending.isEmpty
                              ? StatTone.neutral
                              : StatTone.gold,
                          icon: Symbols.cloud_sync_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KeyValueTile(
                    label: 'Last successful sync',
                    value: lastSync == null
                        ? 'Never'
                        : SparklingDates.relativeSlot(lastSync),
                    helper: repos.demo
                        ? 'Demo mode — data lives on this device'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  PillButton(
                    label: 'Sync now',
                    icon: Symbols.sync_rounded,
                    expand: true,
                    loading: _syncing,
                    onPressed: pending.isEmpty || !_online ? null : _syncNow,
                  ),
                  if (_report != null) ...[
                    const SizedBox(height: 12),
                    InfoBanner(
                      tone: _report!.isClean
                          ? InfoTone.success
                          : InfoTone.warning,
                      text:
                          '${_report!.succeeded} applied · ${_report!.failed} failed · ${_report!.conflicted} conflicts',
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_ops.isEmpty)
                    const EmptyState(
                      icon: Symbols.task_alt_rounded,
                      title: 'Everything is in sync',
                      message: 'Nothing is waiting to be sent.',
                    )
                  else ...[
                    const SectionHeader(title: 'Operations'),
                    for (final op in [...pending, ...others]) ...[
                      ListTileCard(
                        leading: Icon(
                          op.isPending
                              ? Symbols.schedule_rounded
                              : Symbols.check_circle_rounded,
                          color: op.isPending
                              ? cs.onSurfaceVariant
                              : context.sparkling.success,
                          fill: 1,
                        ),
                        title: Text(op.label ?? op.kind),
                        subtitle: Text(
                          [
                            op.status.name,
                            SparklingDates.relativeSlot(op.deviceTime),
                            if (op.lastError != null) op.lastError!,
                          ].join(' · '),
                        ),
                        trailing: op.isPending
                            ? IconTileButton(
                                icon: Symbols.refresh_rounded,
                                tooltip: 'Retry',
                                onPressed: () =>
                                    repos.offlineQueue.retry(op.clientOpId),
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
