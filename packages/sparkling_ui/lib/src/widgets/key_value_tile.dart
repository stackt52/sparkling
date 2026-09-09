import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Field tile from the scan-review screen (1e): overline label + value.
/// Options: mono value (reg/VIN), locked icon (non-editable), warning border
/// (disc expiry), trailing widget.
class KeyValueTile extends StatelessWidget {
  const KeyValueTile({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.locked = false,
    this.warning = false,
    this.trailing,
    this.onTap,
    this.helper,
  });

  final String label;
  final String value;
  final bool mono;
  final bool locked;

  /// Gold warning border + helper tint.
  final bool warning;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Small line under the value (e.g. "Expires in 3 months").
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final br = BorderRadius.circular(SparklingShapes.tile);
    final valueStyle = mono
        ? SparklingTypography.mono(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: cs.onSurface,
          )
        : SparklingTypography.titleLarge.copyWith(color: cs.onSurface);

    return Semantics(
      label: '$label: $value${locked ? ', locked' : ''}',
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: br,
              border: warning
                  ? Border.all(color: SparklingColors.goldDeep, width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: SparklingTypography.overline.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(value, style: valueStyle),
                      if (helper != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          helper!,
                          style: SparklingTypography.bodySmall.copyWith(
                            color: warning
                                ? (context.isDark
                                      ? SparklingColors.goldLight
                                      : SparklingColors.onGold)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
                if (locked)
                  Icon(
                    Symbols.lock_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                    fill: 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
