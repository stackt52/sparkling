import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';

/// Diagonally striped placeholder for photo slots (quote attachments,
/// checklist proof). Optional caption, remove badge and dashed "add" variant.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({
    super.key,
    this.size = 88,
    this.width,
    this.height,
    this.caption,
    this.onRemove,
    this.onTap,
    this.radius = SparklingShapes.tile,
    this.child,
  }) : dashed = false,
       icon = null;

  /// Dashed-border add tile with a camera / add icon.
  const PhotoPlaceholder.add({
    super.key,
    this.size = 88,
    this.width,
    this.height,
    this.onTap,
    this.icon = Symbols.add_a_photo_rounded,
    this.radius = SparklingShapes.tile,
    this.caption,
  }) : dashed = true,
       onRemove = null,
       child = null;

  final double size;
  final double? width;
  final double? height;
  final String? caption;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final double radius;
  final bool dashed;
  final IconData? icon;

  /// Replaces the stripes (e.g. an actual [Image]).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final w = width ?? size;
    final h = height ?? size;
    final br = BorderRadius.circular(radius);

    Widget body;
    if (dashed) {
      body = CustomPaint(
        painter: _DashedBorderPainter(color: cs.outline, radius: radius),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.primary, size: 26),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  style: SparklingTypography.labelMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } else {
      body = ClipRRect(
        borderRadius: br,
        child:
            child ??
            CustomPaint(
              painter: _StripesPainter(
                background: cs.surfaceContainerHigh,
                stripe: cs.onSurfaceVariant.withValues(alpha: 0.12),
              ),
              child: caption == null
                  ? null
                  : Center(
                      child: Text(
                        caption!,
                        textAlign: TextAlign.center,
                        style: SparklingTypography.mono(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
      );
    }

    return Semantics(
      label: dashed ? 'Add photo' : (caption ?? 'Photo'),
      button: onTap != null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: br,
              child: SizedBox(width: w, height: h, child: body),
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: -6,
              top: -6,
              child: Material(
                color: cs.error,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      Symbols.close_rounded,
                      size: 14,
                      color: cs.onError,
                      weight: 700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter({required this.background, required this.stripe});
  final Color background;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = 8;
    final diag = size.width + size.height;
    for (double x = -size.height; x < diag; x += 18) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) =>
      old.background != background || old.stripe != stripe;
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
