import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';

/// Sync centre (NFR-005, ARC-004): queued operations with status
/// (pending / syncing / failed / conflicted), retry & remove, last sync time.
class SyncCentreScreen extends StatelessWidget {
  const SyncCentreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final sync = context.syncStatus;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: sync,
          builder: (context, _) {
            final ops = sync.operations.reversed.toList();
            final last = sync.lastSync;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(
                  children: [
                    IconTileButton(
                      icon: Symbols.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Sync centre',
                        style: SparklingTypography.headlineMedium.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    SyncChip(state: sync.state, label: sync.label),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: '${sync.pendingCount}',
                        label: 'Queued',
                        tone: sync.pendingCount > 0
                            ? StatTone.gold
                            : StatTone.neutral,
                        icon: Symbols.cloud_sync_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        value: '${sync.needsAttention.length}',
                        label: 'Failed',
                        tone: sync.needsAttention.isNotEmpty
                            ? StatTone.error
                            : StatTone.neutral,
                        icon: Symbols.sync_problem_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        value: last == null ? '—' : SparklingDates.hhmm(last),
                        label: 'Last sync',
                        tone: sync.online ? StatTone.success : StatTone.neutral,
                        icon: sync.online
                            ? Symbols.cloud_done_rounded
                            : Symbols.cloud_off_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (!sync.online)
                  OfflineBanner(
                    margin: const EdgeInsets.only(bottom: 12),
                    lastSyncLabel: last == null
                        ? null
                        : SparklingDates.hhmm(last),
                    onRetry: () => sync.syncNow(),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'Sync now',
                        icon: Symbols.sync_rounded,
                        expand: true,
                        loading: sync.syncing,
                        onPressed: () async {
                          final report = await sync.syncNow();
                          if (!context.mounted) return;
                          StaffSnack.show(
                            context,
                            report.attempted == 0
                                ? 'Nothing to sync'
                                : 'Synced ${report.succeeded} of ${report.attempted}'
                                      '${report.conflicted > 0 ? ' · ${report.conflicted} conflicted' : ''}'
                                      '${report.failed > 0 ? ' · ${report.failed} failed' : ''}',
                          );
                        },
                      ),
                    ),
                    if (ops.any((o) => o.status == QueuedOpStatus.succeeded)) ...[
                      const SizedBox(width: 10),
                      PillButton(
                        label: 'Clear done',
                        variant: PillButtonVariant.outlined,
                        onPressed: sync.clearCompleted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                SectionHeader(title: 'Operations'),
                if (ops.isEmpty)
                  const EmptyState(
                    icon: Symbols.cloud_done_rounded,
                    title: 'Everything is synced',
                    text:
                        'Changes made offline are queued here in order, with your ID and device time.',
                  ),
                for (final op in ops) ...[
                  _OpTile(op: op),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                const AuditNote(
                  icon: Symbols.offline_bolt_rounded,
                  text:
                      'Operations replay in device-time order through /sync/batch; the server dedupes on the operation id.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OpTile extends StatelessWidget {
  const _OpTile({required this.op});
  final QueuedOperation op;

  static String kindLabel(String kind) => switch (kind) {
    SyncKinds.taskTransition => 'Task transition',
    SyncKinds.stepResult => 'Checklist step',
    SyncKinds.inventoryMovement => 'Stock movement',
    SyncKinds.taskAssign => 'Assignment',
    SyncKinds.notificationRead => 'Notification read',
    _ => kind,
  };

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final sync = context.syncStatus;
    final (String label, StatusChipTone tone, IconData icon) = switch (op
        .status) {
      QueuedOpStatus.pending => (
        'Pending',
        StatusChipTone.gold,
        Symbols.pending_rounded,
      ),
      QueuedOpStatus.syncing => (
        'Syncing',
        StatusChipTone.primary,
        Symbols.sync_rounded,
      ),
      QueuedOpStatus.succeeded => (
        'Applied',
        StatusChipTone.success,
        Symbols.check_circle_rounded,
      ),
      QueuedOpStatus.failed => (
        'Failed',
        StatusChipTone.error,
        Symbols.error_rounded,
      ),
      QueuedOpStatus.conflicted => (
        'Conflict',
        StatusChipTone.error,
        Symbols.sync_problem_rounded,
      ),
    };
    final needsAction =
        op.status == QueuedOpStatus.failed ||
        op.status == QueuedOpStatus.conflicted;
    return ListTileCard(
      borderColor: needsAction ? cs.error.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  op.label ?? kindLabel(op.kind),
                  style: context.text.titleMedium,
                ),
              ),
              StatusChip(label: label, tone: tone, icon: icon, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${kindLabel(op.kind)} · ${SparklingDates.hhmm(op.deviceTime)}'
            '${op.attempts > 0 ? ' · ${op.attempts} attempt${op.attempts == 1 ? '' : 's'}' : ''}',
            style: context.text.bodySmall,
          ),
          if (op.lastError != null) ...[
            const SizedBox(height: 6),
            Text(
              op.lastError!,
              style: SparklingTypography.bodyMedium.copyWith(color: cs.error),
            ),
          ],
          if (needsAction) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                if (op.status == QueuedOpStatus.failed)
                  PillButton(
                    label: 'Retry',
                    icon: Symbols.refresh_rounded,
                    variant: PillButtonVariant.tonal,
                    dense: true,
                    onPressed: () => sync.retry(op.clientOpId),
                  ),
                PillButton(
                  label: 'Discard',
                  icon: Symbols.delete_rounded,
                  variant: PillButtonVariant.outlinedError,
                  dense: true,
                  onPressed: () => sync.remove(op.clientOpId),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
