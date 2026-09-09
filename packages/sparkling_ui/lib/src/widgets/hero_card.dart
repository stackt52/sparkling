import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import '../tokens/spacing.dart';

/// Gradient feature card (r28) used for "Next booking", stage cards, the
/// loyalty tier card and the admin revenue hero.
///
/// Defaults to the theme hero gradient (navy → azure). Use [HeroCard.navy]
/// for a solid brand-navy card and [HeroCard.gold] for the navy → gold
/// loyalty card. Text inside inherits white via [DefaultTextStyle].
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    this.child,
    this.gradient,
    this.color,
    this.padding = const EdgeInsets.all(SparklingSpacing.cardPaddingLoose),
    this.radius = SparklingShapes.hero,
    this.showOrbs = true,
    this.onTap,
    this.height,
    this.width,
  });

  /// Solid brand navy (#203060).
  const HeroCard.navy({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(SparklingSpacing.cardPaddingLoose),
    this.radius = SparklingShapes.hero,
    this.showOrbs = false,
    this.onTap,
    this.height,
    this.width,
  }) : gradient = null,
       color = SparklingColors.navy;

  /// Navy → gold loyalty tier card (screen 1i).
  const HeroCard.gold({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(SparklingSpacing.cardPaddingLoose),
    this.radius = SparklingShapes.hero,
    this.showOrbs = true,
    this.onTap,
    this.height,
    this.width,
  }) : gradient = SparklingColors.loyaltyGradient,
       color = null;

  final Widget? child;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Draws the translucent decorative circles seen in the mockups.
  final bool showOrbs;
  final VoidCallback? onTap;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final gradient = color == null
        ? (this.gradient ?? context.sparkling.heroGradient)
        : null;
    final borderRadius = BorderRadius.circular(radius);

    Widget body = DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: Padding(padding: padding, child: child),
      ),
    );

    if (showOrbs) {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -40,
            top: -60,
            child: _Orb(size: 200, opacity: 0.10),
          ),
          Positioned(
            right: 40,
            bottom: -70,
            child: _Orb(size: 150, opacity: 0.08),
          ),
          body,
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: Ink(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: borderRadius,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: ClipRRect(borderRadius: borderRadius, child: body),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    ),
  );
}
