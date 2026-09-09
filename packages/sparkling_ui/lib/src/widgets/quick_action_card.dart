import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Tonal quick-action card ("Book a wash" / "Repair quote") with a 42px icon
/// tile (r14). [primary] uses primaryContainer; otherwise secondaryContainer.
class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.primary = true,
    this.onTap,
    this.height = 140,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool primary;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final bg = primary ? cs.primaryContainer : cs.secondaryContainer;
    final fg = primary ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    final tileBg = primary
        ? cs.primary
        : (dark ? cs.secondary : SparklingColors.navy);
    final tileFg = primary
        ? cs.onPrimary
        : (dark ? cs.onSecondary : Colors.white);
    final radius = BorderRadius.circular(SparklingShapes.card);

    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: height,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(
                      SparklingShapes.iconTileSmall,
                    ),
                  ),
                  child: Icon(icon, color: tileFg, size: 22, fill: 1),
                ),
                const Spacer(),
                Text(
                  title,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 17,
                    color: fg,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: fg.withValues(alpha: 0.75),
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
