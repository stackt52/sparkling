import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/common.dart';

/// Colour tone for a plan (falls back to the tier).
PlanTone planTone(MembershipPlan plan) =>
    plan.color == null ? PlanTone.forTier(tierKind(plan.tier)) : PlanTone.forKey(plan.color);

/// Sentence for a `choose_one` / `all` group: "4 × Sparkling Wash **or**
/// 8 × Exterior Wash".
String groupLabel(MembershipPlanGroup g) => g.entitlements
    .map((e) => e.label)
    .join(g.isChooseOne ? ' or ' : ' and ');

/// The member's plan card (docs/MEMBERSHIPS.md UI): plan colour, allowance
/// rings per entitlement, renewal date + invoice state, "Pay now" when an
/// invoice is open.
class MemberPlanCard extends StatelessWidget {
  const MemberPlanCard({
    super.key,
    required this.summary,
    this.onPayNow,
    this.paying = false,
  });

  final MembershipSummary summary;
  final VoidCallback? onPayNow;
  final bool paying;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final plan = s.plan;
    final m = s.membership!;
    final tone = plan == null ? PlanTone.gold : planTone(plan);
    final palette = PlanPalette.of(context, tone);
    final open = s.openInvoice;
    final status = _statusChip(context, s);
    return PlanCard(
      key: const ValueKey('member-plan-card'),
      tone: tone,
      pillLabel: '${plan?.name ?? m.planCode ?? 'Plan'} member',
      title: plan?.name,
      tagline: plan?.tagline,
      trailing: status,
      semanticLabel: '${plan?.name} membership, ${m.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in s.allowances) ...[
            AllowanceRing(
              key: ValueKey('allowance-${a.entitlementCode}'),
              remaining: a.remaining,
              quantity: a.quantity,
              title: a.nounFor,
              caption: [
                '${a.remaining} of ${a.quantity} left',
                if (a.resetLabel != null) a.resetLabel!,
              ].join(' · '),
              color: palette.accent,
              trackColor: palette.track,
              foreground: palette.foreground,
              mutedForeground: palette.muted,
            ),
            const SizedBox(height: 12),
          ],
          if (plan?.discountNote != null)
            Row(
              children: [
                Icon(Symbols.sell_rounded, size: 16, color: palette.muted, fill: 1),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan!.discountNote!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      fontSize: 13.5,
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Divider(color: palette.track, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                open == null ? Symbols.event_repeat_rounded : Symbols.receipt_long_rounded,
                size: 18,
                color: palette.foreground,
                fill: 1,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _renewalLine(s),
                  style: SparklingTypography.bodyMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.foreground,
                  ),
                ),
              ),
              if (open != null && onPayNow != null)
                PillButton(
                  key: const ValueKey('pay-now'),
                  label: 'Pay now',
                  dense: true,
                  loading: paying,
                  variant: s.isPastDue
                      ? PillButtonVariant.filled
                      : PillButtonVariant.tonal,
                  onPressed: onPayNow,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _renewalLine(MembershipSummary s) {
    final m = s.membership!;
    final open = s.openInvoice;
    final fee = s.plan == null ? '' : ' · ${Money.formatZarCompact(s.plan!.monthlyFeeCents).replaceFirst('R', 'R ')}';
    if (s.isPastDue && open != null) {
      return 'Payment due · ${Money.formatZar(open.amountCents)} · benefits paused';
    }
    if (s.isPending) return 'Awaiting first payment';
    if (open != null) {
      return 'Renewal due ${open.dueAt == null ? '' : SparklingDates.dayMonth(open.dueAt!)} · ${Money.formatZar(open.amountCents)}';
    }
    if (m.cancelAtPeriodEnd) {
      return 'Ends ${m.currentPeriodEnd == null ? '' : SparklingDates.dayMonth(m.currentPeriodEnd!)} · not renewing';
    }
    if (m.nextPlanId != null && s.nextRenewalAt != null) {
      return 'Switches plan on ${SparklingDates.dayMonth(s.nextRenewalAt!)}';
    }
    if (s.nextRenewalAt != null) {
      return 'Renews ${SparklingDates.dayMonth(s.nextRenewalAt!)}$fee';
    }
    return 'Active';
  }

  static Widget _statusChip(BuildContext context, MembershipSummary s) {
    final m = s.membership!;
    if (s.pendingSync) {
      return const StatusChip(label: 'Syncing', tone: StatusChipTone.neutral, dense: true);
    }
    return switch (m.status) {
      MembershipStatus.active when m.cancelAtPeriodEnd =>
        const StatusChip(label: 'Ending', tone: StatusChipTone.warning, dense: true),
      MembershipStatus.active =>
        const StatusChip(label: 'Active', tone: StatusChipTone.success, dense: true),
      MembershipStatus.pastDue =>
        const StatusChip(label: 'Payment due', tone: StatusChipTone.error, dense: true),
      MembershipStatus.pending =>
        const StatusChip(label: 'Awaiting payment', tone: StatusChipTone.warning, dense: true),
      _ => StatusChip(label: m.status.label, tone: StatusChipTone.neutral, dense: true),
    };
  }
}

/// A plan on offer (non-member view / change plan): tagline, fee, the
/// OR / AND entitlement groups, discount note and a CTA.
class PlanOfferCard extends StatelessWidget {
  const PlanOfferCard({
    super.key,
    required this.plan,
    required this.onChoose,
    this.ctaLabel,
    this.current = false,
  });

