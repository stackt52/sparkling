import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import 'blocked_reason_sheet.dart';
import 'handover_sheet.dart';
import 'step_tiles.dart';

/// Full-screen checklist route (phone).
class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({super.key, required this.workOrderId});
  final String workOrderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ChecklistView(workOrderId: workOrderId)),
    );
  }
}

/// Checklist execution (2b): WO header + 48px ring, done / current /
/// upcoming steps, supervisor verification gate (STF-033), offline note
/// (STF-034). Every mutation goes through the repository (queued offline);
/// 409s open the conflict dialog (STF-035).
class ChecklistView extends StatefulWidget {
  const ChecklistView({
    super.key,
    required this.workOrderId,
    this.embedded = false,
    this.onClose,
  });

  final String workOrderId;

  /// Rendered inside the tablet detail pane (no back tile).
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<ChecklistView> {
  StreamSubscription<WorkOrderDetail>? _sub;
  WorkOrderDetail? _detail;
  Object? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= _subscribe();
  }

  StreamSubscription<WorkOrderDetail> _subscribe() {
    _sub?.cancel();
    return context.repositories.staff
        .watchWorkOrder(widget.workOrderId)
        .listen(
          (d) {
            if (!mounted) return;
            setState(() {
              _detail = d;
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
    super.dispose();
  }

  String _draftKey(String stepKey) => 'step:${widget.workOrderId}:$stepKey';

  Future<T?> _mutate<T>(Future<T> Function() body, {String? queued}) async {
    setState(() => _busy = true);
    try {
      return await runMutation(
        context,
        body,
        queuedLabel: queued,
        onConflict: _refresh,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeStep(ChecklistStep step, StepInputValue input) async {
    final staff = context.repositories.staff;
    final result = await _mutate(
      () => staff.submitStep(
        widget.workOrderId,
        step.key,
        StepResultInput(
          status: StepStatus.done,
          clientOpId: SparklingApi.newOpId(),
          value: input.value,
          attachmentId: input.attachmentId,
        ),
      ),
      queued: 'Step "${step.title}"',
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      await context.repositories.drafts.delete(_draftKey(step.key));
    }
  }

  Future<void> _blockStep(ChecklistStep step) async {
    final detail = _detail;
    if (detail == null) return;
    final reason = await showBlockedReasonSheet(context, stepTitle: step.title);
    if (reason == null || !mounted) return;
    final staff = context.repositories.staff;
    final task = detail.task;
    final result = await _mutate(() async {
      await staff.submitStep(
        widget.workOrderId,
        step.key,
        StepResultInput(
          status: StepStatus.blocked,
          clientOpId: SparklingApi.newOpId(),
          note: reason,
        ),
      );
      if (task != null && task.status.canTransitionTo(WorkStatus.blocked)) {
        await staff.transitionTask(
          task,
          TaskTransitionInput(
            to: WorkStatus.blocked,
            reason: reason,
            clientOpId: SparklingApi.newOpId(),
          ),
        );
      }
    }, queued: 'Block "${step.title}"');
    if (result != null && mounted) StaffHaptics.error(context);
  }

  Future<void> _transition(WorkStatus to, {String? reason}) async {
    final task = _detail?.task;
    if (task == null) return;
    final result = await _mutate(
      () => context.repositories.staff.transitionTask(
        task,
        TaskTransitionInput(
          to: to,
          reason: reason,
          clientOpId: SparklingApi.newOpId(),
        ),
      ),
      queued: '${task.ref} → ${to.label}',
    );
    if (result != null && mounted) StaffHaptics.success(context);
  }

  /// Vehicle hand-over: OTP sheet → keys released (stream refreshes the
  /// banner with `collected_at`).
  Future<void> _handover(WorkOrderDetail detail) async {
    final wo = detail.workOrder;
    final card = detail.task?.workOrder;
    final result = await showHandoverSheet(
      context,
      workOrderId: wo.id,
      ref: wo.ref,
      customerName: wo.customerName ?? card?.customerName,
      vehicleLabel: wo.vehicleRegistration ?? card?.vehicle?.registrationNo,
    );
    if (result != null && mounted) {
      StaffSnack.show(context, '${wo.ref}: keys released');
    }
  }

  /// Supervisor sign-off: completes the task if needed, records the
  /// supervisor step, then transitions to verified (STF-033).
  Future<void> _verify(ChecklistStep step) async {
    final detail = _detail;
    final task = detail?.task;
    if (detail == null || task == null) return;
    final staff = context.repositories.staff;
    final result = await _mutate(() async {
      var current = task;
      if (current.status == WorkStatus.inProgress) {
        current = await staff.transitionTask(
          current,
          TaskTransitionInput(
            to: WorkStatus.completed,
            clientOpId: SparklingApi.newOpId(),
          ),
        );
      }
      await staff.submitStep(
        widget.workOrderId,
        step.key,
        StepResultInput(
          status: StepStatus.done,
          clientOpId: SparklingApi.newOpId(),
          value: true,
        ),
      );
      return staff.transitionTask(
        current,
        TaskTransitionInput(
          to: WorkStatus.verified,
          clientOpId: SparklingApi.newOpId(),
        ),
      );
    }, queued: 'Verify ${task.ref}');
    if (result != null && mounted) StaffHaptics.success(context);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _detail != null
        ? AsyncSnapshot<WorkOrderDetail>.withData(
            ConnectionState.active,
            _detail!,
          )
        : _error != null
        ? AsyncSnapshot<WorkOrderDetail>.withError(
            ConnectionState.active,
            _error!,
          )
        : const AsyncSnapshot<WorkOrderDetail>.waiting();

    return AsyncView<WorkOrderDetail>(
      snapshot: snapshot,
      onRetry: _refresh,
      builder: (context, detail) => _body(context, detail),
    );
  }

  Widget _body(BuildContext context, WorkOrderDetail detail) {
    final cs = context.colors;
    final session = context.session;
    final wo = detail.workOrder;
    final task = detail.task;
    final status = task?.status ?? wo.status;
    final steps = detail.steps;
    final current = detail.currentStep;
    final progress = detail.progress;
    final card = task?.workOrder;
    final serviceName = wo.serviceName ?? card?.serviceName;
    final templateName = detail.template?.name;
    final title = serviceName != null
        ? '$serviceName checklist'
        : templateName == null
        ? 'Checklist'
        : templateName.toLowerCase().endsWith('checklist')
        ? templateName
        : '$templateName checklist';
    final meta = [
      wo.ref,
      wo.vehicleRegistration ?? card?.vehicle?.registrationNo,
      wo.bay ?? card?.bay,
    ].whereType<String>().join('  ·  ');
    final interactive =
        status == WorkStatus.inProgress ||
        status == WorkStatus.completed ||
        status == WorkStatus.blocked;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Row(
          children: [
            if (!widget.embedded || widget.onClose != null) ...[
              IconTileButton(
                icon: widget.embedded
                    ? Symbols.close_rounded
                    : Symbols.arrow_back_rounded,
                tooltip: widget.embedded ? 'Close' : 'Back',
                onPressed:
                    widget.onClose ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SparklingTypography.headlineMedium.copyWith(
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: SparklingTypography.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ProgressRing(
              value: progress.fraction,
              size: 48,
              strokeWidth: 5,
              color: cs.primary,
              trackColor: cs.surfaceContainerHigh,
              label: '${progress.stepsDone}/${progress.stepCount}',
              semanticLabel:
                  '${progress.stepsDone} of ${progress.stepCount} steps done',
            ),
          ],
        ),
      ),
      const LiveOfflineBanner(),
    ];

    // Status banners.
    if (task != null) {
      Widget? banner;
      switch (status) {
        case WorkStatus.queued:
        case WorkStatus.assigned:
          banner = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoBanner(
                tone: InfoTone.azure,
                icon: Symbols.play_circle_rounded,
                title: 'Not started',
                text: status == WorkStatus.queued
                    ? 'Claim this task to start the checklist — the timer starts now.'
                    : 'Start the checklist when the vehicle is in the bay.',
              ),
              const SizedBox(height: 10),
              PillButton(
                label: status == WorkStatus.queued
                    ? 'Claim & start'
                    : 'Start task',
                icon: Symbols.play_arrow_rounded,
                expand: true,
                minHeight: 56,
                loading: _busy,
                onPressed: () => _transition(WorkStatus.inProgress),
              ),
            ],
          );
        case WorkStatus.blocked:
          banner = InfoBanner(
            tone: InfoTone.error,
            icon: Symbols.block_rounded,
            bordered: true,
            title: 'Blocked',
            text: task.blockedReason ?? wo.blockedReason ?? 'Waiting',
            actionLabel: 'Resume',
            onAction: _busy ? null : () => _transition(WorkStatus.inProgress),
          );
        case WorkStatus.completed:
          banner = const InfoBanner(
            tone: InfoTone.success,
            title: 'Task completed',
            text: 'Awaiting supervisor verification before the vehicle is released.',
          );
        case WorkStatus.verified:
          banner = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoBanner(
                tone: InfoTone.success,
                icon: Symbols.verified_rounded,
                title: 'Verified',
                text:
                    'Signed off${wo.verifiedAt == null ? '' : ' at ${SparklingDates.hhmm(wo.verifiedAt!)}'} · customer notified with their collection OTP.',
              ),
              const SizedBox(height: 10),
              _HandoverCard(
                collectedAt: wo.collectedAt,
                busy: _busy,
                onHandover: () => _handover(detail),
              ),
            ],
          );
        case WorkStatus.cancelled:
          banner = const InfoBanner(
            tone: InfoTone.warning,
            title: 'Cancelled',
            text: 'This work order was cancelled.',
          );
        case WorkStatus.inProgress:
          banner = null;
      }
      if (banner != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: banner,
          ),
        );
      }
    }

    for (final step in steps) {
      final result = detail.resultFor(step.key);
      Widget tile;
      if (result?.isDone ?? false) {
        tile = DoneStepTile(step: step, result: result!);
      } else if (step.isSupervisorVerify) {
        final isCurrent = current?.key == step.key;
        tile = SupervisorStepCard(
          step: step,
          unlocked: detail.requiredStepsPassed && isCurrent && interactive,
          canSupervise: session.canSupervise,
          taskStatus: status,
          busy: _busy,
          onVerify: () => _verify(step),
          onCompleteTask: () => _transition(WorkStatus.completed),
        );
      } else if (current?.key == step.key && status == WorkStatus.inProgress) {
        tile = CurrentStepCard(
          key: ValueKey('current-${step.key}'),
          step: step,
          busy: _busy,
          blockedNote: result?.isBlocked ?? false ? result?.note : null,
          initialDraft: context.repositories.drafts
              .load(_draftKey(step.key))?['value']
              ?.toString(),
          onDraftChanged: (v) => context.repositories.drafts.save(
            _draftKey(step.key),
            {'value': v},
          ),
          onComplete: (v) => _completeStep(step, v),
          onBlock: () => _blockStep(step),
        );
      } else {
        tile = UpcomingStepTile(step: step, locked: detail.isStepLocked(step));
      }
      children.add(
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: tile),
      );
    }

    // Technician "Complete task" when required steps pass and there is no
    // supervisor step in the template.
    final hasSupervisorStep = steps.any((s) => s.isSupervisorVerify);
    if (!hasSupervisorStep &&
        detail.requiredStepsPassed &&
        status == WorkStatus.inProgress &&
        task != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: PillButton(
            label: 'Complete task',
            icon: Symbols.task_alt_rounded,
            expand: true,
            minHeight: 56,
            loading: _busy,
            onPressed: () => _transition(WorkStatus.completed),
          ),
        ),
      );
    }

