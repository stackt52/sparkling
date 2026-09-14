import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import 'walk_in_widgets.dart';

/// Colour tone for a plan (falls back to the tier).
PlanTone planTone(MembershipPlan plan) => plan.color == null
    ? PlanTone.forTier(tierKind(plan.tier))
    : PlanTone.forKey(plan.color);

/// The customer step's membership tile: "Gold · 3 of 4 washes left · renews
/// 9 Oct" or "No membership plan" with an **Enrol in a plan** hint; tapping
/// opens [showCustomerMembershipSheet]. A spinner shows while the summary
/// loads.
class CustomerMembershipTile extends StatelessWidget {
  const CustomerMembershipTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final MembershipSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final s = summary;
    if (s == null) {
      return ListTileCard(
        key: const ValueKey('customer-membership-loading'),
        leading: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        title: const Text('Membership'),
        subtitle: const Text('Checking plan…'),
      );
    }
    if (!s.hasMembership) {
      return ListTileCard(
        key: const ValueKey('customer-membership-none'),
        onTap: onTap,
        leading: Icon(Symbols.workspace_premium_rounded, color: cs.primary),
        title: const Text('No membership plan'),
        subtitle: const Text('Enrol at the counter — washes included from today'),
        trailing: PillButton(
          key: const ValueKey('enrol-cta'),
          label: 'Enrol',
          dense: true,
          icon: Symbols.add_rounded,
          onPressed: onTap,
        ),
      );
    }
    final allowances = s.allowances
        .map((a) => '${a.remaining} of ${a.quantity} ${a.nounFor.toLowerCase()}')
        .join(' · ');
    final renewal = s.isPastDue
        ? 'Payment due · benefits paused'
        : s.nextRenewalAt == null
        ? 'Ends ${s.membership!.currentPeriodEnd == null ? '' : SparklingDates.dayMonth(s.membership!.currentPeriodEnd!)}'
        : 'Renews ${SparklingDates.dayMonth(s.nextRenewalAt!)}';
    return ListTileCard(
      key: const ValueKey('customer-membership'),
      onTap: onTap,
      borderColor: s.isPastDue ? cs.error.withValues(alpha: 0.6) : null,
      leading: Icon(
        s.isPastDue ? Symbols.error_rounded : Symbols.workspace_premium_rounded,
        color: s.isPastDue ? cs.error : x.gold,
        fill: 1,
      ),
      title: Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: TierPill(
                tier: tierKind(s.tier),
                label: '${s.planName} member',
                icon: null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text('$allowances\n$renewal', maxLines: 2),
      trailing: Icon(Symbols.chevron_right_rounded, color: cs.onSurfaceVariant),
    );
  }
}

/// "Membership" sheet for a customer: plan card with allowances, renewal /
/// invoice state, **Record renewal payment** when an invoice is open and
/// **Enrol in a plan** for customers without one. Pops with the updated
/// summary after a write.
Future<MembershipSummary?> showCustomerMembershipSheet(
  BuildContext context, {
  required CustomerSummary customer,
  MembershipSummary? summary,
}) {
  return showModalBottomSheet<MembershipSummary>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MembershipSheet(customer: customer, initial: summary),
  );
}

class _MembershipSheet extends StatefulWidget {
  const _MembershipSheet({required this.customer, this.initial});
  final CustomerSummary customer;
  final MembershipSummary? initial;

  @override
  State<_MembershipSheet> createState() => _MembershipSheetState();
}

