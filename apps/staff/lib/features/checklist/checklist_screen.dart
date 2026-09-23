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

  /// Quotation work orders: the quote carries the amount due / payment
  /// (`GET /quotations/:id` → `payment`, `amount_due_cents`).
  StreamSubscription<List<Quotation>>? _quoteSub;
  Quotation? _quote;
  String? _quoteId;

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
            _watchQuote(d.workOrder);
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = e);
          },
        );
  }

  void _refresh() => setState(() {
    _quoteId = null;
    _sub = _subscribe();
  });

  void _watchQuote(WorkOrder wo) {
    final id = wo.quotationId;
    if (id == null || _quoteId == id) return;
    _quoteId = id;
    _quoteSub?.cancel();
    final staff = context.repositories.staff;
    staff.quotation(id).then((q) {
      if (mounted && q.id == _quoteId) setState(() => _quote = q);
    }, onError: (Object _) {});
    _quoteSub = staff
        .watchQuotations(outletId: wo.outletId)
        .listen((list) {
          final q = list.where((q) => q.id == id).firstOrNull;
          if (q != null && mounted) setState(() => _quote = q);
        }, onError: (Object _) {});
  }

  /// Counter payment for the quotation behind this work order (same cash
  /// step as the hand-over sheet), then the quote shows "Paid · RCP-…".
  Future<void> _recordQuotePayment() async {
    final quote = _quote;
    if (quote == null) return;
    final staff = context.repositories.staff;
    final payment = await showRecordCashSheet(context, quotation: quote);
    if (payment == null || !mounted) return;
    StaffSnack.show(
      context,
      '${Money.formatZar(payment.amountCents)} recorded for ${quote.ref}'
      '${payment.receiptNo == null ? '' : ' · ${payment.receiptNo}'}',
    );
    try {
      final fresh = await staff.quotation(quote.id);
      if (mounted) setState(() => _quote = fresh);
    } catch (_) {
      // The quotations stream refreshes the chip when it emits.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _quoteSub?.cancel();
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
    // Photo proof is uploaded first (needs a connection); the step is then
    // submitted with the server-issued attachment id.
    String? attachmentId = input.attachmentId;
    if (input.photoPaths.isNotEmpty) {
      setState(() => _busy = true);
      try {
        Attachment? last;
        for (final path in input.photoPaths) {
          last = await staff.uploadStepPhoto(
            widget.workOrderId,
            stepKey: step.key,
            path: path,
          );
        }
        attachmentId = last?.id;
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        StaffSnack.show(
          context,
          e.isNetwork
              ? 'The photo needs a connection to upload — reconnect and '
                    'complete the step again.'
              : e.message,
        );
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _busy = false);
        StaffSnack.show(context, "Couldn't upload the photo — try again.");
        return;
      }
    }
    if (!mounted) return;
    final result = await _mutate(
      () => staff.submitStep(
        widget.workOrderId,
        step.key,
        StepResultInput(
          status: StepStatus.done,
          clientOpId: SparklingApi.newOpId(),
          value: input.value,
          attachmentId: attachmentId,
        ),
      ),
      queued: 'Step "${step.title}"',
    );
    if (result != null && mounted) {
      StaffHaptics.success(context);
      StaffSnack.show(
        context,
        result.pendingSync
            ? 'Step "${step.title}" saved — will sync when online'
            : 'Step "${step.title}" completed',
      );
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
      booking: wo.booking ?? card?.booking,
      quotation: _quote,
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
    final checkedInAt = wo.checkedInAt ?? card?.checkedInAt;
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
                  if (checkedInAt != null) ...[
                    const SizedBox(height: 6),
                    StatusChip(
                      key: const ValueKey('checked-in-chip'),
                      label: 'Checked in ${SparklingDates.hhmm(checkedInAt)}',
                      tone: StatusChipTone.success,
                      icon: Symbols.login_rounded,
                      dense: true,
                    ),
                  ] else if (status.isOpen) ...[
                    const SizedBox(height: 6),
                    const StatusChip(
                      key: ValueKey('awaiting-checkin-chip'),
                      label: 'Awaiting check-in',
                      tone: StatusChipTone.warning,
                      icon: Symbols.login_rounded,
                      dense: true,
                    ),
                  ],
                  if (wo.isCashOnCollection || (card?.isCashOnCollection ?? false)) ...[
                    const SizedBox(height: 6),
                    StatusChip(
                      key: const ValueKey('cash-on-collection-chip'),
                      label: wo.isCashDue || (card?.isCashDue ?? false)
                          ? 'Cash on collection · ${Money.formatZar((wo.booking ?? card!.booking!).totalCents)} due'
                          : 'Cash on collection · paid',
                      tone: wo.isCashDue || (card?.isCashDue ?? false)
                          ? StatusChipTone.warning
                          : StatusChipTone.success,
                      icon: Symbols.payments_rounded,
                      dense: true,
                    ),
                  ],
                  // Quotation work order: the quoted total is settled at the
                  // counter — "Quote · R x due" until recorded.
                  if (_quote case final quote?
                      when quote.isPaymentDue || quote.isPaid) ...[
                    const SizedBox(height: 6),
                    StatusChip(
                      key: const ValueKey('quote-payment-chip'),
                      label: quote.isPaid
                          ? 'Paid · ${quote.payment!.receiptNo ?? 'receipt pending'}'
                          : 'Quote · ${Money.formatZar(quote.amountDueCents)} due',
                      tone: quote.isPaid
                          ? StatusChipTone.success
                          : StatusChipTone.warning,
                      icon: Symbols.payments_rounded,
                      dense: true,
                    ),
                  ],
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
                cashDueCents: wo.isCashDue
                    ? wo.booking!.totalCents
                    : (card?.isCashDue ?? false)
                    ? card!.booking!.totalCents
                    : (_quote?.isPaymentDue ?? false)
                    ? _quote!.amountDueCents
                    : null,
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

    // Accepted-quote job still to be settled at the counter.
    if (_quote case final quote? when quote.isPaymentDue) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: _QuotePaymentCard(
            quotation: quote,
            busy: _busy,
            onRecord: _recordQuotePayment,
          ),
        ),
      );
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

