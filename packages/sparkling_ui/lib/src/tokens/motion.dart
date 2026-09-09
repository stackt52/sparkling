import 'package:flutter/widgets.dart';

/// M3 Expressive motion tokens (UX-004).
abstract final class SparklingMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 500);

  /// Spring-ish default for value changes (rings, bars).
  static const Duration spring = Duration(milliseconds: 400);

  /// Continuous loops (scan line).
  static const Duration loop = Duration(milliseconds: 1800);

  /// Emphasized easing for container transforms / shared axis.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Overshooting curve for scale-ins (confirmation blob, ring sweep).
  static const Curve overshoot = Curves.easeOutBack;

  /// Standard decelerate for enters.
  static const Curve enter = Curves.easeOutCubic;

  /// Standard accelerate for exits.
  static const Curve exit = Curves.easeInCubic;

  /// `true` when non-essential animation should be disabled: honours
  /// `MediaQuery.disableAnimations` (OS accessibility) and an app-level
  /// override supplied through [SparklingMotionScope] (profile `reduced_motion`).
  static bool reducedMotion(BuildContext context) {
    final scope = SparklingMotionScope.maybeOf(context);
    if (scope != null && scope.reducedMotion) return true;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Returns [duration] or [Duration.zero] when motion is reduced.
  static Duration durationFor(BuildContext context, Duration duration) =>
      reducedMotion(context) ? Duration.zero : duration;
}

/// App-level reduced-motion override. Wrap your `MaterialApp` (or a subtree)
/// with `SparklingMotionScope(reducedMotion: profile.reducedMotion, child: …)`.
class SparklingMotionScope extends InheritedWidget {
  const SparklingMotionScope({
    super.key,
    required this.reducedMotion,
    required super.child,
  });

  final bool reducedMotion;

  static SparklingMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SparklingMotionScope>();

  @override
  bool updateShouldNotify(SparklingMotionScope oldWidget) =>
      oldWidget.reducedMotion != reducedMotion;
}
