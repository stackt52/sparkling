import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Date chip for the 5-up date strip (1c): r18; disabled = muted; selected =
/// navy block with azure weekday.
class DateChip extends StatelessWidget {
  const DateChip({
    super.key,
    required this.weekday,
    required this.day,
    this.month,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.width = 64,
  });

  /// Short weekday, e.g. `'Mon'`.
  final String weekday;

  /// Day of month, e.g. `'14'`.
  final String day;

  /// Optional short month shown under the day (`'Sep'`).
  final String? month;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final bg = selected
        ? (dark ? cs.primaryContainer : SparklingColors.navy)
        : cs.surfaceContainer;
    final weekdayColor = selected
        ? (dark ? cs.primary : SparklingColors.azure)
        : cs.onSurfaceVariant;
    final dayColor = selected
        ? (dark ? cs.onPrimaryContainer : Colors.white)
        : cs.onSurface;
    final radius = BorderRadius.circular(SparklingShapes.tile);

    return Semantics(
      button: enabled,
      selected: selected,
      enabled: enabled,
      label: '$weekday $day${month == null ? '' : ' $month'}',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: AnimatedContainer(
          duration: SparklingMotion.durationFor(context, SparklingMotion.fast),
          width: width,
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekday.toUpperCase(),
                      style: SparklingTypography.overline.copyWith(
                        color: weekdayColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      day,
                      style: SparklingTypography.headlineSmall.copyWith(
                        fontSize: 20,
                        color: dayColor,
                        height: 1.1,
                      ),
                    ),
                    if (month != null)
                      Text(
                        month!,
                        style: SparklingTypography.labelMedium.copyWith(
                          color: dayColor.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
