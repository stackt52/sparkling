import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Loyalty tiers.
enum LoyaltyTierKind { silver, gold, platinum }

/// Tier pill ("Gold · 2 450 pts", "GOLD MEMBER").
///
/// Gold uses the gold gradient; silver a cool grey; platinum a light steel
/// gradient. In dark mode gold becomes translucent with a gold border (1k).
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
        gradient = LinearGradient(
          colors: dark
              ? const [Color(0xFF3B4C69), Color(0xFF5C6F90)]
              : const [Color(0xFFE6ECF5), Color(0xFFC5D0E0)],
        );
        fg = dark ? Colors.white : const Color(0xFF1E2A3A);
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