  final MembershipPlan plan;
  final VoidCallback? onChoose;
  final String? ctaLabel;

  /// The customer's current plan (CTA disabled).
  final bool current;

  @override
  Widget build(BuildContext context) {
    final tone = planTone(plan);
    final p = PlanPalette.of(context, tone);
    return PlanCard(
      key: ValueKey('plan-${plan.code}'),
      tone: tone,
      title: plan.name,
      tagline: plan.tagline,
      trailing: Text(
        plan.feeLabel,
        style: SparklingTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w800,
          color: p.foreground,
        ),
      ),
      semanticLabel: '${plan.name} plan, ${plan.feeLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in plan.groups) ...[
            _Bullet(
              icon: g.isChooseOne
                  ? Symbols.alt_route_rounded
                  : Symbols.check_circle_rounded,
              text: g.isChooseOne
                  ? '${g.name}: ${groupLabel(g)}'
                  : '${g.name}: ${groupLabel(g)}',
              color: p.foreground,
              muted: p.muted,
            ),
            const SizedBox(height: 6),
          ],
          if (plan.discountNote != null) ...[
            _Bullet(
              icon: Symbols.sell_rounded,
              text: plan.discountNote!,
              color: p.foreground,
              muted: p.muted,
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 8),
          PillButton(
            key: ValueKey('choose-${plan.code}'),
            label: current
                ? 'Your current plan'
                : (ctaLabel ?? 'Choose ${plan.name}'),
            expand: true,
            variant: tone == PlanTone.black
                ? PillButtonVariant.filled
                : PillButtonVariant.navy,
            trailingIcon: current ? null : Symbols.arrow_forward_rounded,
            onPressed: current ? null : onChoose,
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.text,
    required this.color,
    required this.muted,
  });
  final IconData icon;
  final String text;
  final Color color;
  final Color muted;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: color, fill: 1),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: SparklingTypography.bodyMedium.copyWith(
            fontSize: 14,
            height: 1.35,
            color: color,
          ),
        ),
      ),
    ],
  );
}

/// Radio cards for a `choose_one` group — used by the subscribe screen and
/// the change-option sheet.
class OptionPicker extends StatelessWidget {
  const OptionPicker({
    super.key,
    required this.group,
    required this.selected,
    required this.onSelect,
  });

  final MembershipPlanGroup group;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: group.name),
        for (final e in group.entitlements) ...[
          RadioCard(
            key: ValueKey('option-${e.code}'),
            selected: selected == e.code,
            onChanged: (_) => onSelect(e.code),
            radioPosition: RadioCardRadioPosition.trailing,
            leading: Icon(
              serviceIcon(
                e.period == EntitlementPeriod.year ? 'auto_awesome' : 'local_car_wash',
              ),
              color: selected == e.code ? cs.onPrimaryContainer : cs.primary,
              fill: 1,
            ),
            title: Text(
              e.label,
              style: SparklingTypography.titleLarge.copyWith(fontSize: 17),
            ),
            subtitle: Text(
              '${e.code} · ${e.services.map((s) => s.name).join(' / ')} · ${e.period.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Bottom sheet: pick new options for every `choose_one` group.
Future<Map<String, String>?> showChangeOptionsSheet(
  BuildContext context, {
  required MembershipPlan plan,
  required Map<String, String> current,
}) {
  var draft = Map<String, String>.of(current);
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Change your options'),
              for (final g in plan.chooseOneGroups)
                OptionPicker(
                  group: g,
                  selected: draft[g.code],
                  onSelect: (code) => setState(() => draft = {...draft, g.code: code}),
                ),
              const AuditNote(
                icon: Symbols.info_rounded,
                text: 'Options can only change before anything is used in the current month.',
              ),
              const SizedBox(height: 10),
              PillButton(
                key: const ValueKey('save-options'),
                label: 'Save options',
                expand: true,
                onPressed: plan.selectionsValid(draft)
                    ? () => Navigator.of(ctx).pop(draft)
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Cancel confirm sheet → `true` = at period end, `false` = now, null = keep.
Future<bool?> showCancelMembershipSheet(
  BuildContext context, {
  required MembershipSummary summary,
}) {
  final end = summary.membership?.currentPeriodEnd;
  return showModalBottomSheet<bool>(
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
            SectionHeader(title: 'Cancel ${summary.planName ?? 'your'} membership?'),
            Text(
              end == null
                  ? 'Your washes and discounts stop when the membership ends.'
                  : 'Keep your benefits until ${SparklingDates.dayMonth(end)} and stop renewing, or end the membership right now (remaining washes are forfeited).',
              style: SparklingTypography.bodyLarge.copyWith(
                color: ctx.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              key: const ValueKey('cancel-at-period-end'),
              label: end == null ? 'Stop renewing' : 'Stop renewing on ${SparklingDates.dayMonth(end)}',
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 10),
            PillButton(
              key: const ValueKey('cancel-now'),
              label: 'Cancel now',
              variant: PillButtonVariant.outlinedError,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Keep my membership',
              variant: PillButtonVariant.tonal,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(null),
            ),
          ],
        ),
      ),
    ),
  );
}
