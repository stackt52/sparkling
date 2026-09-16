import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/screen_header.dart';
import '../../widgets/segmented_pills.dart';

/// Header + 4-segment progress strip shared by the walk-in steps (mirrors
/// the customer app's `BookingStepHeader`, 1b).
class BookingStepHeader extends StatelessWidget {
  const BookingStepHeader({
    super.key,
    required this.title,
    required this.step,
    required this.subtitle,
    this.total = 4,
    this.onBack,
    this.trailing,
  });

  final String title;
  final int step;
  final int total;
  final String subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScreenHeader(
          title: title,
          subtitle: 'Step $step of $total · $subtitle',
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          leading: onBack == null
              ? null
              : IconTileButton(
                  icon: Symbols.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: onBack,
                ),
          trailing: trailing,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: StepProgressStrip(current: step, total: total),
        ),
      ],
    );
  }
}

/// Sticky bottom bar with an optional label/value block and the CTA.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.child,
    this.leadingLabel,
    this.leadingValue,
  });

  final Widget child;
  final String? leadingLabel;
  final String? leadingValue;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Row(
          children: [
            if (leadingValue != null) ...[
              Flexible(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingLabel != null)
                    Text(
                      leadingLabel!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    leadingValue!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SparklingTypography.headlineMedium.copyWith(
                      fontSize: 22,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(flex: 3, child: child),
          ],
        ),
      ),
    );
  }
}

/// 1px dashed horizontal rule (payment summary, 1f).
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color, this.height = 1});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
            count,
            (_) => Container(
              width: dash,
              height: height,
              margin: const EdgeInsets.only(right: gap),
              color: c,
            ),
          ),
        );
      },
    );
  }
}

/// Tonal icon tile (primaryContainer by default).
class TintedIconTile extends StatelessWidget {
  const TintedIconTile({
    super.key,
    required this.icon,
    this.size = 56,
    this.radius = SparklingShapes.tile,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double radius;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? cs.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        icon,
        size: size * 0.45,
        color: foreground ?? cs.primary,
        fill: 1,
      ),
    );
  }
}

/// Navy outlet card (1b) — read-only for the staff member's own outlet,
/// tappable only when they work at several.
class OutletCard extends StatelessWidget {
  const OutletCard({super.key, required this.outlet, this.onTap});

  final Outlet? outlet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final cs = context.colors;
    final fg = dark ? cs.onPrimaryContainer : Colors.white;
    final bg = dark ? cs.primaryContainer : context.sparkling.navy;
    final o = outlet;
    final hours = o?.hoursFor(DateTime.now().weekday);
    final radius = BorderRadius.circular(SparklingShapes.card);
    return Semantics(
      button: onTap != null,
      label: o == null ? 'Outlet' : 'Outlet ${o.name}',
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: dark ? 0.10 : 0.14),
                    borderRadius: BorderRadius.circular(SparklingShapes.tile),
                  ),
                  child: Icon(
                    Symbols.storefront_rounded,
                    color: dark ? cs.primary : const Color(0xFF8BD2FF),
                    fill: 1,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o?.name ?? 'Your outlet',
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 17,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        o == null
                            ? 'Loading…'
                            : [
                                '${o.bayCount} bays',
                                if (hours != null)
                                  'Open ${hours[0]}–${hours[1]}'
                                else
                                  'Closed today',
                              ].join(' · '),
                        style: SparklingTypography.bodyMedium.copyWith(
                          fontSize: 13.5,
                          color: fg.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  onTap == null
                      ? Symbols.lock_rounded
                      : Symbols.unfold_more_rounded,
                  size: onTap == null ? 18 : 24,
                  color: fg.withValues(alpha: 0.7),
                  fill: onTap == null ? 1 : 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selected-customer summary (step 1 after choosing, and the top of steps
/// 2–4): initials avatar, name, phone, tier pill and "Change".
class CustomerCard extends StatelessWidget {
  const CustomerCard({
    super.key,
    required this.customer,
    this.onChange,
    this.compact = false,
  });

  final CustomerSummary customer;
  final VoidCallback? onChange;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final c = customer;
    final meta = [
      if (c.phone != null) Phone.format(c.phone),
      if (!compact && c.email != null) c.email!,
    ].join(' · ');
    return ListTileCard(
      padding: EdgeInsets.fromLTRB(16, compact ? 10 : 14, 12, compact ? 10 : 14),
      borderColor: cs.primary.withValues(alpha: 0.45),
      leading: Container(
        width: compact ? 40 : 48,
        height: compact ? 40 : 48,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(SparklingShapes.iconTileSmall),
        ),
        alignment: Alignment.center,
        child: Text(
          c.initials,
          style: SparklingTypography.titleMedium.copyWith(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SparklingTypography.titleLarge.copyWith(
                fontSize: 17,
                color: cs.onSurface,
              ),
            ),
          ),
          if (c.loyalty != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TierPill(
                  key: const ValueKey('customer-plan-pill'),
                  tier: tierKind(c.tier),
                  label: c.loyalty!.planLabel,
                ),
              ),
            ),
          ] else if (c.isWalkIn) ...[
            const SizedBox(width: 8),
            const StatusChip(label: 'Walk-in', dense: true),
          ],
        ],
      ),
      subtitle: Text(
        meta.isEmpty ? 'No contact details' : meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onChange == null
          ? null
          : TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Change'),
            ),
    );
  }
}

