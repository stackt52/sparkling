import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Tone of a [StatTile] numeral / tint.
enum StatTone { azure, neutral, error, success, gold }

/// KPI tile: 24px 700 numeral + overline label (2c supervisor ops, 3a admin).
/// Error/success tones tint the background; azure colours the numeral.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.tone = StatTone.neutral,
    this.icon,
    this.trailing,
    this.onTap,
    this.bordered = false,
    this.valueSize = 24,
  });

  final String value;
  final String label;
  final StatTone tone;
  final IconData? icon;

  /// e.g. a trend chip.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Draws a 1.5px border in the tone colour (exception cards).
  final bool bordered;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final (Color bg, Color valueColor, Color accent) = switch (tone) {
      StatTone.azure => (
        cs.surfaceContainer,
        context.isDark ? cs.primary : SparklingColors.azure,
        SparklingColors.azure,
      ),
      StatTone.neutral => (cs.surfaceContainer, cs.onSurface, cs.outline),
      StatTone.error => (
        cs.errorContainer.withValues(alpha: context.isDark ? 0.6 : 1),
        cs.onErrorContainer,
        cs.error,
      ),
      StatTone.success => (
        x.successContainer.withValues(alpha: context.isDark ? 0.7 : 1),
        x.onSuccessContainer,
        x.success,
      ),
      StatTone.gold => (
        context.isDark
            ? SparklingColors.goldDeep.withValues(alpha: 0.16)
            : SparklingColors.goldLight.withValues(alpha: 0.5),
        context.isDark ? SparklingColors.goldLight : SparklingColors.onGold,
        SparklingColors.goldDeep,
      ),
    };
    final radius = BorderRadius.circular(SparklingShapes.card);

    return Semantics(
      label: '$label: $value',
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: bordered ? Border.all(color: accent, width: 1.5) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 16,
                        color: valueColor.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: SparklingTypography.overline.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: SparklingTypography.font(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