    children.add(
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: AuditNote(
          icon: Symbols.offline_bolt_rounded,
          text: 'Works offline — steps queue with your ID and timestamps, then sync in order.',
        ),
      ),
    );

    return ListView(padding: EdgeInsets.zero, children: children);
  }
}

/// "Hand over vehicle" CTA on a verified work order, or the released state
/// once the customer's OTP was verified.
class _HandoverCard extends StatelessWidget {
  const _HandoverCard({
    required this.collectedAt,
    required this.onHandover,
    this.busy = false,
  });

  final DateTime? collectedAt;
  final VoidCallback onHandover;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final at = collectedAt;
    if (at != null) {
      return ListTileCard(
        key: const ValueKey('handover-collected'),
        borderColor: x.success.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: x.success, shape: BoxShape.circle),
          child: Icon(Symbols.check_rounded, color: x.onSuccess, weight: 700),
        ),
        title: Text('Keys released · collected at ${SparklingDates.hhmm(at)}'),
        subtitle: const Text('Collection OTP verified at the counter.'),
      );
    }
    return ListTileCard(
      key: const ValueKey('handover-card'),
      borderColor: cs.primary.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Symbols.key_rounded, color: cs.primary, fill: 1),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Awaiting collection',
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ask the customer for their 5-digit OTP to release the keys.',
            style: SparklingTypography.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Hand over vehicle',
            icon: Symbols.key_rounded,
            expand: true,
            minHeight: 56,
            onPressed: busy ? null : onHandover,
          ),
        ],
      ),
    );
  }
}
