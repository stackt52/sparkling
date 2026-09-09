import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';
import '../tokens/motion.dart';

/// "Step 1 of 3" segmented strip (5px segments, filled primary) used in the
/// booking flow header.
class StepProgressStrip extends StatelessWidget {
  const StepProgressStrip({
    super.key,
    required this.current,
    required this.total,
    this.height = 5,
    this.gap = 6,
  }) : assert(total > 0),
       assert(current >= 0 && current <= total);

  /// Number of completed / active segments (1-based: `current: 1` fills one).
  final int current;
  final int total;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      label: 'Step $current of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: AnimatedContainer(
                duration: SparklingMotion.durationFor(
                  context,
                  SparklingMotion.medium,
                ),
                curve: SparklingMotion.emphasized,
                height: height,
                decoration: BoxDecoration(
                  color: i < current ? cs.primary : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
