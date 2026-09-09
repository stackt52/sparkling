import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/motion.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';

/// Selectable card used for services, payment methods and staff assignment.
///
/// Selected = primaryContainer + 2px primary border + filled radio check.
/// Unselected = surfaceContainer, r22. [enabled] false renders at 55% opacity
/// (at-capacity staff rows).
class RadioCard extends StatelessWidget {
  const RadioCard({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.footer,
    this.enabled = true,
    this.padding = const EdgeInsets.all(SparklingSpacing.cardPadding),
    this.radioPosition = RadioCardRadioPosition.leading,
    this.semanticLabel,
  });

  final bool selected;

  /// Called with `true` when tapped (never with `false`; radios don't untoggle).
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;

  /// Leading widget shown between the radio and the text (e.g. VISA plate).
  final Widget? leading;

  /// Trailing widget (price, "Earn 22 pts" chip …).
  final Widget? trailing;

  /// Optional row rendered under the text (e.g. skill chips).
  final Widget? footer;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final RadioCardRadioPosition radioPosition;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(SparklingShapes.card);
    final duration = SparklingMotion.durationFor(context, SparklingMotion.fast);

    final radio = _RadioDot(
      selected: selected,
      color: cs.primary,
      outline: cs.outline,
    );

    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle.merge(
          style: context.text.titleMedium!.copyWith(
            color: selected ? cs.onPrimaryContainer : cs.onSurface,
          ),
          child: title,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: context.text.bodySmall!.copyWith(
              color: selected
                  ? cs.onPrimaryContainer.withValues(alpha: 0.8)
                  : cs.onSurfaceVariant,
            ),
            child: subtitle!,
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );

    return Semantics(
      selected: selected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: AnimatedContainer(
          duration: duration,
          curve: SparklingMotion.emphasized,
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainer,
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
              onTap: enabled && onChanged != null
                  ? () => onChanged!(true)
                  : null,
              child: Padding(
                padding: padding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (radioPosition == RadioCardRadioPosition.leading) ...[
                      radio,
                      const SizedBox(width: 12),
                    ],
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: textColumn),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                    if (radioPosition == RadioCardRadioPosition.trailing) ...[
                      const SizedBox(width: 12),
                      radio,
                    ],
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

enum RadioCardRadioPosition { leading, trailing }

class _RadioDot extends StatelessWidget {
  const _RadioDot({
    required this.selected,
    required this.color,
    required this.outline,
  });
  final bool selected;
  final Color color;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: SparklingMotion.durationFor(context, SparklingMotion.fast),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(color: selected ? color : outline, width: 2),
      ),
      child: selected
          ? Icon(
              Symbols.check_rounded,
              size: 15,
              color: context.colors.onPrimary,
              weight: 700,
            )
          : null,
    );
  }
}
