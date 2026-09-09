import 'package:flutter/material.dart';

import '../theme/colors_ext.dart';

/// Bottom-sheet drag handle (40×4, outline colour). The theme already shows
/// one via `showDragHandle`; use this when building custom sheets.
class DragHandle extends StatelessWidget {
  const DragHandle({
    super.key,
    this.width = 40,
    this.height = 4,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final double width;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: context.colors.outline,
            borderRadius: BorderRadius.circular(height),
          ),
        ),
      ),
    );
  }
}
