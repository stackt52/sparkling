import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';

/// Stock level state (STF-040).
enum LevelState { ok, low, out }

/// Rounded level bar coloured by state: ok = success, low = #FFB59F / warning,
/// out = empty red track. Also usable as a generic progress bar with
/// [LinearLevelBar.progress] (azure gradient fill).
class LinearLevelBar extends StatelessWidget {
  const LinearLevelBar({
    super.key,
    required this.value,
    this.state = LevelState.ok,
    this.height = 8,
    this.trackColor,
    this.gradient,
  }) : assert(value >= 0 && value <= 1);

  /// Azure-gradient progress bar (checklist progress, tier progress).
  const LinearLevelBar.progress({
    super.key,
    required this.value,
    this.height = 8,
    this.trackColor,
    this.gradient = SparklingColors.azureBarGradient,
  }) : state = LevelState.ok,
       assert(value >= 0 && value <= 1);

  /// 0…1
  final double value;
  final LevelState state;
  final double height;
  final Color? trackColor;

  /// When set, fills with this gradient instead of the state colour.
  final Gradient? gradient;

  static LevelState stateFor({required num onHand, required num threshold}) {
    if (onHand <= 0) return LevelState.out;
    if (onHand <= threshold) return LevelState.low;
    return LevelState.ok;
  }

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    final cs = context.colors;
    final fill = switch (state) {
      LevelState.ok => x.success,
      LevelState.low =>
        context.isDark ? SparklingColors.darkError : SparklingColors.goldDeep,
      LevelState.out => cs.error,
    };
    final track =
        trackColor ??
        x.outlineTrack.withValues(alpha: context.isDark ? 1 : 0.55);
    final reduced = SparklingMotion.reducedMotion(context);

    return Semantics(
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Container(color: track),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduced ? value : 0, end: value),
                  duration: reduced ? Duration.zero : SparklingMotion.spring,
                  curve: SparklingMotion.emphasized,
                  builder: (context, v, _) => Container(
                    width: constraints.maxWidth * v,
                    decoration: BoxDecoration(
                      color: gradient == null ? fill : null,
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
