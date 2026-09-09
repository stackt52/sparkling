import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';

/// Sync chip: synced (green) / queued (gold) / offline. Tapping opens the
/// sync status screen (CUS-054, ARC-004).
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  StreamSubscription<bool>? _conn;
  StreamSubscription<List<QueuedOperation>>? _queue;
  bool _online = true;
  int _pending = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_conn != null) return;
    final repos = context.repos;
    _online = repos.connectivity.lastKnown;
    _pending = repos.offlineQueue.pendingCount;
    _conn = repos.connectivity.online.listen((v) {
      if (mounted) setState(() => _online = v);
    });
    _queue = repos.offlineQueue.changes.listen((ops) {
      if (mounted) {
        setState(() => _pending = ops.where((o) => o.isPending).length);
      }
    });
  }

  @override
  void dispose() {
    _conn?.cancel();
    _queue?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = !_online
        ? SyncState.offline
        : _pending > 0
        ? SyncState.queued
        : SyncState.synced;
    final label = switch (state) {
      SyncState.offline => 'Offline',
      SyncState.queued => '$_pending queued',
      SyncState.synced => 'Synced',
    };
    return SyncChip(
      state: state,
      label: label,
      onTap: () => context.push(Routes.sync),
    );
  }
}
