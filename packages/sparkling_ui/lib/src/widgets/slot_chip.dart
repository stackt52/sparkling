import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/motion.dart';
import '../tokens/typography.dart';

/// Time-slot state in the slot picker (1c).
enum SlotState { available, booked, selected }

/// Pill time-slot chip: available (surfaceContainer), booked (struck-through,
/// muted, not tappable), selected (filled primary).
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.label,
    this.state = SlotState.available,
    this.onTap,
    this.height = 44,
  });

  final String label;
  final SlotState state;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final booked = state == SlotState.booked;
    final selected = state == SlotState.selected;
    final bg = selected ? cs.primary : cs.surfaceContainer;
    final fg = selected
        ? cs.onPrimary
        : booked
        ? cs.onSurfaceVariant.withValues(alpha: 0.55)
        : cs.onSurface;

    return Semantics(
      button: !booked,
      selected: selected,
      enabled: !booked,
      label: booked ? '$label, booked' : label,
      child: AnimatedContainer(
        duration: SparklingMotion.durationFor(context, SparklingMotion.fast),
        height: height,
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: booked ? null : onTap,
            child: Center(
              child: Text(
                label,
                style: SparklingTypography.labelLarge.copyWith(
                  fontSize: 13.5,
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  decoration: booked ? TextDecoration.lineThrough : null,
                  decorationColor: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
