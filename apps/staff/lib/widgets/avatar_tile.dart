import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'palette.dart';

/// Tint of an [AvatarTile]. Cycles through the palette seen in the mockups
/// (azure, gold, steel, sage, rose, lilac).
enum AvatarTone { azure, gold, steel, sage, rose, lilac, primary }

/// Rounded initials tile (44–64px, r14–18) used in team rows, assign sheet,
/// leaderboard rows and the profile.
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    super.key,
    required this.initials,
    this.size = 44,
    this.radius,
    this.tone = AvatarTone.azure,
    this.semanticLabel,
  });

  final String initials;
  final double size;
  final double? radius;
  final AvatarTone tone;
  final String? semanticLabel;

  /// Stable tone for a name / id so the same person keeps the same colour.
  static AvatarTone toneFor(String key) {
    const tones = [
      AvatarTone.azure,
      AvatarTone.gold,
      AvatarTone.steel,
      AvatarTone.sage,
      AvatarTone.rose,
      AvatarTone.lilac,
    ];
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return tones[h % tones.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final (Color bg, Color fg) = switch (tone) {
      AvatarTone.azure => (
        dark ? cs.primary : SparklingColors.lightPrimaryContainer,
        dark ? cs.onPrimary : SparklingColors.lightOnPrimaryContainer,
      ),
      AvatarTone.primary => (cs.primaryContainer, cs.onPrimaryContainer),
      AvatarTone.gold => (SparklingColors.goldDeep, SparklingColors.onGold),
      AvatarTone.steel => (StaffPalette.avatarSteel, StaffPalette.avatarSteelOn),
      AvatarTone.sage => (
        dark ? StaffPalette.avatarSageDark : SparklingColors.lightSuccessContainer,
        dark ? StaffPalette.avatarSageDarkOn : SparklingColors.lightOnSuccessContainer,
      ),
      AvatarTone.rose => (StaffPalette.avatarRose, StaffPalette.avatarRoseOn),
      AvatarTone.lilac => (StaffPalette.avatarLilac, StaffPalette.avatarLilacOn),
    };
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius ?? size * 0.32),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: SparklingTypography.font(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}
