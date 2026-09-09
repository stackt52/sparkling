import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Gamification badge tile (2e): earned = coloured icon; locked = 45% opacity
/// with a lock glyph.
class BadgeTile extends StatelessWidget {
  const BadgeTile({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.earned = true,
    this.onTap,
    this.size = 92,
  });

  final String label;
  final IconData icon;

  /// Icon colour when earned (badge `colour` from the API).
  final Color? color;
  final bool earned;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final br = BorderRadius.circular(SparklingShapes.card);
    return Semantics(
      label: earned ? '$label badge, earned' : '$label badge, locked',
      button: onTap != null,
      child: Opacity(
        opacity: earned ? 1 : 0.45,
        child: Material(
          color: cs.surfaceContainer,
          borderRadius: br,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            child: SizedBox(
              width: size,
              height: size + 8,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    earned ? icon : Symbols.lock_rounded,
                    size: 30,
                    fill: 1,
                    color: earned ? (color ?? cs.primary) : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      earned ? label : 'Locked',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.labelLarge.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
