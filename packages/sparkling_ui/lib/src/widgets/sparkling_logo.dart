import 'package:flutter/material.dart';

/// The Sparkling wordmark. Picks `logo-light.png` on light surfaces and the
/// white-text `logo-dark.png` on dark/navy surfaces.
///
/// Pass [onDark] to force the variant (e.g. inside a navy hero card in light
/// mode).
class SparklingLogo extends StatelessWidget {
  const SparklingLogo({
    super.key,
    this.height = 36,
    this.onDark,
    this.semanticLabel = 'Sparkling Auto Care Centres',
  });

  /// Rendered height; width scales with the image aspect ratio.
  final double height;

  /// `true` → white variant, `false` → colour variant, `null` → by brightness.
  final bool? onDark;

  final String semanticLabel;

  static const String lightAsset = 'assets/logo-light.png';
  static const String darkAsset = 'assets/logo-dark.png';
  static const String package = 'sparkling_ui';

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? darkAsset : lightAsset,
      package: package,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.medium,
    );
  }
}
