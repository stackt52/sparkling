import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'membership_widgets.dart';
import 'points_section.dart';
import 'subscribe_screen.dart';

/// Membership tab (docs/MEMBERSHIPS.md "Customer app"): the member's plan
/// card with allowance rings, renewal / invoice state and "Pay now", change
/// option / change plan / cancel; non-members see the three plans with the
/// option picker → sandbox payment → activated. Points balance, rewards and
/// the ledger stay below as a secondary section.
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  Stream<MembershipSummary>? _membership;
  Future<MembershipPlanList>? _plans;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_membership == null) _init();
  }

  void _init() {
    final repos = context.repos;
    _membership = repos.membership.watchMe();
    _plans = repos.membership.plans();
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payNow(MembershipSummary s) => _run(() async {
    final repos = context.repos;
    final intent = await repos.membership.payInvoice(s.openInvoice!.id);
    final paid = await repos.customer.confirmSandboxPayment(intent.payment.id);
    if (!mounted) return;
    AppHaptics.success(context);
    showSnack(
      context,
      paid.status.isVerified
          ? '${Money.formatZar(paid.amountCents)} paid · your ${s.planName} membership is renewed.'
          : 'Payment is ${paid.status.label.toLowerCase()} — we will update your membership when the provider confirms.',
    );
  });

  Future<void> _changeOptions(MembershipSummary s) async {
    final plan = s.plan;
    if (plan == null) return;
    final picked = await showChangeOptionsSheet(
      context,
      plan: plan,
      current: s.selections,
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      await context.repos.membership.changeSelections(picked);
      if (!mounted) return;
      AppHaptics.success(context);
      showSnack(context, 'Options updated for this month.');
    });
  }

  Future<void> _changePlan(MembershipSummary s) async {
    final plans = await _plans;
    if (plans == null || !mounted) return;
    final target = await showModalBottomSheet<MembershipPlan>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Change plan'),
              Text(
                'Upgrades apply now (you pay the new fee today); downgrades apply at your next renewal.',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: ctx.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final p in plans.plans) ...[
                PlanOfferCard(
                  plan: p,
                  current: p.code == s.planCode,
                  ctaLabel: p.monthlyFeeCents > (s.plan?.monthlyFeeCents ?? 0)
                      ? 'Upgrade to ${p.name}'
                      : 'Switch to ${p.name} at renewal',
                  onChoose: () => Navigator.of(ctx).pop(p),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    context.push(
      Routes.membershipSubscribe,
      extra: SubscribeArgs(plan: target, current: s),
    );
  }

  Future<void> _cancel(MembershipSummary s) async {
    final atPeriodEnd = await showCancelMembershipSheet(context, summary: s);
    if (atPeriodEnd == null || !mounted) return;
    await _run(() async {
      final after = await context.repos.membership.cancel(
        atPeriodEnd: atPeriodEnd,
      );
      if (!mounted) return;
      showSnack(
        context,
        after.hasMembership
            ? 'Your membership ends on ${SparklingDates.dayMonth(after.membership!.currentPeriodEnd!)}.'
            : 'Membership cancelled. You are back on Silver — rejoin any time.',
      );
    });
  }

  void _subscribe(MembershipPlan plan) {
    AppHaptics.light(context);
    context.push(Routes.membershipSubscribe, extra: SubscribeArgs(plan: plan));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => setState(_init),
          child: StreamBuilder<MembershipSummary>(
            stream: _membership,
            builder: (context, snap) {
              final s = snap.data;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text(
                    'Membership',
                    style: SparklingTypography.headlineLarge.copyWith(
                      fontSize: 30,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (snap.hasError && s == null)
                    ErrorView(
                      error: snap.error,
                      compact: true,
                      onRetry: () => setState(_init),
                    )
                  else if (s == null)
                    const HeroCard.gold(
                      child: SizedBox(height: 150, child: LoadingView()),
                    )
                  else if (s.hasMembership)
                    _MemberView(
                      summary: s,
                      busy: _busy,
                      onPayNow: () => _payNow(s),
                      onChangeOptions: () => _changeOptions(s),
                      onChangePlan: () => _changePlan(s),
                      onCancel: () => _cancel(s),
                    )
                  else
                    _PlansView(plans: _plans!, onChoose: _subscribe),
                  const SizedBox(height: 26),
                  const PointsSection(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MemberView extends StatelessWidget {
  const _MemberView({
    required this.summary,
    required this.busy,
    required this.onPayNow,
    required this.onChangeOptions,
    required this.onChangePlan,
    required this.onCancel,
  });

  final MembershipSummary summary;
  final bool busy;
  final VoidCallback onPayNow;
  final VoidCallback onChangeOptions;
  final VoidCallback onChangePlan;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final s = summary;
    final ending = s.membership?.cancelAtPeriodEnd ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MemberPlanCard(summary: s, onPayNow: onPayNow, paying: busy),
        const SizedBox(height: 12),
        if (s.isPastDue)
          InfoBanner(
            tone: InfoTone.warning,
            icon: Symbols.pause_circle_rounded,
            title: 'Benefits paused',
            text:
                'Your renewal of ${Money.formatZar(s.openInvoice?.amountCents ?? 0)} is outstanding — pay now to restore your washes and discounts.',
            margin: const EdgeInsets.only(bottom: 12),
          )
        else if (s.isPending)
          const InfoBanner(
            tone: InfoTone.info,
            icon: Symbols.hourglass_top_rounded,
            text: 'Your membership activates as soon as the first payment is confirmed.',
            margin: EdgeInsets.only(bottom: 12),
          )
        else if (ending)
          InfoBanner(
            tone: InfoTone.info,
            icon: Symbols.event_busy_rounded,
            text:
                'Not renewing — benefits end on ${SparklingDates.dayMonth(s.membership!.currentPeriodEnd!)}.',
            margin: const EdgeInsets.only(bottom: 12),
          ),
        if (s.invoices.isNotEmpty)
          Text(
            'Last invoice ${s.invoices.first.ref} · ${Money.formatZar(s.invoices.first.amountCents)} · ${s.invoices.first.status.label.toLowerCase()}',
            style: SparklingTypography.bodyMedium.copyWith(
              fontSize: 13.5,
              color: cs.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (s.plan?.chooseOneGroups.isNotEmpty ?? false) ...[
              Expanded(
                child: PillButton(
                  key: const ValueKey('change-options'),
                  label: 'Change option',
                  icon: Symbols.tune_rounded,
                  variant: PillButtonVariant.tonal,
                  expand: true,
                  onPressed: busy || !s.isActive ? null : onChangeOptions,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: PillButton(
                key: const ValueKey('change-plan'),
                label: 'Change plan',
                icon: Symbols.swap_vert_rounded,
                variant: PillButtonVariant.outlined,
                expand: true,
                onPressed: busy || !s.isActive ? null : onChangePlan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('cancel-membership'),
            onPressed: busy || ending ? null : onCancel,
            icon: const Icon(Symbols.cancel_rounded, size: 18),
            label: Text(ending ? 'Cancellation scheduled' : 'Cancel membership'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ),
      ],
    );
  }
}

class _PlansView extends StatelessWidget {
  const _PlansView({required this.plans, required this.onChoose});
  final Future<MembershipPlanList> plans;
  final ValueChanged<MembershipPlan> onChoose;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a plan',
          style: SparklingTypography.headlineSmall.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Monthly washes included, a discount on other services and a higher points rate. Cancel any time.',
          style: SparklingTypography.bodyMedium.copyWith(
            fontSize: 14,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        AsyncView<MembershipPlanList>(
          future: plans,
          builder: (context, list) => Column(
            children: [
              for (final p in list.plans) ...[
                PlanOfferCard(plan: p, onChoose: () => onChoose(p)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
