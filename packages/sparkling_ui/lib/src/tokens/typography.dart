import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Outfit type ramp from the design handoff plus a mono face for plates,
/// VINs and refs (UX-001).
///
/// Sizes follow the mockups (px == logical px):
/// * display 700 34–40 · headline 600 19–22 · title 600 14.5–16
/// * body 400 12.5–13.5 lh 1.5 · label 500–700 10–12.5
/// * overline 10.5 uppercase +.06em
abstract final class SparklingTypography {
  /// When `false`, [font] and [mono] return plain [TextStyle]s that reference
  /// the family name without asking google_fonts to fetch it. Widget tests
  /// (no network) should set this to `false`; apps keep the default.
  static bool useGoogleFonts = true;

  static const String outfitFamily = 'Outfit';
  static const String monoFamily = 'JetBrains Mono';

  /// Outfit text style (falls back to the platform sans when fonts are off).
  static TextStyle font({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    if (useGoogleFonts) {
      return GoogleFonts.outfit(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    return TextStyle(
      fontFamily: outfitFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// Monospace style for plates, VINs, refs (JetBrains Mono).
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    if (useGoogleFonts) {
      return GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }
    return TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // ---- Ramp --------------------------------------------------------------
  static TextStyle get displayLarge => font(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.5,
  );
  static TextStyle get displayMedium => font(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.4,
  );
  static TextStyle get displaySmall => font(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.3,
  );

  static TextStyle get headlineLarge => font(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.3,
  );
  static TextStyle get headlineMedium => font(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
  );
  static TextStyle get headlineSmall =>
      font(fontSize: 19, fontWeight: FontWeight.w600, height: 1.2);

  static TextStyle get titleLarge =>
      font(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get titleMedium =>
      font(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get titleSmall =>
      font(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3);

  static TextStyle get bodyLarge =>
      font(fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle get bodyMedium =>
      font(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle get bodySmall =>
      font(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get labelLarge =>
      font(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get labelMedium =>
      font(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get labelSmall => font(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.2,
  );

  /// 10.5px uppercase, letter-spacing .06em. Apply `.toUpperCase()` to text.
  static TextStyle get overline => font(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.63,
  );

  /// Plate / VIN / ref style (mono, 13px, medium).
  static TextStyle get monoBody =>
      mono(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4);

  /// Larger mono for refs in headers.
  static TextStyle get monoTitle =>
      mono(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3);

  /// Full M3 [TextTheme] built from the ramp.
  static TextTheme textTheme(Color onSurface, Color onSurfaceVariant) =>
      TextTheme(
        displayLarge: displayLarge.copyWith(color: onSurface),
        displayMedium: displayMedium.copyWith(color: onSurface),
        displaySmall: displaySmall.copyWith(color: onSurface),
        headlineLarge: headlineLarge.copyWith(color: onSurface),
        headlineMedium: headlineMedium.copyWith(color: onSurface),
        headlineSmall: headlineSmall.copyWith(color: onSurface),
        titleLarge: titleLarge.copyWith(color: onSurface),
        titleMedium: titleMedium.copyWith(color: onSurface),
        titleSmall: titleSmall.copyWith(color: onSurface),
        bodyLarge: bodyLarge.copyWith(color: onSurface),
        bodyMedium: bodyMedium.copyWith(color: onSurface),
        bodySmall: bodySmall.copyWith(color: onSurfaceVariant),
        labelLarge: labelLarge.copyWith(color: onSurface),
        labelMedium: labelMedium.copyWith(color: onSurface),
        labelSmall: labelSmall.copyWith(color: onSurfaceVariant),
      );
}
