import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';

/// Expressive confirmation blob (1g): asymmetric organic shape —
/// primaryContainer outer, primary inner, white check — that scales in with
/// overshoot while azure/gold confetti dots stagger outward. Static when
/// motion is reduced.
class ConfettiBlob extends StatefulWidget {
  const ConfettiBlob({
    super.key,
    this.size = 160,
    this.icon = Symbols.check_rounded,
    this.animate = true,
    this.dotCount = 10,
  });

  final double size;
  final IconData icon;

  /// Set to `false` to render the final frame immediately.
  final bool animate;
  final int dotCount;

  @override
  State<ConfettiBlob> createState() => _ConfettiBlobState();
}

class _ConfettiBlobState extends State<ConfettiBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final List<_Dot> _dots;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _dots = List.generate(widget.dotCount, (i) {
      final angle =
          (i / widget.dotCount) * math.pi * 2 + rnd.nextDouble() * 0.6;
      return _Dot(
        angle: angle,
        distance: 0.62 + rnd.nextDouble() * 0.28,
        radius: 3 + rnd.nextDouble() * 4,
        gold: i.isOdd,
        delay: rnd.nextDouble() * 0.3,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = SparklingMotion.reducedMotion(context) || !widget.animate;
    if (reduced) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final size = widget.size;
    return Semantics(
      label: 'Success',
      child: SizedBox(
        width: size * 1.5,
        height: size * 1.5,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final blobScale = SparklingMotion.overshoot.transform(
              t.clamp(0.0, 0.6) / 0.6,
            );
            final innerScale = SparklingMotion.overshoot.transform(
              ((t - 0.15) / 0.55).clamp(0.0, 1.0),
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(size * 1.5),
                  painter: _DotsPainter(
                    dots: _dots,
                    progress: t,
                    base: size,
                    gold: SparklingColors.goldDeep,
                    azure: SparklingColors.azure,
                  ),
                ),
                Transform.scale(
                  scale: blobScale,
                  child: _Blob(size: size, color: cs.primaryContainer, seed: 0),
                ),
                Transform.scale(
                  scale: innerScale,
                  child: _Blob(
                    size: size * 0.62,
                    color: cs.primary,
                    seed: 1,
                    child: Icon(
                      widget.icon,
                      size: size * 0.35,
                      color: cs.onPrimary,
                      weight: 700,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dot {
  const _Dot({
    required this.angle,
    required this.distance,
    required this.radius,
    required this.gold,
    required this.delay,
  });
  final double angle;
  final double distance;
  final double radius;
  final bool gold;
  final double delay;
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.dots,
    required this.progress,
    required this.base,
    required this.gold,
    required this.azure,
  });
  final List<_Dot> dots;
  final double progress;
  final double base;
  final Color gold;
  final Color azure;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    for (final d in dots) {
      final local = ((progress - 0.3 - d.delay) / 0.6).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final dist = base * d.distance * eased;
      final opacity = local < 0.8 ? 1.0 : (1 - (local - 0.8) / 0.2);
      final paint = Paint()
        ..color = (d.gold ? gold : azure).withValues(
          alpha: opacity.clamp(0.0, 1.0),
        );
      final pos = centre + Offset(math.cos(d.angle), math.sin(d.angle)) * dist;
      canvas.drawCircle(pos, d.radius * (0.6 + 0.4 * eased), paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.progress != progress;
}

/// Organic asymmetric blob: `border-radius: 58% 42% 55% 45% / 48% 60% 40% 52%`.
class _Blob extends StatelessWidget {
  const _Blob({
    required this.size,
    required this.color,
    required this.seed,
    this.child,
  });
  final double size;
  final Color color;
  final int seed;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = size;
    final radius = seed == 0
        ? BorderRadius.only(
            topLeft: Radius.elliptical(s * 0.58, s * 0.48),
            topRight: Radius.elliptical(s * 0.42, s * 0.60),
            bottomRight: Radius.elliptical(s * 0.55, s * 0.40),
            bottomLeft: Radius.elliptical(s * 0.45, s * 0.52),
          )
        : BorderRadius.only(
            topLeft: Radius.elliptical(s * 0.46, s * 0.56),
            topRight: Radius.elliptical(s * 0.54, s * 0.44),
            bottomRight: Radius.elliptical(s * 0.42, s * 0.58),
            bottomLeft: Radius.elliptical(s * 0.58, s * 0.42),
          );
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: child == null ? null : Center(child: child),
    );
  }
}