/// "Earn 22 pts" white/high-surface chip shown on the selected service (1b).
class PointsChip extends StatelessWidget {
  const PointsChip({super.key, required this.points});
  final int points;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: context.isDark ? cs.surfaceContainerHigh : Colors.white,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.sell_rounded,
            size: 15,
            color: context.sparkling.gold,
            fill: 1,
          ),
          const SizedBox(width: 6),
          Text(
            'Earn $points pts',
            style: SparklingTypography.labelLarge.copyWith(
              fontSize: 13,
              color: context.isDark
                  ? SparklingColors.goldLight
                  : SparklingColors.onGold,
            ),
          ),
        ],
      ),
    );
  }
}

IconData serviceIcon(String? name) => switch (name) {
  'water_drop' => Symbols.water_drop_rounded,
  'local_car_wash' => Symbols.local_car_wash_rounded,
  'auto_awesome' => Symbols.auto_awesome_rounded,
  'cleaning_services' => Symbols.cleaning_services_rounded,
  'car_crash' => Symbols.car_crash_rounded,
  'bolt' => Symbols.bolt_rounded,
  'percent' => Symbols.percent_rounded,
  'loyalty' => Symbols.loyalty_rounded,
  _ => Symbols.local_car_wash_rounded,
};

LoyaltyTierKind tierKind(LoyaltyTier tier) => switch (tier) {
  LoyaltyTier.silver => LoyaltyTierKind.silver,
  LoyaltyTier.gold => LoyaltyTierKind.gold,
  LoyaltyTier.platinum => LoyaltyTierKind.platinum,
  LoyaltyTier.black => LoyaltyTierKind.black,
};

/// "Sparkling Auto Care Centre Menlyn" → "Menlyn" for tight labels.
String shortOutletName(String? name) {
  if (name == null) return '';
  var n = name;
  for (final prefix in const [
    'Sparkling Auto Care Centre ',
    'Sparkling Elite Centre ',
    'Sparkling Car Wash ',
    'Sparkling ',
  ]) {
    if (n.startsWith(prefix)) {
      n = n.substring(prefix.length);
      break;
    }
  }
  return n;
}

