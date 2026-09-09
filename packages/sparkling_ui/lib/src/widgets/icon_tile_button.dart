import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';

/// Tone of an [IconTileButton].
enum IconTileTone { tonal, navy, primary, onDark, outlined }

/// 44px rounded (r16) icon tile — back button, notification bell, avatar,
/// torch toggle, camera, timer.
class IconTileButton extends StatelessWidget {
  const IconTileButton({
    super.key,
    this.icon,
    this.child,
    this.onPressed,
    this.tone = IconTileTone.tonal,
    this.size = SparklingSpacing.touchTarget,
    this.radius = SparklingShapes.iconTile,
    this.tooltip,
    this.selected = false,
    this.fill,
  }) : assert(icon != null || child != null, 'Provide an icon or a child');

  final IconData? icon;

  /// Custom content (e.g. initials text for an avatar).
  final Widget? child;
  final VoidCallback? onPressed;
  final IconTileTone tone;
  final double size;
  final double radius;
  final String? tooltip;

  /// Selected state (torch on) → primary tint.
  final bool selected;

  /// Material Symbols fill (defaults to 1 when [selected]).
  final double? fill;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final (Color bg, Color fg, BorderSide side) = switch (tone) {
      IconTileTone.tonal => (
        cs.surfaceContainer,
        cs.onSurface,
        BorderSide.none,
      ),
      IconTileTone.navy => (
        dark ? cs.primaryContainer : SparklingColors.navy,
        dark ? cs.onPrimaryContainer : Colors.white,
        BorderSide.none,
      ),
      IconTileTone.primary => (
        cs.primaryContainer,
        cs.onPrimaryContainer,
        BorderSide.none,
      ),
      IconTileTone.onDark => (
        Colors.white.withValues(alpha: 0.14),
        Colors.white,
        BorderSide.none,
      ),
      IconTileTone.outlined => (
        Colors.transparent,
        cs.onSurface,
        BorderSide(color: cs.outline, width: 1.5),
      ),
    };
    final effectiveBg = selected ? cs.primary : bg;
    final effectiveFg = selected ? cs.onPrimary : fg;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

    final button = Material(
      color: effectiveBg,
      shape: shape,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child:
                child ??
                Icon(
                  icon,
                  color: effectiveFg,
                  size: size * 0.5,
                  fill: fill ?? (selected ? 1 : 0),
                ),
          ),
        ),
      ),
    );

    return Semantics(
      button: onPressed != null,
      label: tooltip,
      selected: selected,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}
