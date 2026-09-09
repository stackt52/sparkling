import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Staff screen header: small overline ("Glen Village · Bay team") above a
/// 28px headline ("My tasks"), with an optional trailing widget (sync chip,
/// filter tile, segmented control).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 16),
  });

  final String title;
  final String? overline;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overline != null)
                  Text(
                    overline!,
                    style: SparklingTypography.bodyLarge.copyWith(
                      fontSize: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  title,
                  style: SparklingTypography.headlineLarge.copyWith(
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}
