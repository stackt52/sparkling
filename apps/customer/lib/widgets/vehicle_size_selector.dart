import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'common.dart';

/// Small / Large / Bike segmented control with the example hint underneath.
/// Drives the small / large catalogue price (vehicles.size_class).
class VehicleSizeSelector extends StatelessWidget {
  const VehicleSizeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Vehicle size',
    this.fromDisc = false,
  });

  final VehicleSize value;
  final ValueChanged<VehicleSize> onChanged;
  final String label;

  /// Prefilled from the licence-disc description.
  final bool fromDisc;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: SparklingTypography.labelLarge.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedPills(
          labels: VehicleSize.values.map((s) => s.label).toList(),
          selected: value.index,
          onSelected: (i) {
            AppHaptics.selection(context);
            onChanged(VehicleSize.values[i]);
          },
        ),
        const SizedBox(height: 6),
        Text(
          '${value.hint}${fromDisc ? ' · from your licence disc' : ''}. '
          'Sets the small / large wash price.',
          style: SparklingTypography.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// "Large" / "Bike" chip shown on vehicle cards and pickers.
class VehicleSizeChip extends StatelessWidget {
  const VehicleSizeChip({super.key, required this.size});
  final VehicleSize size;

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: size.label, tone: StatusChipTone.neutral, dense: true);
}
