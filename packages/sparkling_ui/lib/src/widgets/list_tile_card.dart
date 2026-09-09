import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/shapes.dart';

/// Generic surfaceContainer tile (r22) with optional leading / trailing
/// widgets and border tint. Use for task cards, inventory items, ledger rows.
class ListTileCard extends StatelessWidget {
  const ListTileCard({
    super.key,
    this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.borderWidth = 1.5,
    this.color,
    this.radius = SparklingShapes.card,
    this.opacity = 1,
  }) : assert(child != null || title != null, 'Provide a child or a title');

  /// Full custom content (ignores title/subtitle/leading/trailing).
  final Widget? child;
  final Widget? title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Optional border (e.g. error for blocked, gold for overdue SLA).
  final Color? borderColor;
  final double borderWidth;
  final Color? color;
  final double radius;

  /// Fades the whole card (done steps at 65%).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final br = BorderRadius.circular(radius);

    final body =
        child ??
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: context.text.titleMedium!,
                    child: title!,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: context.text.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        );

    return Opacity(
      opacity: opacity,
      child: Material(
        color: color ?? cs.surfaceContainer,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: br,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: borderWidth),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
