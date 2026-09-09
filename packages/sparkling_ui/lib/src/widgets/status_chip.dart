import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Colour tone of a [StatusChip].
enum StatusChipTone {
  neutral,
  primary,
  success,
  warning,
  error,
  gold,
  live,
  onDark,
}

/// Pill status chip (booking / work-order / stock states).
///
/// * `live` shows a pulsing-free green dot before the label ("Live · 2 min ago").
/// * `onDark` is the translucent white chip used inside hero cards.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusChipTone.neutral,
    this.icon,
    this.dot = false,
    this.outlined = false,
    this.dense = false,
    this.onTap,
  });

  final String label;
  final StatusChipTone tone;

  /// Optional leading icon (Material Symbols).
  final IconData? icon;

  /// Show a leading coloured dot (as in the "Confirmed" / "In progress" chips).
  final bool dot;

  /// Translucent background + 1px border variant (dark-mode gold chip).
  final bool outlined;

  /// Reduces padding/text size to 10.5px for tight table rows.
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, dotColor) = _colors(context);
    final textStyle = SparklingTypography.labelLarge.copyWith(
      fontSize: dense ? 10.5 : 12,
      fontWeight: FontWeight.w600,
      color: fg,
      height: 1.2,
    );
    final showDot = dot || tone == StatusChipTone.live;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDot) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 6),
        ] else if (icon != null) ...[
          Icon(icon, size: dense ? 13 : 15, color: fg),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Semantics(
      label: label,
      child: Material(
        color: outlined ? bg.withValues(alpha: 0.18) : bg,
        shape: StadiumBorder(
          side: outlined
              ? BorderSide(color: fg.withValues(alpha: 0.6))
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 9 : 12,
              vertical: dense ? 4 : 7,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  (Color, Color, Color) _colors(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    switch (tone) {
      case StatusChipTone.neutral:
        return (
          cs.surfaceContainerHigh,
          cs.onSurfaceVariant,
          cs.onSurfaceVariant,
        );
      case StatusChipTone.primary:
        return (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          context.isDark ? cs.primary : SparklingColors.azure,
        );
      case StatusChipTone.success:
        return (x.successContainer, x.onSuccessContainer, x.success);
      case StatusChipTone.warning:
        return (x.warningContainer, x.onWarningContainer, x.gold);
      case StatusChipTone.error:
        return (cs.errorContainer, cs.onErrorContainer, cs.error);
      case StatusChipTone.gold:
        return (
          context.isDark ? SparklingColors.goldDeep : SparklingColors.goldLight,
          context.isDark ? SparklingColors.goldLight : SparklingColors.onGold,
          SparklingColors.goldDeep,
        );
      case StatusChipTone.live:
        return (x.successContainer, x.onSuccessContainer, x.success);
      case StatusChipTone.onDark:
        return (Colors.white.withValues(alpha: 0.16), Colors.white, x.success);
    }
  }
}
