import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Task card (2a/2g): priority chip + mono WO ref + status chip, title,
/// vehicle + bay in mono, checklist progress bar and a ≥48px primary action
/// with a timer tile. Blocked tasks get an error border and reason line.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onOpen,
    this.onStart,
    this.selected = false,
  });

  final Task task;

  /// Open the checklist (container-transform on phones, detail pane on tablet).
  final VoidCallback onOpen;

  /// Start / claim a queued or assigned task (transition → in_progress).
  final VoidCallback? onStart;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final wo = task.workOrder;
    final status = task.status;
    final blocked = status == WorkStatus.blocked;
    final reg = wo?.vehicle?.registrationNo;
    final detail = [
      ?reg,
      wo?.bay ?? (status == WorkStatus.queued ? 'awaiting arrival' : null),
    ].whereType<String>().join('  ·  ');
    final progress = wo?.progress;
    final showProgress =
        progress != null &&
        progress.stepCount > 0 &&
        (status == WorkStatus.inProgress || status == WorkStatus.assigned);

    return ListTileCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      borderColor: blocked
          ? cs.error.withValues(alpha: 0.55)
          : (selected ? cs.primary : null),
      borderWidth: selected && !blocked ? 2 : 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PriorityChip(priority: task.priority.clamp(1, 3)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.ref,
                  style: SparklingTypography.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(context),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            wo?.title.isNotEmpty == true ? wo!.title : task.title,
            style: SparklingTypography.titleLarge.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detail,
              style: SparklingTypography.mono(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (blocked) ...[
            const SizedBox(height: 6),
            Text(
              'Waiting: ${task.blockedReason ?? wo?.blockedReason ?? 'blocked'}',
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 14,
                color: cs.error,
              ),
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: LinearLevelBar.progress(value: progress.fraction)),
                const SizedBox(width: 14),
                Text(
                  progress.label,
                  style: SparklingTypography.labelLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ],
          if (status == WorkStatus.inProgress) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Continue checklist',
                    expand: true,
                    minHeight: 56,
                    onPressed: onOpen,
                  ),
                ),
                const SizedBox(width: 12),
                _TimerTile(task: task),
              ],
            ),
          ] else if (status == WorkStatus.assigned ||
              status == WorkStatus.queued) ...[
            if (onStart != null) ...[
              const SizedBox(height: 16),
              PillButton(
                label: status == WorkStatus.queued
                    ? 'Claim & start'
                    : 'Start checklist',
                icon: Symbols.play_arrow_rounded,
                variant: PillButtonVariant.tonal,
                expand: true,
                minHeight: 52,
                onPressed: onStart,
              ),
            ],
          ] else if (status.isDone && task.completedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${status.label} ${SparklingDates.hhmm(task.completedAt!)}'
              '${task.assigneeName == null ? '' : ' · ${task.assigneeName}'}',
              style: SparklingTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context) {
    final wo = task.workOrder;
    switch (task.status) {
      case WorkStatus.inProgress:
        return const StatusChip(
          label: 'In progress',
          tone: StatusChipTone.primary,
          dot: true,
        );
      case WorkStatus.blocked:
        return const StatusChip(
          label: 'Blocked',
          tone: StatusChipTone.error,
          icon: Symbols.block_rounded,
        );
      case WorkStatus.queued:
      case WorkStatus.assigned:
        final at = wo?.slotStart ?? wo?.etaAt ?? task.dueAt;
        return StatusChip(
          label: at == null
              ? task.status.label
              : '${task.status.label} · ${SparklingDates.hhmm(at)}',
          tone: StatusChipTone.neutral,
        );
      case WorkStatus.completed:
        return const StatusChip(
          label: 'Completed',
          tone: StatusChipTone.success,
          icon: Symbols.check_rounded,
        );
      case WorkStatus.verified:
        return const StatusChip(
          label: 'Verified',
          tone: StatusChipTone.success,
          icon: Symbols.verified_rounded,
        );
      case WorkStatus.cancelled:
        return const StatusChip(label: 'Cancelled');
    }
  }
}

/// 56px tile showing `task.elapsed()`; ticks every 30 s while in progress.
class _TimerTile extends StatefulWidget {
  const _TimerTile({required this.task});
  final Task task;

  @override
  State<_TimerTile> createState() => _TimerTileState();
}

class _TimerTileState extends State<_TimerTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String format(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final elapsed = widget.task.elapsed();
    return Semantics(
      label: 'Elapsed ${format(elapsed)}',
      child: Container(
        width: 64,
        height: 56,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(SparklingShapes.tile),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.timer_rounded, size: 20, color: cs.onSurface),
            const SizedBox(height: 2),
            Text(
              format(elapsed),
              style: SparklingTypography.mono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
