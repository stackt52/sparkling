import 'package:flutter/painting.dart';

/// Avatar tints seen in the staff mockups (2c/2d/2e) that the shared token
/// sheet does not carry. Kept here as named tokens so no widget hard-codes a
/// colour; `PodiumWidget` in sparkling_ui uses the same steel / rose values.
abstract final class StaffPalette {
  static const Color avatarSteel = Color(0xFFB9C7E6);
  static const Color avatarSteelOn = Color(0xFF203060);
  static const Color avatarRose = Color(0xFFE8B3A0);
  static const Color avatarRoseOn = Color(0xFF5C1900);
  static const Color avatarLilac = Color(0xFFD6B4EA);
  static const Color avatarLilacOn = Color(0xFF3A1F4E);
  static const Color avatarSageDark = Color(0xFF7DC9A3);
  static const Color avatarSageDarkOn = Color(0xFF0D3A24);
}
