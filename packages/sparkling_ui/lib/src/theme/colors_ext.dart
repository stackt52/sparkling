import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Custom colour roles that M3 [ColorScheme] does not carry.
///
/// Read with `Theme.of(context).extension<SparklingColorsExt>()!` or the
/// shorthand [SparklingColorsExtX.sparkling] on a [ThemeData]/[BuildContext].
@immutable
class SparklingColorsExt extends ThemeExtension<SparklingColorsExt> {
  const SparklingColorsExt({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.gold,
    required this.onGold,
    required this.goldGradient,
    required this.heroGradient,
    required this.azure,
    required this.navy,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.outlineTrack,
    required this.offlineRing,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Solid gold (deep end of the gradient) for borders/text accents.
  final Color gold;
  final Color onGold;
  final LinearGradient goldGradient;
  final LinearGradient heroGradient;
  final Color azure;
  final Color navy;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;

  /// Track colour for progress bars / level bars.
  final Color outlineTrack;

  /// Desaturated ring colour while offline.
  final Color offlineRing;

  static const SparklingColorsExt light = SparklingColorsExt(
    success: SparklingColors.lightSuccess,
    onSuccess: SparklingColors.lightOnSuccess,
    successContainer: SparklingColors.lightSuccessContainer,
    onSuccessContainer: SparklingColors.lightOnSuccessContainer,
    warningContainer: SparklingColors.lightWarningContainer,
    onWarningContainer: SparklingColors.lightOnWarningContainer,
    gold: SparklingColors.goldDeep,
    onGold: SparklingColors.onGold,
    goldGradient: SparklingColors.goldGradient,
    heroGradient: SparklingColors.heroGradientLight,
    azure: SparklingColors.azure,
    navy: SparklingColors.navy,
    surfaceContainer: SparklingColors.lightSurfaceContainer,
    surfaceContainerHigh: SparklingColors.lightSurfaceContainerHigh,
    outlineTrack: SparklingColors.lightOutline,
    offlineRing: SparklingColors.offlineRing,
  );

  static const SparklingColorsExt dark = SparklingColorsExt(
    success: SparklingColors.darkSuccess,
    onSuccess: SparklingColors.darkOnSuccess,
    successContainer: SparklingColors.darkSuccessContainer,
    onSuccessContainer: SparklingColors.darkOnSuccessContainer,
    warningContainer: SparklingColors.darkWarningContainer,
    onWarningContainer: SparklingColors.darkOnWarningContainer,
    gold: SparklingColors.goldDeep,
    onGold: SparklingColors.onGold,
    goldGradient: SparklingColors.goldGradient,
    heroGradient: SparklingColors.heroGradientDark,
    azure: SparklingColors.azure,
    navy: SparklingColors.navy,
    surfaceContainer: SparklingColors.darkSurfaceContainer,
    surfaceContainerHigh: SparklingColors.darkSurfaceContainerHigh,
    outlineTrack: SparklingColors.darkOutline,
    offlineRing: SparklingColors.offlineRing,
  );

  @override
  SparklingColorsExt copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? gold,
    Color? onGold,
    LinearGradient? goldGradient,
    LinearGradient? heroGradient,
    Color? azure,
    Color? navy,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? outlineTrack,
    Color? offlineRing,
  }) {
    return SparklingColorsExt(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      gold: gold ?? this.gold,
      onGold: onGold ?? this.onGold,
      goldGradient: goldGradient ?? this.goldGradient,
      heroGradient: heroGradient ?? this.heroGradient,
      azure: azure ?? this.azure,
      navy: navy ?? this.navy,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      outlineTrack: outlineTrack ?? this.outlineTrack,
      offlineRing: offlineRing ?? this.offlineRing,
    );
  }

  @override
  SparklingColorsExt lerp(ThemeExtension<SparklingColorsExt>? other, double t) {
    if (other is! SparklingColorsExt) return this;
    return SparklingColorsExt(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      gold: Color.lerp(gold, other.gold, t)!,
      onGold: Color.lerp(onGold, other.onGold, t)!,
      goldGradient: LinearGradient.lerp(goldGradient, other.goldGradient, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      azure: Color.lerp(azure, other.azure, t)!,
      navy: Color.lerp(navy, other.navy, t)!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceContainerHigh: Color.lerp(
        surfaceContainerHigh,
        other.surfaceContainerHigh,
        t,
      )!,
      outlineTrack: Color.lerp(outlineTrack, other.outlineTrack, t)!,
      offlineRing: Color.lerp(offlineRing, other.offlineRing, t)!,
    );
  }
}

/// Convenience accessors.
extension SparklingColorsExtX on BuildContext {
  /// The Sparkling extension colours for the current theme.
  SparklingColorsExt get sparkling =>
      Theme.of(this).extension<SparklingColorsExt>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? SparklingColorsExt.dark
          : SparklingColorsExt.light);

  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
