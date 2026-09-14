import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'membership_widgets.dart';

/// `/membership/subscribe` arguments: the plan to join, or — when [current]
/// is set — the plan to change to (upgrade now / downgrade at renewal).
class SubscribeArgs {
  const SubscribeArgs({required this.plan, this.current});
  final MembershipPlan plan;
  final MembershipSummary? current;

  bool get isChange => current?.hasMembership ?? false;

  /// Upgrade = higher fee than the current plan → paid now.
  bool get isUpgrade =>
      isChange && plan.monthlyFeeCents > (current!.plan?.monthlyFeeCents ?? 0);
}

/// Plan option picker → sandbox payment → activated (docs/MEMBERSHIPS.md).
/// Mirrors the booking payment screen: summary card, the `choose_one`
/// options as radio cards, the tokenised payment methods and one CTA
/// ("Pay R 295 securely"). `POST /memberships` returns the pending
/// membership + first invoice + payment intent; the sandbox confirm activates
/// it. For a downgrade nothing is paid — the switch is scheduled.
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key, required this.args});

  final SubscribeArgs args;

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  late Map<String, String> _selections;
  Future<List<PaymentMethod>>? _methods;
  String? _methodId;
  bool _busy = false;
  String? _stage;

  /// Stable per screen so a retried submit is idempotent.
  final _opId = SparklingApi.newOpId();

  MembershipPlan get plan => widget.args.plan;
  bool get _paysNow => !widget.args.isChange || widget.args.isUpgrade;

  @override
  void initState() {
    super.initState();
    _selections = {
      ...plan.defaultSelections(),
      // Keep the current choice when the same group code exists (e.g. washes).
      for (final e in (widget.args.current?.selections ?? const {}).entries)
        if (plan.group(e.key)?.entitlement(e.value) != null) e.key: e.value,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _methods ??= _loadMethods();
  }

  Future<List<PaymentMethod>> _loadMethods() async {
    final methods = await context.repos.customer.paymentMethods();
    if (mounted && _methodId == null && methods.isNotEmpty) {
      _methodId = (methods.where((m) => m.isDefault).firstOrNull ?? methods.first).id;
    }
    return methods;
  }

  Future<void> _submit() async {
    final repos = context.repos;
    setState(() {
      _busy = true;
      _stage = widget.args.isChange ? 'Updating your plan…' : 'Creating your membership…';
    });
    try {
      final SubscribeResult result;
      if (widget.args.isChange) {
        result = await repos.membership.changePlan(
          planCode: plan.code,
          selections: _selections,
        );
      } else {
        result = await repos.membership.subscribe(
          planCode: plan.code,
          selections: _selections,
          clientOpId: _opId,
        );
      }
      if (!mounted) return;
      var paid = true;
      if (result.payment != null) {
        setState(() => _stage = 'Contacting payment provider…');
        final payment = await repos.customer.confirmSandboxPayment(
          result.payment!.payment.id,
        );
        paid = payment.status.isVerified;
        if (!mounted) return;
        if (!paid) {
          showSnack(
            context,
            payment.failureReason ??
                'Payment is still ${payment.status.label.toLowerCase()} — your plan activates when the provider confirms.',
          );
        }
      }
      if (!mounted) return;
      AppHaptics.success(context);
      await _showDone(
        activated: paid && (result.payment != null || !widget.args.isChange),
        scheduled: widget.args.isChange && result.payment == null,
      );
      if (!mounted) return;
      context.go(Routes.membership);
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message);
      if (e.isConflict) context.go(Routes.membership);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    }
  }

  Future<void> _showDone({required bool activated, required bool scheduled}) {
    final s = widget.args.current;
    final when = s?.nextRenewalAt ?? s?.membership?.currentPeriodEnd;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('membership-done'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ConfettiBlob(size: 120),
            const SizedBox(height: 8),
            Text(
              scheduled
                  ? 'Plan change scheduled'
                  : activated
                  ? '${plan.name} membership active'
                  : 'Almost there',
              textAlign: TextAlign.center,
              style: SparklingTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              scheduled
                  ? 'You switch to ${plan.name} on ${when == null ? 'your next renewal' : SparklingDates.dayMonth(when)}. Your current benefits stay until then.'
                  : activated
                  ? 'Welcome to Sparkling ${plan.name}. ${plan.benefitsSummary(_selections)}.'
                  : 'We will activate your ${plan.name} membership as soon as the payment is confirmed.',
              textAlign: TextAlign.center,
              style: SparklingTypography.bodyMedium.copyWith(
                color: ctx.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('membership-done-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final args = widget.args;
    final valid = plan.selectionsValid(_selections);
    final title = args.isChange
        ? (args.isUpgrade ? 'Upgrade to ${plan.name}' : 'Switch to ${plan.name}')
        : 'Join ${plan.name}';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: title,
              onBack: _busy ? null : () => context.pop(),
            ),
            Expanded(
              child: AsyncView<List<PaymentMethod>>(
                future: _methods!,
                onRetry: () => setState(() => _methods = _loadMethods()),
                builder: (context, methods) {
                  final selectedMethod =
                      methods.where((m) => m.id == _methodId).firstOrNull;
                  final canPay = valid && (!_paysNow || selectedMethod != null);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                          children: [
                            PlanCard(
                              tone: planTone(plan),
                              title: plan.name,
                              tagline: plan.tagline,
                              trailing: Text(
                                plan.feeLabel,
                                style: SparklingTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: plan.discountNote == null
                                  ? null
                                  : Row(
                                      children: [
                                        const Icon(Symbols.sell_rounded, size: 16, fill: 1),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            plan.discountNote!,
                                            style: SparklingTypography.bodyMedium
                                                .copyWith(fontSize: 13.5),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 18),
                            for (final g in plan.chooseOneGroups)
                              OptionPicker(
                                group: g,
                                selected: _selections[g.code],
                                onSelect: (code) {
                                  AppHaptics.selection(context);
                                  setState(() => _selections = {..._selections, g.code: code});
                                },
                              ),
                            for (final g in plan.groups.where((g) => !g.isChooseOne)) ...[
                              SectionHeader(title: g.name),
                              for (final e in g.entitlements)
                                ListTileCard(
                                  leading: Icon(
                                    Symbols.check_circle_rounded,
                                    color: context.sparkling.success,
                                    fill: 1,
                                  ),
                                  title: Text(e.label),
                                  subtitle: Text(
                                    '${e.services.map((s) => s.name).join(' / ')} · ${e.period.label}',
                                  ),
                                ),
                              const SizedBox(height: 10),
                            ],
                            if (_paysNow) ...[
                              const SizedBox(height: 8),
                              const SectionHeader(title: 'Payment method'),
                              for (final m in methods) ...[
                                RadioCard(
                                  selected: m.id == _methodId,
                                  onChanged: (_) {
                                    AppHaptics.selection(context);
                                    setState(() => _methodId = m.id);
                                  },
                                  radioPosition: RadioCardRadioPosition.trailing,
                                  leading: BrandPlate(brand: m.brand),
                                  title: Text(
                                    m.displayLabel,
                                    style: SparklingTypography.titleLarge.copyWith(fontSize: 17),
                                  ),
                                  subtitle: Text(
                                    m.isCard ? 'Charged monthly · tokenised' : 'Pay from your bank app',
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Symbols.verified_user_rounded,
                                    size: 20,
                                    color: cs.onSurfaceVariant,
                                    fill: 1,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      args.isUpgrade
                                          ? 'You pay the ${plan.name} fee today; a new monthly period starts now.'
                                          : 'Renews monthly on the same day. Cancel any time from the Membership tab; unused washes do not roll over.',
                                      style: SparklingTypography.bodyMedium.copyWith(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              InfoBanner(
                                tone: InfoTone.info,
                                icon: Symbols.event_repeat_rounded,
                                text:
                                    'Nothing to pay now — you switch to ${plan.name} at your next renewal.',
                              ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          border: Border(top: BorderSide(color: cs.outlineVariant)),
                        ),
                        child: BottomActionBar(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_stage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    _stage!,
                                    textAlign: TextAlign.center,
                                    style: SparklingTypography.bodyMedium.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              PillButton(
                                key: const ValueKey('subscribe-cta'),
                                label: _paysNow
                                    ? 'Pay ${Money.formatZar(plan.monthlyFeeCents)} securely'
                                    : 'Schedule switch to ${plan.name}',
                                icon: _paysNow ? Symbols.lock_rounded : Symbols.event_repeat_rounded,
                                expand: true,
                                minHeight: 56,
                                loading: _busy,
                                onPressed: canPay && !_busy ? _submit : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