/// "Quote · R x due" on a quotation work order with **Record cash payment**
/// (the hand-over sheet's cash step, targeting the quotation).
class _QuotePaymentCard extends StatelessWidget {
  const _QuotePaymentCard({
    required this.quotation,
    required this.onRecord,
    this.busy = false,
  });

  final Quotation quotation;
  final VoidCallback onRecord;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final q = quotation;
    return ListTileCard(
      key: const ValueKey('quote-payment-card'),
      borderColor: x.onWarningContainer.withValues(alpha: 0.45),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Symbols.payments_rounded, color: x.onWarningContainer, fill: 1),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quote · ${Money.formatZar(q.amountDueCents)} due',
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
            '${q.ref} is settled at the counter — record the cash before the keys are released. A receipt is issued and the customer notified.',
            style: SparklingTypography.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          PillButton(
            key: const ValueKey('quote-record-cash'),
            label: 'Record cash payment',
            icon: Symbols.point_of_sale_rounded,
            variant: PillButtonVariant.tonal,
            expand: true,
            minHeight: 52,
            onPressed: busy ? null : onRecord,
          ),
        ],
      ),
    );
  }
}

/// "Hand over vehicle" CTA on a verified work order, or the released state
/// once the customer's OTP was verified.
class _HandoverCard extends StatelessWidget {
  const _HandoverCard({
    required this.collectedAt,
    required this.onHandover,
    this.cashDueCents,
    this.busy = false,
  });

  final DateTime? collectedAt;
  final VoidCallback onHandover;

  /// Cash on collection still to be recorded (amber line + first step of
  /// the hand-over sheet).
  final int? cashDueCents;
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
          if (cashDueCents != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('handover-cash-due-line'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: x.warningContainer,
                borderRadius: BorderRadius.circular(SparklingShapes.tile),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.payments_rounded,
                    size: 20,
                    color: x.onWarningContainer,
                    fill: 1,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cash due · ${Money.formatZar(cashDueCents!)} — take the cash and record it before the OTP.',
                      style: SparklingTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: x.onWarningContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
