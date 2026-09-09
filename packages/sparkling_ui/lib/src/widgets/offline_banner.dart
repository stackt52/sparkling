import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Gold-tinted offline banner (screen 1l / CUS-054): cloud_off icon,
/// "You're offline · Showing status from HH:MM" and a Retry action.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.lastSyncLabel,
    this.title = "You're offline",
    this.onRetry,
    this.retryLabel = 'Retry',
    this.margin = EdgeInsets.zero,
  });

  /// e.g. `'20:47'` → "Showing status from 20:47".
  final String? lastSyncLabel;
  final String title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final bg = dark
        ? SparklingColors.goldDeep.withValues(alpha: 0.16)
        : SparklingColors.lightWarningContainer;
    final fg = dark
        ? SparklingColors.goldLight
        : SparklingColors.lightOnWarningContainer;
    final subtitle = lastSyncLabel == null
        ? 'Changes will sync when you reconnect'
        : 'Showing status from $lastSyncLabel';

    return Padding(
      padding: margin,
      child: Semantics(
        liveRegion: true,
        label: '$title. $subtitle',
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(SparklingShapes.tile),
            border: Border.all(
              color: SparklingColors.goldDeep.withValues(
                alpha: dark ? 0.6 : 0.35,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Symbols.cloud_off_rounded, color: fg, size: 22, fill: 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: SparklingTypography.titleSmall.copyWith(color: fg),
                    ),
                    Text(
                      subtitle,
                      style: SparklingTypography.bodySmall.copyWith(
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(retryLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
