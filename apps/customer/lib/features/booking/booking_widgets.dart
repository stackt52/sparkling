import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../widgets/common.dart';

/// Header + 3-segment progress strip shared by the booking steps.
class BookingStepHeader extends StatelessWidget {
  const BookingStepHeader({
    super.key,
    required this.title,
    required this.step,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final int step;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScreenHeader(
          title: title,
          subtitle: 'Step $step of 3 · $subtitle',
          onBack: onBack,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: StepProgressStrip(current: step, total: 3),
        ),
      ],
    );
  }
}

/// Navy outlet selector card (1b) — opens [showOutletPicker].
class OutletSelectorCard extends StatelessWidget {
  const OutletSelectorCard({
    super.key,
    required this.outlet,
    required this.onTap,
    this.compact = false,
  });

  final Outlet? outlet;
  final VoidCallback onTap;
  final bool compact;

  String _meta(Outlet o) {
    final hours = o.hoursFor(DateTime.now().weekday);
    return [
      o.rating.toStringAsFixed(1),
      if (o.distanceLabel != null) o.distanceLabel!,
      if (hours != null) 'Open until ${hours[1]}' else 'Closed today',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final cs = context.colors;
    final fg = dark ? cs.onPrimaryContainer : Colors.white;
    final bg = dark ? cs.primaryContainer : context.sparkling.navy;
    final o = outlet;
    final radius = BorderRadius.circular(SparklingShapes.card);
    return Semantics(
      button: true,
      label: o == null ? 'Choose outlet' : 'Outlet ${o.name}',
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Row(
              children: [
                Container(
                  width: compact ? 44 : 56,
                  height: compact ? 44 : 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: dark ? 0.10 : 0.14),
                    borderRadius: BorderRadius.circular(SparklingShapes.tile),
                  ),
                  child: Icon(
                    Symbols.storefront_rounded,
                    color: dark ? cs.primary : const Color(0xFF8BD2FF),
                    fill: 1,
                    size: compact ? 22 : 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o?.name ?? 'Choose an outlet',
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 17,
                          color: fg,
                        ),
                      ),
                      if (o != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Symbols.star_rounded,
                              size: 15,
                              color: SparklingColors.goldDeep,
                              fill: 1,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _meta(o),
                                style: SparklingTypography.bodyMedium.copyWith(
                                  fontSize: 13.5,
                                  color: fg.withValues(alpha: 0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Symbols.unfold_more_rounded,
                  color: fg.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal outlet picker sheet with rating + distance (1b interaction).
Future<Outlet?> showOutletPicker(
  BuildContext context, {
  required List<Outlet> outlets,
  String? selectedId,
}) {
  return showModalBottomSheet<Outlet>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final cs = context.colors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Choose outlet'),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: outlets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final o = outlets[i];
                    final hours = o.hoursFor(DateTime.now().weekday);
                    return RadioCard(
                      selected: o.id == selectedId,
                      onChanged: (_) => Navigator.of(context).pop(o),
                      leading: Icon(
                        Symbols.storefront_rounded,
                        color: cs.primary,
                        fill: 1,
                      ),
                      title: Text(o.name),
                      subtitle: Text(
                        [
                          o.addressLabel,
                          if (hours != null) '${hours[0]}–${hours[1]}',
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Symbols.star_rounded,
                                size: 15,
                                color: SparklingColors.goldDeep,
                                fill: 1,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                o.rating.toStringAsFixed(1),
                                style: SparklingTypography.labelLarge.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          if (o.distanceLabel != null)
                            Text(
                              o.distanceLabel!,
                              style: SparklingTypography.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Modal vehicle picker sheet; offers "Add vehicle" when the list is empty.
Future<Vehicle?> showVehiclePicker(
  BuildContext context, {
  required List<Vehicle> vehicles,
  String? selectedId,
}) {
  return showModalBottomSheet<Vehicle>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final cs = sheetContext.colors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Which vehicle?',
                actionLabel: 'Add',
                onAction: () {
                  Navigator.of(sheetContext).pop();
                  context.push(Routes.vehicleAdd);
                },
              ),
              if (vehicles.isEmpty)
                EmptyState(
                  icon: Symbols.directions_car_rounded,
                  title: 'No vehicles yet',
                  message: 'Scan your licence disc or enter the details.',
                  actionLabel: 'Add vehicle',
                  onAction: () {
                    Navigator.of(sheetContext).pop();
                    context.push(Routes.vehicleAdd);
                  },
                ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final v = vehicles[i];
                    return RadioCard(
                      selected: v.id == selectedId,
                      onChanged: (_) => Navigator.of(context).pop(v),
                      leading: Icon(
                        Symbols.directions_car_rounded,
                        color: cs.primary,
                        fill: 1,
                      ),
                      title: Text(
                        v.displayName.isEmpty ? v.shortName : v.displayName,
                      ),
                      subtitle: Text(
                        v.registrationNo,
                        style: SparklingTypography.monoBody.copyWith(
                          letterSpacing: 1.2,
                        ),
                      ),
                      trailing: StatusChip(
                        label: v.discVerified ? 'Disc verified' : 'Manual',
                        tone: v.discVerified
                            ? StatusChipTone.success
                            : StatusChipTone.neutral,
                        dense: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Small "car + plate" chip used on the service list header (1b).
class VehicleChip extends StatelessWidget {
  const VehicleChip({super.key, required this.vehicle, required this.onTap});
  final Vehicle? vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      button: true,
      label: vehicle == null
          ? 'Choose vehicle'
          : 'Vehicle ${vehicle!.registrationNo}',
      child: InkWell(
        borderRadius: SparklingShapes.pillRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.directions_car_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
                fill: 1,
              ),
              const SizedBox(width: 6),
              Text(
                vehicle?.registrationNo ?? 'Choose vehicle',
                style: SparklingTypography.mono(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
