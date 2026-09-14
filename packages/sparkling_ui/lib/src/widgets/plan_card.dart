import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'tier_pill.dart';

/// Colour treatment of a membership plan card: gold gradient, platinum steel
/// or black navy with gold text (docs/MEMBERSHIPS.md "UI").
enum PlanTone {
  gold,
  platinum,
  black;

  /// Tone for a plan's tier (silver has no plan card → gold treatment).
  static PlanTone forTier(LoyaltyTierKind tier) => switch (tier) {
    LoyaltyTierKind.platinum => platinum,
    LoyaltyTierKind.black => black,
    LoyaltyTierKind.silver || LoyaltyTierKind.gold => gold,
  };

  /// Tone for the plan's `color` key (`gold` | `platinum` | `black`).
  static PlanTone forKey(String? key) => switch (key) {
    'platinum' => platinum,
    'black' => black,
    _ => gold,
  };

  LoyaltyTierKind get tier => switch (this) {
    gold => LoyaltyTierKind.gold,
    platinum => LoyaltyTierKind.platinum,
    black => LoyaltyTierKind.black,
  };
}

/// Resolved colours of a [PlanTone] for the current brightness.
class PlanPalette {
  const PlanPalette({
    required this.gradient,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.track,
  });

  final Gradient gradient;

  /// Primary text / icon colour on the card.
  final Color foreground;

  /// Secondary text colour on the card.
  final Color muted;

  /// Ring / progress sweep colour on the card.
  final Color accent;

  /// Ring / progress track colour on the card.
  final Color track;

  static PlanPalette of(BuildContext context, PlanTone tone) {
    final dark = context.isDark;
    return switch (tone) {
      PlanTone.gold => PlanPalette(
        gradient: SparklingColors.goldGradient,
        foreground: SparklingColors.onGold,
        muted: SparklingColors.onGold.withValues(alpha: 0.72),
        accent: SparklingColors.onGold,
        track: SparklingColors.onGold.withValues(alpha: 0.18),
      ),
      PlanTone.platinum => PlanPalette(
        gradient: dark
            ? SparklingColors.platinumGradientDark
            : SparklingColors.platinumGradient,
        foreground: dark ? Colors.white : SparklingColors.onPlatinum,
        muted: (dark ? Colors.white : SparklingColors.onPlatinum).withValues(
          alpha: 0.72,
        ),
        accent: dark ? SparklingColors.azure : SparklingColors.navy,
        track: (dark ? Colors.white : SparklingColors.onPlatinum).withValues(
          alpha: 0.16,
        ),
      ),
      PlanTone.black => PlanPalette(
        gradient: dark
            ? SparklingColors.blackGradientDark
            : SparklingColors.blackGradient,
        foreground: SparklingColors.onBlack,
        muted: SparklingColors.onBlack.withValues(alpha: 0.72),
        accent: SparklingColors.goldDeep,
        track: SparklingColors.goldDeep.withValues(alpha: 0.22),
      ),
    };
  }
}

/// Membership plan card (r28) in the plan's colour: a [TierPill] header with
/// an optional trailing widget (fee, status chip), the plan name, an optional
/// tagline and any [child] content — allowance rings, entitlement lists,
/// actions. Text and icons inside inherit the plan foreground colour.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.tone,
    this.title,
    this.pillLabel,
    this.tagline,
    this.trailing,
    this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.all(SparklingSpacing.cardPaddingLoose),
    this.radius = SparklingShapes.hero,
    this.semanticLabel,
  });

  final PlanTone tone;

  /// Large plan name ("Gold"). Omitted when null.
  final String? title;

  /// Pill text (defaults to the tier name, e.g. "GOLD").
  final String? pillLabel;
  final String? tagline;

  /// Right of the pill — fee ("R 295 / month") or a status chip.
  final Widget? trailing;
  final Widget? child;
  final VoidCallback? onTap;

  /// Draws a primary outline (plan picker).
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = PlanPalette.of(context, tone);
    final cs = context.colors;
    final br = BorderRadius.circular(radius);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: p.gradient,
            borderRadius: br,
            border: selected
                ? Border.all(color: cs.primary, width: 2.5)
                : null,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            child: Padding(
              padding: padding,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: p.foreground),
                child: IconTheme.merge(
                  data: IconThemeData(color: p.foreground),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              // The card is its own coloured surface: keep the
                              // light-mode pill so it reads on the gradient.
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  brightness: Brightness.light,
                                ),
                                child: TierPill(
                                  tier: tone.tier,
                                  label: pillLabel,
                                  uppercase: pillLabel == null,
                                  icon: null,
                                ),
                              ),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: trailing,
                              ),
                            ),
                          ] else
                            const Spacer(),
                        ],
                      ),
                      if (title != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          title!,
                          style: SparklingTypography.headlineMedium.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: p.foreground,
                          ),
                        ),
                      ],
                      if (tagline != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          tagline!,
                          style: SparklingTypography.bodyMedium.copyWith(
                            fontSize: 14,
                            height: 1.35,
                            color: p.muted,
                          ),
                        ),
                      ],
                      if (child != null) ...[
                        const SizedBox(height: 14),
                        child!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