/// Small / Large / Bike pills with the example hint (vehicles.size_class —
/// drives the small / large catalogue price).
class VehicleSizeSelector extends StatelessWidget {
  const VehicleSizeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.fromDisc = false,
  });

  final VehicleSize value;
  final ValueChanged<VehicleSize> onChanged;

  /// Prefilled from the licence-disc description.
  final bool fromDisc;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle size',
          style: SparklingTypography.labelLarge.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedPills<VehicleSize>(
          selected: value,
          onChanged: onChanged,
          segments: [
            for (final s in VehicleSize.values)
              PillSegment(value: s, label: s.label),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${value.hint}${fromDisc ? ' · from the disc' : ''}. '
          'Sets the small / large price.',
          style: SparklingTypography.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Offer card (1b): outlet wording, description · duration, "Includes: …"
/// for composites, VAT note for `excl` offers, the price resolved for the
/// vehicle size ("From R x" / "By quote") and the points chip when selected.
class ServiceOfferCard extends StatelessWidget {
  const ServiceOfferCard({
    super.key,
    required this.service,
    required this.size,
    required this.selected,
    required this.onSelect,
    this.points,
    this.included = false,
    this.benefitTag,
  });

  final OutletService service;
  final VehicleSize size;
  final bool selected;
  final VoidCallback onSelect;
  final int? points;

  /// The customer's plan covers this service (allowance left) → R 0.
  final bool included;

  /// "Included · 3 of 4 left" / "Gold −10%".
  final String? benefitTag;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final s = service;
    final pts = points ?? s.pointsFor(size);
    final includes = s.includesLabel;
    final from = s.pricingMode == PricingMode.from && !s.isByQuote && !included;
    final captionStyle = SparklingTypography.bodySmall.copyWith(
      fontSize: 12.5,
      color: selected
          ? cs.onPrimaryContainer.withValues(alpha: 0.85)
          : cs.onSurfaceVariant,
    );
    final showFooter =
        includes != null ||
        s.isExclVat ||
        s.isByQuote ||
        benefitTag != null ||
        (selected && pts > 0);
    return RadioCard(
      selected: selected,
      enabled: s.isAvailable,
      onChanged: (_) => onSelect(),
      radioPosition: RadioCardRadioPosition.trailing,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      leading: Icon(
        s.isByQuote ? Symbols.request_quote_rounded : serviceIcon(s.icon),
        color: selected ? cs.onPrimaryContainer : cs.primary,
        fill: 1,
        size: 26,
      ),
      title: Text(
        s.name,
        style: SparklingTypography.titleLarge.copyWith(fontSize: 17),
      ),
      subtitle: Text(
        [
          if (s.description != null) s.description!,
          '${s.durationMinutes} min',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: SparklingTypography.bodyMedium.copyWith(fontSize: 14),
      ),
      footer: !showFooter
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (benefitTag != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: MembershipBenefitChip(
                      label: included ? 'Included in plan' : benefitTag!,
                      detail: included ? benefitTag : null,
                      included: included,
                    ),
                  ),
                if (includes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(
                      TextSpan(
                        text: 'Includes: ',
                        style: captionStyle.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        children: [
                          TextSpan(text: includes, style: captionStyle),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (s.isByQuote)
                  Text(
                    'Priced by quote — raise a quote instead of booking.',
                    style: captionStyle,
                  )
                else if (s.isExclVat)
                  Text('Excl. VAT · 15% added to the total.', style: captionStyle),
                if (selected && pts > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: PointsChip(points: pts),
                      ),
                    ),
                  ),
              ],
            ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (from)
            Text(
              'From',
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          if (included)
            Text(
              compactZar(s.priceFor(size) ?? 0),
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12,
                decoration: TextDecoration.lineThrough,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          Text(
            s.isByQuote
                ? 'By quote'
                : included
                ? 'R 0'
                : compactZar(s.priceFor(size) ?? 0),
            textAlign: TextAlign.end,
            style: SparklingTypography.headlineSmall.copyWith(
              fontSize: s.isByQuote ? 16 : 19,
              color: included
                  ? (selected ? cs.onPrimaryContainer : x.success)
                  : (selected ? cs.onPrimaryContainer : cs.onSurface),
            ),
          ),
          if (s.isExclVat && !s.isByQuote && !included)
            Text(
              'excl. VAT',
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 11,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Checkbox card for an add-on of the chosen service's group.
class AddonCard extends StatelessWidget {
  const AddonCard({
    super.key,
    required this.addon,
    required this.size,
    required this.selected,
    required this.onChanged,
  });

  final OutletService addon;
  final VehicleSize size;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(SparklingShapes.card);
    final price = addon.priceFor(size);
    return Semantics(
      checked: selected,
      label: 'Add-on ${addon.name}',
      child: AnimatedContainer(
        duration: SparklingMotion.durationFor(context, SparklingMotion.fast),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : cs.surfaceContainer,
          borderRadius: radius,
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: price == null ? null : () => onChanged(!selected),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Symbols.add_circle_rounded,
                    color: cs.primary,
                    fill: selected ? 1 : 0,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          addon.name,
                          style: SparklingTypography.titleMedium.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        if (addon.description != null)
                          Text(
                            addon.description!,
                            style: SparklingTypography.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    price == null ? 'By quote' : '+ ${compactZar(price)}',
                    style: SparklingTypography.titleMedium.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Checkbox(
                    value: selected,
                    onChanged: price == null
                        ? null
                        : (v) => onChanged(v ?? false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `R 198.00` → `R 198` style compact amount used in bottom bars.
String compactZar(int cents) =>
    Money.formatZarCompact(cents).replaceFirst('R', 'R ');

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "September 2026" (no direct `intl` dependency in the staff app).
String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// "Included in plan · 3 of 4 left" (success tint) or "Gold −10%" (gold
/// tint) tag on an offer card / summary.
class MembershipBenefitChip extends StatelessWidget {
  const MembershipBenefitChip({
    super.key,
    required this.label,
    this.detail,
    this.included = false,
  });

  final String label;
  final String? detail;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    final dark = context.isDark;
    final bg = included
        ? x.successContainer
        : (dark
              ? SparklingColors.goldDeep.withValues(alpha: 0.18)
              : SparklingColors.goldLight);
    final fg = included
        ? x.onSuccessContainer
        : (dark ? SparklingColors.goldLight : SparklingColors.onGold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            included
                ? Symbols.check_circle_rounded
                : Symbols.workspace_premium_rounded,
            size: 15,
            color: fg,
            fill: 1,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              detail == null ? label : '$label · $detail',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
