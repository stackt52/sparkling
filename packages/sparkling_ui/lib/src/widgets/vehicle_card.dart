import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/shapes.dart';
import '../tokens/typography.dart';
import 'status_chip.dart';

/// 200px-wide horizontal vehicle card: car icon, verification chip, model
/// title and plate in mono (screen 1a).
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.title,
    required this.plate,
    this.verified = false,
    this.verifiedLabel = 'Disc verified',
    this.manualLabel = 'Manual entry',
    this.selected = false,
    this.width = 200,
    this.onTap,
  });

  /// e.g. `'Corolla Cross'`.
  final String title;

  /// e.g. `'KL 45 MN GP'`.
  final String plate;
  final bool verified;
  final String verifiedLabel;
  final String manualLabel;
  final bool selected;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(SparklingShapes.card);

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$title, $plate, ${verified ? verifiedLabel : manualLabel}',
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainer,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      Symbols.directions_car_rounded,
                      color: cs.primary,
                      fill: 1,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: StatusChip(
                        label: verified ? verifiedLabel : manualLabel,
                        tone: verified
                            ? StatusChipTone.success
                            : StatusChipTone.neutral,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  plate,
                  style: SparklingTypography.monoBody.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
