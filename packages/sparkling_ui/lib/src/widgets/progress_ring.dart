import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/motion.dart';
import '../tokens/typography.dart';

/// Conic-sweep progress ring (58px in the tracking hero, 48px in the
/// checklist header). Animates with an overshooting spring on value change
/// unless motion is reduced (UX-004).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 58,
    this.strokeWidth = 6,
    this.color,
    this.trackColor,
    this.child,
    this.label,
    this.desaturated = false,
    this.semanticLabel,
  }) : assert(value >= 0 && value <= 1);

  /// 0…1
  final double value;
  final double size;
  final double strokeWidth;

  /// Sweep colour (defaults to azure on dark cards / primary otherwise).
  final Color? color;
  final Color? trackColor;

  /// Custom centre widget. When null and [label] is set, draws the label.
  final Widget? child;

  /// Centre label, e.g. `'58%'` or `'4/7'`.
  final String? label;

  /// Uses the offline (desaturated) ring colour (screen 1l).
  final bool desaturated;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    final sweep = desaturated ? x.offlineRing : (color ?? x.azure);
    final track = trackColor ?? Colors.white.withValues(alpha: 0.18);
    final reduced = SparklingMotion.reducedMotion(context);

    final labelStyle = SparklingTypography.font(
      fontSize: size * 0.28,
      fontWeight: FontWeight.w700,
      height: 1,
    );

    return Semantics(
      label: semanticLabel ?? 'Progress ${(value * 100).round()} percent',
      value: '${(value * 100).round()}%',
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduced ? value : 0, end: value),
          duration: reduced ? Duration.zero : SparklingMotion.spring,
          curve: SparklingMotion.overshoot,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
              value: v.clamp(0.0, 1.0),
              color: sweep,
              track: track,
              stroke: strokeWidth,
            ),
            child: Center(
              child:
                  child ??
                  (label == null
                      ? null
                      : DefaultTextStyle.merge(
                          style: labelStyle,
                          child: Text(label!),
                        )),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(inset, 0, math.pi * 2, false, trackPaint);

    if (value <= 0) return;
    final sweepPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(inset, -math.pi / 2, math.pi * 2 * value, false, sweepPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
