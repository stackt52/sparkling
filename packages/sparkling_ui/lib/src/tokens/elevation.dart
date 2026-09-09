import 'package:flutter/painting.dart';

import 'colors.dart';

/// Shadows. Surfaces are flat tonal (M3); shadows appear only on the FAB,
/// bottom sheets and the podium avatar glow.
abstract final class SparklingElevation {
  /// `0 8px 20px rgba(0,160,224,.35)`
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x5900A0E0), offset: Offset(0, 8), blurRadius: 20),
  ];

  /// `0 -12px 32px rgba(0,0,0,.4)`
  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, -12), blurRadius: 32),
  ];

  /// Gold glow behind the leaderboard winner avatar.
  static const List<BoxShadow> podiumGlow = [
    BoxShadow(color: Color(0x80E2BA5F), blurRadius: 28, spreadRadius: 2),
  ];

  /// Azure glow used on the scan line (`box-shadow: 0 0 14px #00A0E0`).
  static const List<BoxShadow> scanLine = [
    BoxShadow(color: SparklingColors.azure, blurRadius: 14),
  ];

  /// No shadow — the default for cards/tiles.
  static const List<BoxShadow> none = [];
}
