import 'package:flutter/painting.dart';

/// Raw colour tokens from the Sparkling design handoff (UX-001).
///
/// Prefer reading colours from `Theme.of(context).colorScheme` and
/// [SparklingColorsExt] inside widgets; use these constants only when building
/// themes or when a value must be identical in both brightnesses (brand).
abstract final class SparklingColors {
  // ---- Brand -------------------------------------------------------------
  /// Brand navy — logo background, hero cards, dark accents.
  static const Color navy = Color(0xFF203060);

  /// Brand azure — logo car swoosh, gradients, live indicators.
  static const Color azure = Color(0xFF00A0E0);

  /// Deep azure used at the end of azure gradients.
  static const Color azureDeep = Color(0xFF0074B8);

  /// Scan screen / camera scrim background.
  static const Color scrim = Color(0xFF0B1018);

  // ---- Light scheme ------------------------------------------------------
  static const Color lightPrimary = Color(0xFF006398);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFCBE6FF);
  static const Color lightOnPrimaryContainer = Color(0xFF001D31);
  static const Color lightSecondary = navy;
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightSecondaryContainer = Color(0xFFD7E3F9);
  static const Color lightOnSecondaryContainer = Color(0xFF14243D);
  static const Color lightSurface = Color(0xFFF6FAFD);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFF1F6FA);
  static const Color lightSurfaceContainer = Color(0xFFEBF1F7);
  static const Color lightSurfaceContainerHigh = Color(0xFFE1EAF2);
  static const Color lightSurfaceContainerHighest = Color(0xFFD7E2EC);
  static const Color lightOnSurface = Color(0xFF16212B);
  static const Color lightOnSurfaceVariant = Color(0xFF51606F);
  static const Color lightOutline = Color(0xFFC3CFDA);
  static const Color lightOutlineVariant = Color(0xFFDCE5EE);
  static const Color lightError = Color(0xFFBA1A1A);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFFFDAD6);
  static const Color lightOnErrorContainer = Color(0xFF93000A);
  static const Color lightSuccess = Color(0xFF1D8A4E);
  static const Color lightOnSuccess = Color(0xFFFFFFFF);
  static const Color lightSuccessContainer = Color(0xFFC9F0D8);
  static const Color lightOnSuccessContainer = Color(0xFF0D5C32);
  static const Color lightWarningContainer = Color(0xFFFFE6B8);
  static const Color lightOnWarningContainer = Color(0xFF7A5000);
  static const Color lightInverseSurface = Color(0xFF2B3642);
  static const Color lightOnInverseSurface = Color(0xFFEEF3F8);

  // ---- Dark scheme -------------------------------------------------------
  static const Color darkPrimary = Color(0xFF8BD2FF);
  static const Color darkOnPrimary = Color(0xFF00344F);
  static const Color darkPrimaryContainer = Color(0xFF0F3550);
  static const Color darkOnPrimaryContainer = Color(0xFFCBE8FF);
  static const Color darkSecondary = Color(0xFFB9C7E6);
  static const Color darkOnSecondary = Color(0xFF203060);
  static const Color darkSecondaryContainer = Color(0xFF2B3C58);
  static const Color darkOnSecondaryContainer = Color(0xFFD7E3F9);
  static const Color darkSurface = Color(0xFF0D1524);
  static const Color darkSurfaceContainerLowest = Color(0xFF080E1A);
  static const Color darkSurfaceContainerLow = Color(0xFF111A2C);
  static const Color darkSurfaceContainer = Color(0xFF151F33);
  static const Color darkSurfaceContainerHigh = Color(0xFF1B2942);
  static const Color darkSurfaceContainerHighest = Color(0xFF1D2942);
  static const Color darkOnSurface = Color(0xFFE3E9F4);
  static const Color darkOnSurfaceVariant = Color(0xFF98A6BB);
  static const Color darkOutline = Color(0xFF2B3C58);
  static const Color darkOutlineVariant = Color(0xFF223250);
  static const Color darkError = Color(0xFFFFB59F);
  static const Color darkOnError = Color(0xFF5C1900);
  static const Color darkErrorContainer = Color(0xFF3B1B12);
  static const Color darkOnErrorContainer = Color(0xFFFFB59F);
  static const Color darkSuccess = Color(0xFF6EE7A0);
  static const Color darkOnSuccess = Color(0xFF003919);
  static const Color darkSuccessContainer = Color(0xFF14352A);
  static const Color darkOnSuccessContainer = Color(0xFF6EE7A0);
  static const Color darkWarningContainer = Color(0xFF3A2E12);
  static const Color darkOnWarningContainer = Color(0xFFF3DDA4);
  static const Color darkInverseSurface = Color(0xFFE3E9F4);
  static const Color darkOnInverseSurface = Color(0xFF16212B);

  /// Desaturated ring colour used when the app is offline (screen 1l).
  static const Color offlineRing = Color(0xFF5A7A94);

  // ---- Gold (loyalty) ----------------------------------------------------
  static const Color goldLight = Color(0xFFF3DDA4);
  static const Color goldDeep = Color(0xFFE2BA5F);
  static const Color onGold = Color(0xFF5C4200);

  // ---- Gradients ---------------------------------------------------------
  /// `linear-gradient(135deg, #F3DDA4, #E2BA5F)`
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, goldDeep],
  );

  /// `linear-gradient(135deg, #00A0E0, #0074B8)`
  static const LinearGradient azureGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [azure, azureDeep],
  );

  /// Progress-bar fill inside navy cards: azure → light azure.
  static const LinearGradient azureBarGradient = LinearGradient(
    colors: [azure, Color(0xFF8BD2FF)],
  );

  /// `linear-gradient(130deg, #203060 30%, #0A5F96 80%, #00A0E0)`
  static const LinearGradient heroGradientLight = LinearGradient(
    begin: Alignment(-1, -0.7),
    end: Alignment(1, 0.7),
    stops: [0.30, 0.80, 1.0],
    colors: [navy, Color(0xFF0A5F96), azure],
  );

  /// `linear-gradient(130deg, #1B2942 20%, #0A4F7D 75%, #0083C4)`
  static const LinearGradient heroGradientDark = LinearGradient(
    begin: Alignment(-1, -0.7),
    end: Alignment(1, 0.7),
    stops: [0.20, 0.75, 1.0],
    colors: [Color(0xFF1B2942), Color(0xFF0A4F7D), Color(0xFF0083C4)],
  );

  /// Navy → gold tier card gradient (screen 1i).
  static const LinearGradient loyaltyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.55, 1.0],
    colors: [navy, Color(0xFF2C3E6E), Color(0xFF6E5A3A)],
  );
}
