import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Sync state shown in the staff app header (STF-062) and offline screens.
enum SyncState { synced, queued, offline }

/// "Synced 09:41" / "3 queued" / "Offline" pill with cloud icon.
class SyncChip extends StatelessWidget {
  const SyncChip({super.key, required this.state, this.label, this.onTap});

  final SyncState state;

  /// Overrides the default label, e.g. `'Synced 09:41'` or `'Last sync 20:47'`.
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final (IconData icon, Color bg, Color fg, String text) = switch (state) {
      SyncState.synced => (
        Symbols.cloud_done_rounded,
        x.successContainer,
        x.onSuccessContainer,
        'Synced',
      ),
      SyncState.queued => (
        Symbols.cloud_sync_rounded,
        context.isDark
            ? SparklingColors.goldDeep.withValues(alpha: 0.18)
            : SparklingColors.goldLight,
        context.isDark ? SparklingColors.goldLight : SparklingColors.onGold,
        'Queued',
      ),
      SyncState.offline => (
        Symbols.cloud_off_rounded,
        cs.surfaceContainerHigh,
        cs.onSurfaceVariant,
        'Offline',
      ),
    };

    return Semantics(
      label: 'Sync status: ${label ?? text}',
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg, fill: 1),
                const SizedBox(width: 6),
                Text(
                  label ?? text,
                  style: SparklingTypography.labelLarge.copyWith(
                    fontSize: 12.5,
                    color: fg,
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
