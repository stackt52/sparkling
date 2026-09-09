import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../app/scope.dart';

/// Header sync chip bound to [SyncStatusController] (STF-062). Tapping opens
/// the sync centre.
class LiveSyncChip extends StatelessWidget {
  const LiveSyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.syncStatus;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => SyncChip(
        state: sync.state,
        label: sync.label,
        onTap: () => context.push('/sync'),
      ),
    );
  }
}

/// Offline banner shown at the top of screens while offline (CUS-054 style).
class LiveOfflineBanner extends StatelessWidget {
  const LiveOfflineBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(20, 0, 20, 12),
  });
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final sync = context.syncStatus;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (sync.online) return const SizedBox.shrink();
        final last = sync.lastSync;
        return OfflineBanner(
          margin: margin,
          lastSyncLabel: last == null ? null : SparklingDates.hhmm(last),
          onRetry: () => sync.syncNow(),
        );
      },
    );
  }
}
