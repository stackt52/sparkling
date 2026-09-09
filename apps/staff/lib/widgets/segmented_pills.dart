import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// One option of a [SegmentedPills] control.
class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.count});
  final T value;
  final String label;

  /// Rendered as "Label · 4".
  final int? count;
}

/// Segmented filter pills ("Mine · 4 / Queue · 5 / Done · 6", "Week / Month").
///
/// Selected = primary (dark) / brand navy (light) filled pill, unselected =
/// surfaceContainer, all ≥ 48px tall for gloved use (UX-006). When [grouped]
/// the pills sit inside one surfaceContainer track (leaderboard header).
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.grouped = false,
    this.height = 48,
    this.gap = 8,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool grouped;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final selectedBg = dark ? cs.primary : SparklingColors.navy;
    final selectedFg = dark ? cs.onPrimary : Colors.white;
    final duration = SparklingMotion.durationFor(context, SparklingMotion.fast);

    final pills = <Widget>[];
    for (final (i, s) in segments.indexed) {
      final isSelected = s.value == selected;
      final label = s.count == null ? s.label : '${s.label} · ${s.count}';
      if (i > 0 && !grouped) pills.add(SizedBox(width: gap));
      pills.add(
        Expanded(
          child: Semantics(
            button: true,
            selected: isSelected,
            label: label,
            child: AnimatedContainer(
              duration: duration,
              curve: SparklingMotion.emphasized,
              height: grouped ? height - 8 : height,
              decoration: ShapeDecoration(
                color: isSelected
                    ? selectedBg
                    : (grouped ? Colors.transparent : cs.surfaceContainer),
                shape: const StadiumBorder(),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(s.value),
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.titleMedium.copyWith(
                        fontSize: 16,
                        color: isSelected ? selectedFg : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final row = Row(children: pills);
    if (!grouped) return row;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: cs.surfaceContainer,
        shape: const StadiumBorder(),
      ),
      child: row,
    );
  }
}
