import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// Visual variant of a [PillButton].
enum PillButtonVariant {
  /// Filled primary.
  filled,

  /// Tonal (primaryContainer).
  tonal,

  /// Outlined.
  outlined,

  /// White pill on a navy/gradient card ("Track service").
  whiteOnNavy,

  /// Filled brand navy (light) / primary (dark) — "Redeem", "Export CSV".
  navy,

  /// Outlined in the error colour ("Mark blocked").
  outlinedError,
}

/// Pill-shaped button, min height 48 (UX-006), optional leading icon and
/// loading state.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PillButtonVariant.filled,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.minHeight = SparklingSpacing.touchTargetStaff,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Stretch to the available width.
  final bool expand;

  /// Replaces the icon with a small spinner and disables the button.
  final bool loading;
  final double minHeight;

  /// Smaller padding / 40px height for inline uses (e.g. "Redeem").
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final height = dense ? 40.0 : minHeight;
    final padding = EdgeInsets.symmetric(horizontal: dense ? 16 : 22);

    final ButtonStyle style = switch (variant) {
      PillButtonVariant.filled => FilledButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
      ),
      PillButtonVariant.tonal => FilledButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      PillButtonVariant.outlined => OutlinedButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
      ),
      PillButtonVariant.whiteOnNavy => FilledButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
        backgroundColor: Colors.white,
        foregroundColor: SparklingColors.navy,
      ),
      PillButtonVariant.navy => FilledButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
        backgroundColor: dark ? cs.primary : SparklingColors.navy,
        foregroundColor: dark ? cs.onPrimary : Colors.white,
      ),
      PillButtonVariant.outlinedError => OutlinedButton.styleFrom(
        minimumSize: Size(64, height),
        padding: padding,
        foregroundColor: cs.error,
        side: BorderSide(color: cs.error.withValues(alpha: 0.7), width: 1.5),
      ),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: 18),
        ],
      ],
    );

    final effectiveOnPressed = loading ? null : onPressed;
    final Widget button = switch (variant) {
      PillButtonVariant.outlined ||
      PillButtonVariant.outlinedError => OutlinedButton(
        onPressed: effectiveOnPressed,
        style: style,
        child: content,
      ),
      _ => FilledButton(
        onPressed: effectiveOnPressed,
        style: style,
        child: content,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
