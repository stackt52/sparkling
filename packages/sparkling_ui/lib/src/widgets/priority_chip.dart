import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Work-order priority pill: P1 = error tone, P2 = gold, P3 = neutral (2a/2g).
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority})
    : assert(priority >= 1 && priority <= 3);

  /// 1 (highest) … 3.
  final int priority;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final (Color bg, Color fg) = switch (priority) {
      1 =>
        context.isDark
            ? (SparklingColors.darkError, SparklingColors.darkOnError)
            : (cs.errorContainer, cs.onErrorContainer),
      2 => (SparklingColors.goldLight, SparklingColors.onGold),
      _ => (cs.surfaceContainerHigh, cs.onSurfaceVariant),
    };
    return Semantics(
      label: 'Priority $priority',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: Text(
          'P$priority',
          style: SparklingTypography.labelLarge.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}
