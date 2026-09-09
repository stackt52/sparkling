import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Tone of an [InfoBanner].
enum InfoTone { info, success, warning, error, azure }

/// Tinted banner with icon, optional title and action (success banner on scan
/// review, expectation banner on quote request, alert banner on inventory).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.title,
    this.tone = InfoTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.bordered = false,
    this.margin = EdgeInsets.zero,
  });

  final String text;
  final String? title;
  final InfoTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool bordered;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final dark = context.isDark;
    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      InfoTone.info => (
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        Symbols.info_rounded,
      ),
      InfoTone.success => (
        x.successContainer,
        x.onSuccessContainer,
        Symbols.task_alt_rounded,
      ),
      InfoTone.warning => (
        x.warningContainer,
        x.onWarningContainer,
        Symbols.warning_rounded,
      ),
      InfoTone.error => (
        cs.errorContainer,
        cs.onErrorContainer,
        Symbols.notification_important_rounded,
      ),
      InfoTone.azure => (
        SparklingColors.azure.withValues(alpha: dark ? 0.16 : 0.12),
        dark ? SparklingColors.darkPrimary : SparklingColors.lightPrimary,
        Symbols.offline_bolt_rounded,
      ),
    };

    return Padding(
      padding: margin,
      child: Semantics(
        label: title == null ? text : '$title. $text',
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(SparklingShapes.tile),
            border: bordered
                ? Border.all(color: fg.withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? defaultIcon, color: fg, size: 20, fill: 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: SparklingTypography.titleSmall.copyWith(
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      text,
                      style: SparklingTypography.bodyMedium.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
