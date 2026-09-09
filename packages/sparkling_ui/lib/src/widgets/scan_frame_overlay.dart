import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/motion.dart';

/// PDF417 scanner overlay (1d): #0B1018 scrim, r28 viewfinder with four
/// azure corner brackets (42px, 4px stroke), a looping glowing scan line and
/// an optional torch tile slot in the corner.
///
/// Place it in a [Stack] above the camera preview; the viewfinder region is
/// transparent so the preview shows through.
class ScanFrameOverlay extends StatefulWidget {
  const ScanFrameOverlay({
    super.key,
    this.viewfinderAspectRatio = 2.4,
    this.viewfinderRadius = 28,
    this.horizontalInset = 24,
    this.scanning = true,
    this.success = false,
    this.torch,
    this.hint,
    this.scrimColor = SparklingColors.scrim,
    this.scrimOpacity = 0.86,
  });

  /// Width / height of the viewfinder (licence discs are wide barcodes).
  final double viewfinderAspectRatio;
  final double viewfinderRadius;
  final double horizontalInset;

  /// Animates the scan line while `true`.
  final bool scanning;

  /// Flashes the brackets green (success flash before container-transform).
  final bool success;

  /// Widget placed at the top-right of the viewfinder (torch toggle).
  final Widget? torch;

  /// Widget shown under the viewfinder (hint banner).
  final Widget? hint;
  final Color scrimColor;
  final double scrimOpacity;

  @override
  State<ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SparklingMotion.loop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ScanFrameOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduced = SparklingMotion.reducedMotion(context);
    if (widget.scanning && !reduced) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.success
        ? SparklingColors.darkSuccess
        : SparklingColors.azure;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - widget.horizontalInset * 2;
        final height = width / widget.viewfinderAspectRatio;
        final rect = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight * 0.42,
          ),
          width: width,
          height: height,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ScrimPainter(
                hole: rect,
                radius: widget.viewfinderRadius,
                color: widget.scrimColor.withValues(alpha: widget.scrimOpacity),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BracketsPainter(
                        color: accent,
                        radius: 18,
                        length: 42,
                        stroke: 4,
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final y =
                          14 +
                          (height - 28) *
                              Curves.easeInOut.transform(_controller.value);
                      return Positioned(
                        left: 18,
                        right: 18,
                        top: y,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: accent,
                                blurRadius: SparklingElevation
                                    .scanLine
                                    .first
                                    .blurRadius,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (widget.torch != null)
                    Positioned(right: 12, top: 12, child: widget.torch!),
                ],
              ),
            ),
            if (widget.hint != null)
              Positioned(
                left: widget.horizontalInset,
                right: widget.horizontalInset,
                top: rect.bottom + 20,
                child: widget.hint!,
              ),
          ],
        );
      },
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({
    required this.hole,
    required this.radius,
    required this.color,
  });
  final Rect hole;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    final path = Path.combine(PathOperation.difference, full, cut);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color || old.radius != radius;
}

class _BracketsPainter extends CustomPainter {
  _BracketsPainter({
    required this.color,
    required this.radius,
    required this.length,
    required this.stroke,
  });
  final Color color;
  final double radius;
  final double length;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final r = radius;
    final l = length;
    final w = size.width;
    final h = size.height;
    final o = stroke / 2;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(o, l)
        ..lineTo(o, r + o)
        ..arcToPoint(Offset(r + o, o), radius: Radius.circular(r))
        ..lineTo(l, o),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - l, o)
        ..lineTo(w - r - o, o)
        ..arcToPoint(Offset(w - o, r + o), radius: Radius.circular(r))
        ..lineTo(w - o, l),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w - o, h - l)
        ..lineTo(w - o, h - r - o)
        ..arcToPoint(Offset(w - r - o, h - o), radius: Radius.circular(r))
        ..lineTo(w - l, h - o),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(l, h - o)
        ..lineTo(r + o, h - o)
        ..arcToPoint(Offset(o, h - r - o), radius: Radius.circular(r))
        ..lineTo(o, h - l),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BracketsPainter old) => old.color != color;
}
