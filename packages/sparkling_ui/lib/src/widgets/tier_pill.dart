import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Loyalty tiers — since membership plans the tier is the plan
/// (silver = no plan, gold / platinum / black = the plan).
enum LoyaltyTierKind { silver, gold, platinum, black }

/// Tier pill ("Gold · 2 450 pts", "GOLD MEMBER", "Black · 8 washes left").
///
/// Gold uses the gold gradient; silver a cool grey; platinum a light steel
/// gradient; black the navy `#0B1220 → #203060` gradient with gold text. In
/// dark mode gold becomes translucent with a gold border (1k) and black keeps
/// its gradient with a gold border.
class TierPill extends StatelessWidget {
  const TierPill({
    super.key,
    required this.tier,
    this.label,
    this.icon = Symbols.loyalty_rounded,
    this.uppercase = false,
    this.onTap,
  });

  final LoyaltyTierKind tier;

  /// Defaults to the tier name.
  final String? label;
  final IconData? icon;
  final bool uppercase;
  final VoidCallback? onTap;

  static String nameOf(LoyaltyTierKind t) => switch (t) {
    LoyaltyTierKind.silver => 'Silver',
    LoyaltyTierKind.gold => 'Gold',
    LoyaltyTierKind.platinum => 'Platinum',
    LoyaltyTierKind.black => 'Black',
  };

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final text = uppercase
        ? (label ?? nameOf(tier)).toUpperCase()
        : (label ?? nameOf(tier));

    Gradient? gradient;
    Color? bg;
    Color fg;
    BorderSide side = BorderSide.none;
    switch (tier) {
      case LoyaltyTierKind.gold:
        if (dark) {
          bg = SparklingColors.goldDeep.withValues(alpha: 0.18);
          fg = SparklingColors.goldLight;
          side = const BorderSide(color: SparklingColors.goldDeep, width: 1);
        } else {
          gradient = SparklingColors.goldGradient;
          fg = SparklingColors.onGold;
        }
      case LoyaltyTierKind.silver:
        bg = dark ? const Color(0xFF2B3C58) : const Color(0xFFE4E9EF);
        fg = dark ? const Color(0xFFD5DEEA) : const Color(0xFF3F4A57);
      case LoyaltyTierKind.platinum:
        gradient = dark
            ? SparklingColors.platinumGradientDark
            : SparklingColors.platinumGradient;
        fg = dark ? Colors.white : SparklingColors.onPlatinum;
      case LoyaltyTierKind.black:
        gradient = dark
            ? SparklingColors.blackGradientDark
            : SparklingColors.blackGradient;
        fg = SparklingColors.onBlack;
        if (dark) {
          side = BorderSide(
            color: SparklingColors.goldDeep.withValues(alpha: 0.7),
            width: 1,
          );
        }
    }

    return Semantics(
      label: '${nameOf(tier)} tier',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Ink(
            decoration: ShapeDecoration(
              color: bg,
              gradient: gradient,
              shape: StadiumBorder(side: side),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg, fill: 1),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    text,
                    style: SparklingTypography.labelLarge.copyWith(
                      fontSize: uppercase ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: uppercase ? 0.6 : 0,
                      color: fg,
                    ),
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
