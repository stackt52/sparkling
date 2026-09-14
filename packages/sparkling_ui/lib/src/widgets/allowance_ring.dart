import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/typography.dart';
import 'progress_ring.dart';

/// Allowance progress for one plan entitlement: a ring showing what is left
/// ("3/4" in the centre) with a title and caption beside it, e.g.
/// "Sparkling Washes · 3 of 4 left · resets 5 Oct".
///
/// Colours default to the ambient [DefaultTextStyle] so the widget works on a
/// plan card as well as on a plain surface.
class AllowanceRing extends StatelessWidget {
  const AllowanceRing({
    super.key,
    required this.remaining,
    required this.quantity,
    required this.title,
    this.caption,
    this.size = 56,
    this.color,
    this.trackColor,
    this.foreground,
    this.mutedForeground,
  });

  final int remaining;
  final int quantity;

  /// "Sparkling Washes"
  final String title;

  /// "3 of 4 left · resets 5 Oct"
  final String? caption;
  final double size;

  /// Ring sweep colour (defaults to the text colour).
  final Color? color;
  final Color? trackColor;

  /// Title / centre label colour (defaults to the ambient text colour).
  final Color? foreground;
  final Color? mutedForeground;

  double get value =>
      quantity <= 0 ? 0 : (remaining / quantity).clamp(0, 1).toDouble();

  @override
  Widget build(BuildContext context) {
    final ambient = DefaultTextStyle.of(context).style.color ??
        context.colors.onSurface;
    final fg = foreground ?? ambient;
    final muted = mutedForeground ?? fg.withValues(alpha: 0.72);
    final sweep = color ?? fg;
    final exhausted = remaining <= 0;
    return Semantics(
      label: '$title: $remaining of $quantity left',
      child: Row(
        children: [
          ProgressRing(
            value: value,
            size: size,
            strokeWidth: 6,
            color: sweep,
            trackColor: trackColor ?? fg.withValues(alpha: 0.18),
            semanticLabel: '$remaining of $quantity',
            child: Text(
              '$remaining/$quantity',
              style: SparklingTypography.font(
                fontSize: size * 0.26,
                fontWeight: FontWeight.w800,
                height: 1,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SparklingTypography.titleMedium.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (caption != null)
                  Text(
                    exhausted ? '$caption · used up' : caption!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      fontSize: 13.5,
                      color: muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
