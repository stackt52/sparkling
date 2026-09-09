import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Compact KPI tile for the 4-across supervisor row (2c): centred 24px 700
/// numeral above a short label. Colour logic mirrors the design-system
/// [StatTone] (azure numeral / neutral / error tint / success tint) but the
/// layout is centred and the label is not upper-cased so four tiles fit a
/// 412px phone. On wider layouts prefer [StatTile].
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.value,
    required this.label,
    this.tone = StatTone.neutral,
    this.onTap,
    this.selected = false,
  });

  final String value;
  final String label;
  final StatTone tone;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final dark = context.isDark;
    final (Color bg, Color valueColor, Color labelColor, Color accent) =
        switch (tone) {
          StatTone.azure => (
            cs.primaryContainer,
            dark ? cs.primary : SparklingColors.lightPrimary,
            dark ? cs.primary : SparklingColors.lightPrimary,
            cs.primary,
          ),
          StatTone.neutral => (
            cs.surfaceContainer,
            cs.onSurface,
            cs.onSurfaceVariant,
            cs.outline,
          ),
          StatTone.error => (
            cs.errorContainer.withValues(alpha: dark ? 0.6 : 1),
            cs.onErrorContainer,
            cs.onErrorContainer,
            cs.error,
          ),
          StatTone.success => (
            x.successContainer.withValues(alpha: dark ? 0.7 : 1),
            x.onSuccessContainer,
            x.onSuccessContainer,
            x.success,
          ),
          StatTone.gold => (
            dark
                ? SparklingColors.goldDeep.withValues(alpha: 0.16)
                : SparklingColors.goldLight.withValues(alpha: 0.5),
            dark ? SparklingColors.goldLight : SparklingColors.onGold,
            dark ? SparklingColors.goldLight : SparklingColors.onGold,
            SparklingColors.goldDeep,
          ),
        };
    final radius = BorderRadius.circular(SparklingShapes.card);
    return Semantics(
      label: '$label: $value',
      button: onTap != null,
      selected: selected,
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: selected ? Border.all(color: accent, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: SparklingTypography.font(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: valueColor,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: SparklingTypography.labelLarge.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                    maxLines: 1,
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
