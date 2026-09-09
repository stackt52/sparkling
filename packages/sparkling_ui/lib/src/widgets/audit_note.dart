import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/typography.dart';

/// Small inline note with an icon ("Actor, time and reason are recorded",
/// "Works offline — steps queue …"). Subtle: no background by default.
class AuditNote extends StatelessWidget {
  const AuditNote({
    super.key,
    required this.text,
    this.icon = Symbols.history_rounded,
    this.iconColor,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String text;
  final IconData icon;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            child: Icon(
              icon,
              size: 13,
              color: iconColor ?? cs.onPrimaryContainer,
              fill: 1,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: SparklingTypography.bodyMedium.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
