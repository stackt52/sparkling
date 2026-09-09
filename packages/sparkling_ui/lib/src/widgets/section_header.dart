import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/typography.dart';

/// "Your vehicles  ·  Manage" style section header: title on the left,
/// optional text action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Custom trailing widget (takes precedence over [actionLabel]).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: SparklingTypography.headlineSmall.copyWith(
                fontSize: 19,
                color: cs.onSurface,
              ),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: SparklingTypography.titleSmall.copyWith(
                  color: cs.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