class _MembershipSheetState extends State<_MembershipSheet> {
  MembershipSummary? _summary;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.initial;
    if (_summary == null) _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.repositories.staff.customerMembership(
        widget.customer.id,
      );
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    }
  }

  Future<void> _enrol() async {
    final result = await showEnrolSheet(context, customer: widget.customer);
    if (result == null || !mounted) return;
    setState(() {
      _summary = result;
      _changed = true;
    });
  }

  Future<void> _recordPayment() async {
    final s = _summary;
    if (s == null || s.openInvoice == null) return;
    final method = await showModalBottomSheet<CounterPaymentMethod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Record ${Money.formatZar(s.openInvoice!.amountCents)} renewal',
              ),
              Text(
                '${s.openInvoice!.ref} · ${s.planName} · period from ${s.openInvoice!.periodStart == null ? '' : SparklingDates.dayMonth(s.openInvoice!.periodStart!)}',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: ctx.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final m in CounterPaymentMethod.values) ...[
                PillButton(
                  key: ValueKey('renewal-${m.db}'),
                  label: m.label,
                  icon: switch (m) {
                    CounterPaymentMethod.cash => Symbols.payments_rounded,
                    CounterPaymentMethod.cardTerminal => Symbols.contactless_rounded,
                    CounterPaymentMethod.eft => Symbols.account_balance_rounded,
                  },
                  variant: m == CounterPaymentMethod.cash
                      ? PillButtonVariant.filled
                      : PillButtonVariant.tonal,
                  expand: true,
                  onPressed: () => Navigator.of(ctx).pop(m),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
    if (method == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await context.repositories.staff
          .recordMembershipInvoicePayment(
            membershipId: s.membership!.id,
            invoiceId: s.openInvoice!.id,
            method: method,
            clientOpId: SparklingApi.newOpId(),
          );
      if (!mounted) return;
      StaffHaptics.success(context);
      StaffSnack.show(
        context,
        '${Money.formatZar(s.openInvoice!.amountCents)} ${method.label.toLowerCase()} recorded · ${s.planName} renewed.',
      );
      setState(() {
        _summary = updated;
        _changed = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        await showConflictDialog(context, e);
        await _load();
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final s = _summary;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed ? _summary : null);
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: '${widget.customer.firstName}\'s membership'),
                if (s == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!s.hasMembership) ...[
                  Text(
                    'No plan yet. Enrol ${widget.customer.firstName} at the counter — the plan is active immediately and the first wash can be booked now.',
                    style: SparklingTypography.bodyLarge.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillButton(
                    key: const ValueKey('sheet-enrol'),
                    label: 'Enrol in a plan',
                    icon: Symbols.workspace_premium_rounded,
                    expand: true,
                    minHeight: 54,
                    onPressed: _enrol,
                  ),
                ] else ...[
                  _PlanSummaryCard(summary: s),
                  const SizedBox(height: 12),
                  if (s.openInvoice != null) ...[
                    if (s.isPastDue)
                      const InfoBanner(
                        tone: InfoTone.warning,
                        icon: Symbols.pause_circle_rounded,
                        text: 'Benefits are paused until the renewal is paid.',
                        margin: EdgeInsets.only(bottom: 10),
                      ),
                    PillButton(
                      key: const ValueKey('record-renewal-payment'),
                      label:
                          'Record renewal payment · ${Money.formatZar(s.openInvoice!.amountCents)}',
                      icon: Symbols.point_of_sale_rounded,
                      expand: true,
                      minHeight: 54,
                      loading: _busy,
                      onPressed: _busy ? null : _recordPayment,
                    ),
                  ] else
                    Text(
                      'Nothing due. Included washes apply automatically when booking a covered service.',
                      style: SparklingTypography.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                PillButton(
                  label: 'Close',
                  variant: PillButtonVariant.outlined,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_changed ? _summary : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.summary});
  final MembershipSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final plan = s.plan;
    final tone = plan == null ? PlanTone.gold : planTone(plan);
    final p = PlanPalette.of(context, tone);
    final m = s.membership!;
    return PlanCard(
      key: const ValueKey('sheet-plan-card'),
      tone: tone,
      pillLabel: '${plan?.name ?? m.planCode} member',
      trailing: StatusChip(
        label: m.status.label,
        tone: s.isPastDue
            ? StatusChipTone.error
            : s.isActive
            ? StatusChipTone.success
            : StatusChipTone.neutral,
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in s.allowances) ...[
            AllowanceRing(
              remaining: a.remaining,
              quantity: a.quantity,
              size: 48,
              title: a.nounFor,
              caption: '${a.remaining} of ${a.quantity} left${a.resetLabel == null ? '' : ' · ${a.resetLabel}'}',
              color: p.accent,
              trackColor: p.track,
              foreground: p.foreground,
              mutedForeground: p.muted,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            [
              m.ref,
              if (s.nextRenewalAt != null) 'renews ${SparklingDates.dayMonth(s.nextRenewalAt!)}',
              m.paymentMethod.label.toLowerCase(),
            ].join(' · '),
            style: SparklingTypography.bodyMedium.copyWith(
              fontSize: 13,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// **Enrol in a plan** sheet: plan → options → cash / card terminal / EFT →
/// `POST /staff/customers/:id/membership` (queued offline as
/// `membership.enrol`). Pops with the new summary.
Future<MembershipSummary?> showEnrolSheet(
  BuildContext context, {
  required CustomerSummary customer,
}) {
  return showModalBottomSheet<MembershipSummary>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _EnrolSheet(customer: customer),
  );
}

class _EnrolSheet extends StatefulWidget {
  const _EnrolSheet({required this.customer});
  final CustomerSummary customer;

  @override
  State<_EnrolSheet> createState() => _EnrolSheetState();
}

class _EnrolSheetState extends State<_EnrolSheet> {
  Future<MembershipPlanList>? _plans;
  MembershipPlan? _plan;
  Map<String, String> _selections = const {};
  CounterPaymentMethod _method = CounterPaymentMethod.cash;
  bool _busy = false;
  final _opId = SparklingApi.newOpId();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _plans ??= context.repositories.membership.plans();
  }

  void _pick(MembershipPlan p) {
    StaffHaptics.tap(context);
    setState(() {
      _plan = p;
      _selections = p.defaultSelections();
    });
  }

  Future<void> _enrol() async {
    final plan = _plan;
    if (plan == null || !plan.selectionsValid(_selections)) return;
    setState(() => _busy = true);
    try {
      final summary = await context.repositories.staff.enrolMembership(
        EnrolMembershipInput(
          customerId: widget.customer.id,
          planCode: plan.code,
          selections: _selections,
          paymentMethod: _method,
          clientOpId: _opId,
        ),
      );
      if (!mounted) return;
      StaffHaptics.success(context);
      if (summary.pendingSync) {
        StaffSnack.queued(context, '${plan.name} enrolment');
      } else {
        StaffSnack.show(
          context,
          '${widget.customer.firstName} is now a ${plan.name} member · ${Money.formatZar(plan.monthlyFeeCents)} ${_method.label.toLowerCase()} recorded.',
        );
      }
      Navigator.of(context).pop(summary);
    } on ApiException catch (e) {
      if (!mounted) return;
      StaffHaptics.error(context);
      if (e.isConflict) {
        await showConflictDialog(context, e, title: 'Already a member');
        if (mounted) Navigator.of(context).pop();
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final plan = _plan;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SectionHeader(title: 'Enrol ${widget.customer.firstName} in a plan'),
          FutureBuilder<MembershipPlanList>(
            future: _plans,
            builder: (context, snap) {
              final list = snap.data;
              if (snap.hasError) {
                return Text(
                  ErrorState.messageFor(snap.error!),
                  style: TextStyle(color: cs.error),
                );
              }
              if (list == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in list.plans) ...[
                    PlanCard(
                      key: ValueKey('enrol-plan-${p.code}'),
                      tone: planTone(p),
                      title: p.name,
                      tagline: p.tagline,
                      selected: plan?.code == p.code,
                      padding: const EdgeInsets.all(16),
                      trailing: Text(
                        p.feeLabel,
                        style: SparklingTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () => _pick(p),
                      child: Text(
                        [
                          for (final g in p.groups)
                            g.entitlements.map((e) => e.label).join(g.isChooseOne ? ' or ' : ' and '),
                          if (p.discountNote != null) p.discountNote!,
                        ].join(' · '),
                        style: SparklingTypography.bodyMedium.copyWith(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
          if (plan != null) ...[
            for (final g in plan.chooseOneGroups) ...[
              SectionHeader(title: g.name),
              for (final e in g.entitlements) ...[
                RadioCard(
                  key: ValueKey('enrol-option-${e.code}'),
                  selected: _selections[g.code] == e.code,
                  onChanged: (_) {
                    StaffHaptics.tap(context);
                    setState(() => _selections = {..._selections, g.code: e.code});
                  },
                  radioPosition: RadioCardRadioPosition.trailing,
                  leading: Icon(Symbols.local_car_wash_rounded, color: cs.primary, fill: 1),
                  title: Text(e.label),
                  subtitle: Text(
                    '${e.code} · ${e.services.map((s) => s.name).join(' / ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            for (final g in plan.groups.where((g) => !g.isChooseOne)) ...[
              SectionHeader(title: g.name),
              for (final e in g.entitlements)
                ListTileCard(
                  leading: Icon(Symbols.check_circle_rounded, color: context.sparkling.success, fill: 1),
                  title: Text(e.label),
                  subtitle: Text(e.period.label),
                ),
              const SizedBox(height: 8),
            ],
            const SectionHeader(title: 'Paid at the counter'),
            Row(
              children: [
                for (final m in CounterPaymentMethod.values) ...[
                  Expanded(
                    child: ChoiceChip(
                      key: ValueKey('enrol-pay-${m.db}'),
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(m.label, textAlign: TextAlign.center),
                      ),
                      selected: _method == m,
                      onSelected: (_) => setState(() => _method = m),
                    ),
                  ),
                  if (m != CounterPaymentMethod.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),
            AuditNote(
              icon: Symbols.receipt_long_rounded,
              text:
                  '${Money.formatZar(plan.monthlyFeeCents)} is recorded under your name with a receipt; the plan is active immediately and renews monthly.',
            ),
            const SizedBox(height: 8),
            PillButton(
              key: const ValueKey('enrol-confirm'),
              label: 'Enrol · ${Money.formatZar(plan.monthlyFeeCents)} ${_method.label.toLowerCase()}',
              icon: Symbols.workspace_premium_rounded,
              expand: true,
              minHeight: 56,
              loading: _busy,
              onPressed: _busy || !plan.selectionsValid(_selections) ? null : _enrol,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Pick a plan to choose its options.',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
