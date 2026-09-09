import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'colors_ext.dart';

/// Builds the M3 Expressive [ThemeData] for the Sparkling apps (UX-001/002).
///
/// ```dart
/// MaterialApp(theme: SparklingTheme.light(), darkTheme: SparklingTheme.dark())
/// ```
abstract final class SparklingTheme {
  static ThemeData light() => _build(lightScheme, SparklingColorsExt.light);

  static ThemeData dark() => _build(darkScheme, SparklingColorsExt.dark);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: SparklingColors.lightPrimary,
    onPrimary: SparklingColors.lightOnPrimary,
    primaryContainer: SparklingColors.lightPrimaryContainer,
    onPrimaryContainer: SparklingColors.lightOnPrimaryContainer,
    secondary: SparklingColors.lightSecondary,
    onSecondary: SparklingColors.lightOnSecondary,
    secondaryContainer: SparklingColors.lightSecondaryContainer,
    onSecondaryContainer: SparklingColors.lightOnSecondaryContainer,
    tertiary: SparklingColors.azure,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD3F1FF),
    onTertiaryContainer: Color(0xFF00394F),
    error: SparklingColors.lightError,
    onError: SparklingColors.lightOnError,
    errorContainer: SparklingColors.lightErrorContainer,
    onErrorContainer: SparklingColors.lightOnErrorContainer,
    surface: SparklingColors.lightSurface,
    onSurface: SparklingColors.lightOnSurface,
    onSurfaceVariant: SparklingColors.lightOnSurfaceVariant,
    surfaceContainerLowest: SparklingColors.lightSurfaceContainerLowest,
    surfaceContainerLow: SparklingColors.lightSurfaceContainerLow,
    surfaceContainer: SparklingColors.lightSurfaceContainer,
    surfaceContainerHigh: SparklingColors.lightSurfaceContainerHigh,
    surfaceContainerHighest: SparklingColors.lightSurfaceContainerHighest,
    outline: SparklingColors.lightOutline,
    outlineVariant: SparklingColors.lightOutlineVariant,
    inverseSurface: SparklingColors.lightInverseSurface,
    onInverseSurface: SparklingColors.lightOnInverseSurface,
    inversePrimary: SparklingColors.darkPrimary,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: SparklingColors.darkPrimary,
    onPrimary: SparklingColors.darkOnPrimary,
    primaryContainer: SparklingColors.darkPrimaryContainer,
    onPrimaryContainer: SparklingColors.darkOnPrimaryContainer,
    secondary: SparklingColors.darkSecondary,
    onSecondary: SparklingColors.darkOnSecondary,
    secondaryContainer: SparklingColors.darkSecondaryContainer,
    onSecondaryContainer: SparklingColors.darkOnSecondaryContainer,
    tertiary: SparklingColors.azure,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFF0A4F7D),
    onTertiaryContainer: Color(0xFFD3F1FF),
    error: SparklingColors.darkError,
    onError: SparklingColors.darkOnError,
    errorContainer: SparklingColors.darkErrorContainer,
    onErrorContainer: SparklingColors.darkOnErrorContainer,
    surface: SparklingColors.darkSurface,
    onSurface: SparklingColors.darkOnSurface,
    onSurfaceVariant: SparklingColors.darkOnSurfaceVariant,
    surfaceContainerLowest: SparklingColors.darkSurfaceContainerLowest,
    surfaceContainerLow: SparklingColors.darkSurfaceContainerLow,
    surfaceContainer: SparklingColors.darkSurfaceContainer,
    surfaceContainerHigh: SparklingColors.darkSurfaceContainerHigh,
    surfaceContainerHighest: SparklingColors.darkSurfaceContainerHighest,
    outline: SparklingColors.darkOutline,
    outlineVariant: SparklingColors.darkOutlineVariant,
    inverseSurface: SparklingColors.darkInverseSurface,
    onInverseSurface: SparklingColors.darkOnInverseSurface,
    inversePrimary: SparklingColors.lightPrimary,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static ThemeData _build(ColorScheme scheme, SparklingColorsExt ext) {
    final textTheme = SparklingTypography.textTheme(
      scheme.onSurface,
      scheme.onSurfaceVariant,
    );
    final isDark = scheme.brightness == Brightness.dark;
    final pillButtonPadding = const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 12,
    );
    final buttonText = SparklingTypography.labelLarge.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      extensions: [ext],
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: 22,
        fill: 0,
        weight: 400,
        opticalSize: 24,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark
            ? scheme.primaryContainer
            : SparklingColors.lightPrimaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            fill: selected ? 1 : 0,
            weight: selected ? 500 : 400,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return SparklingTypography.labelMedium.copyWith(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        useIndicator: true,
        selectedIconTheme: IconThemeData(
          color: scheme.onPrimaryContainer,
          fill: 1,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          fill: 0,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, SparklingSpacing.touchTargetStaff),
          shape: const StadiumBorder(),
          padding: pillButtonPadding,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, SparklingSpacing.touchTargetStaff),
          shape: const StadiumBorder(),
          padding: pillButtonPadding,
          textStyle: buttonText,
          elevation: 0,
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, SparklingSpacing.touchTargetStaff),
          shape: const StadiumBorder(),
          padding: pillButtonPadding,
          textStyle: buttonText,
          side: BorderSide(color: scheme.outline, width: 1.5),
          foregroundColor: scheme.primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, SparklingSpacing.touchTarget),
          shape: const StadiumBorder(),
          textStyle: buttonText,
          foregroundColor: scheme.primary,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            SparklingSpacing.touchTarget,
            SparklingSpacing.touchTarget,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: SparklingShapes.radius(SparklingShapes.iconTile),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? scheme.primary : SparklingColors.azure,
        foregroundColor: isDark ? scheme.onPrimary : Colors.white,
        elevation: 6,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: SparklingShapes.radius(SparklingShapes.fab),
        ),
        extendedTextStyle: SparklingTypography.titleMedium.copyWith(
          fontSize: 16,
        ),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: isDark ? scheme.primaryContainer : SparklingColors.navy,
        secondarySelectedColor: scheme.primaryContainer,
        checkmarkColor: isDark ? scheme.onPrimaryContainer : Colors.white,
        labelStyle: SparklingTypography.labelLarge.copyWith(
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: SparklingTypography.labelLarge.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        showCheckmark: true,
        elevation: 0,
        pressElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: SparklingShapes.cardShape,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        shape: SparklingShapes.tileShape,
        tileColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: scheme.onSurfaceVariant,
        minVerticalPadding: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: SparklingShapes.tileRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: SparklingShapes.tileRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SparklingShapes.tileRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: SparklingShapes.tileRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: SparklingShapes.tileRadius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return scheme.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: ext.outlineTrack,
        circularTrackColor: ext.outlineTrack,
        linearMinHeight: 8,
        borderRadius: SparklingShapes.pillRadius,
        strokeCap: StrokeCap.round,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: SparklingShapes.sheetShape,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(40, 4),
        clipBehavior: Clip.antiAlias,
        shadowColor: SparklingElevation.sheet.first.color,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: SparklingShapes.dialogShape,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: isDark
            ? SparklingColors.lightPrimary
            : scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: SparklingShapes.tileRadius),
        insetPadding: const EdgeInsets.all(SparklingSpacing.gutter),
        elevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide.none,
          backgroundColor: scheme.surfaceContainer,
          selectedBackgroundColor: isDark
              ? scheme.primary
              : SparklingColors.navy,
          selectedForegroundColor: isDark ? scheme.onPrimary : Colors.white,
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: buttonText,
          minimumSize: const Size(0, 48),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        dividerColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: SparklingColors.azure,
        textColor: Colors.white,
        smallSize: 9,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SparklingShapes.tileRadius),
        textStyle: textTheme.bodyMedium,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
