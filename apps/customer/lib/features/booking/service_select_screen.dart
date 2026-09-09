import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'booking_flow.dart';
import 'booking_widgets.dart';

/// Step 1 of 3 — choose outlet, vehicle and service (1b).
class ServiceSelectScreen extends StatefulWidget {
  const ServiceSelectScreen({super.key});

  @override
  State<ServiceSelectScreen> createState() => _ServiceSelectScreenState();
}

class _ServiceSelectScreenState extends State<ServiceSelectScreen> {
  List<Outlet>? _outlets;
  List<Vehicle>? _vehicles;
  List<OutletService>? _services;
  Object? _error;
  String? _servicesForOutlet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_outlets == null && _error == null) _load();
  }

  BookingFlowController get _flow => context.bookingFlow;

  Future<void> _load() async {
    setState(() => _error = null);
    final repos = context.repos;
    try {
      final results = await Future.wait([
        repos.catalogue.outlets(),
        repos.customer.vehicles(),
      ]);
      final outlets = results[0] as List<Outlet>;
      final vehicles = results[1] as List<Vehicle>;
      if (!mounted) return;
      // Defaults: keep the restored draft, otherwise nearest outlet + first car.
      if (_flow.outlet == null && outlets.isNotEmpty) {
        final sorted = [
          ...outlets,
        ]..sort((a, b) => (a.distanceKm ?? 1e9).compareTo(b.distanceKm ?? 1e9));
        _flow.setOutlet(sorted.first);
      }
      if (_flow.vehicle == null && vehicles.isNotEmpty) {
        _flow.setVehicle(vehicles.first);
      }
      setState(() {
        _outlets = outlets;
        _vehicles = vehicles;
      });
      await _loadServices();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadServices() async {
    final outlet = _flow.outlet;
    if (outlet == null) return;
    if (_servicesForOutlet == outlet.id && _services != null) return;
    setState(() {
      _services = null;
      _servicesForOutlet = outlet.id;
    });
    try {
      final list = await context.repos.catalogue.outletServices(outlet.id);
      if (!mounted || _flow.outlet?.id != outlet.id) return;
      final washes =
          list
              .where(
                (s) =>
                    s.category == ServiceCategory.carWash &&
                    !s.service.isQuoteBased,
              )
              .toList()
            ..sort((a, b) => a.priceCents.compareTo(b.priceCents));
      setState(() => _services = washes);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickOutlet() async {
    final outlets = _outlets;
    if (outlets == null) return;
    final chosen = await showOutletPicker(
      context,
      outlets: outlets,
      selectedId: _flow.outlet?.id,
    );
    if (chosen == null || !mounted) return;
    _flow.setOutlet(chosen);
    await _loadServices();
  }

  Future<void> _pickVehicle() async {
    final vehicles = _vehicles ?? const <Vehicle>[];
    final chosen = await showVehiclePicker(
      context,
      vehicles: vehicles,
      selectedId: _flow.vehicle?.id,
    );
    if (chosen != null) _flow.setVehicle(chosen);
  }

  void _next() {
    if (_flow.vehicle == null) {
      showSnack(context, 'Choose a vehicle first.');
      _pickVehicle();
      return;
    }
    if (!_flow.canPickSlot) return;
    AppHaptics.light(context);
    context.push(Routes.bookSlot);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _flow,
          builder: (context, _) {
            final flow = _flow;
            return Column(
              children: [
                BookingStepHeader(
                  title: 'Book a wash',
                  step: 1,
                  subtitle: 'Choose service',
                ),
                Expanded(
                  child: _error != null
                      ? ErrorView(error: _error, onRetry: _load)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          children: [
                            OutletSelectorCard(
                              outlet: flow.outlet,
                              onTap: _pickOutlet,
                            ),
                            const SizedBox(height: 20),
                            SectionHeader(
                              title: 'Wash services',
                              trailing: VehicleChip(
                                vehicle: flow.vehicle,
                                onTap: _pickVehicle,
                              ),
                            ),
                            if (flow.restoredAt != null && flow.service != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InfoBanner(
                                  tone: InfoTone.info,
                                  icon: Symbols.history_rounded,
                                  text:
                                      'Draft restored from ${SparklingDates.relativeSlot(flow.restoredAt!)}.',
                                ),
                              ),
                            if (_services == null)
                              const LoadingView()
                            else if (_services!.isEmpty)
                              EmptyState(
                                icon: Symbols.local_car_wash_rounded,
                                title: 'No wash services here',
                                message: 'Try another outlet.',
                                actionLabel: 'Change outlet',
                                onAction: _pickOutlet,
                              )
                            else
                              for (final s in _services!) ...[
                                _ServiceCard(
                                  service: s,
                                  selected: flow.service?.id == s.id,
                                  onSelect: () {
                                    AppHaptics.selection(context);
                                    flow.setService(s);
                                  },
                                ),
                                const SizedBox(height: 10),
                              ],
                          ],
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: BottomActionBar(
                    leadingLabel: 'Selected',
                    leadingValue: flow.service == null
                        ? '—'
                        : Money.formatZarCompact(flow.service!.priceCents)
                              .replaceFirst('R', 'R '),
                    child: PillButton(
                      label: 'Choose date & time',
                      trailingIcon: Symbols.arrow_forward_rounded,
                      expand: true,
                      onPressed: flow.service == null ? null : _next,
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.selected,
    required this.onSelect,
  });

  final OutletService service;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final s = service;
    final points = s.pointsEstimate > 0
        ? s.pointsEstimate
        : (s.priceCents / 100 * s.service.pointsPerRand).round();
    return RadioCard(
      selected: selected,
      enabled: s.isAvailable,
      onChanged: (_) => onSelect(),
      radioPosition: RadioCardRadioPosition.trailing,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      leading: Icon(
        serviceIcon(s.service.icon),
        color: cs.primary,
        fill: 1,
        size: 26,
      ),
      title: Text(
        s.name,
        style: SparklingTypography.titleLarge.copyWith(fontSize: 18),
      ),
      subtitle: Text(
        [
          if (s.service.description != null) s.service.description!,
          '${s.durationMinutes} min',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: SparklingTypography.bodyMedium.copyWith(fontSize: 14),
      ),
      footer: selected && points > 0
          ? Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    color: context.isDark
                        ? cs.surfaceContainerHigh
                        : Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.sell_rounded,
                        size: 15,
                        color: context.sparkling.gold,
                        fill: 1,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Earn $points pts',
                        style: SparklingTypography.labelLarge.copyWith(
                          fontSize: 13,
                          color: context.isDark
                              ? SparklingColors.goldLight
                              : SparklingColors.onGold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      trailing: Text(
        Money.formatZarCompact(s.priceCents).replaceFirst('R', 'R '),
        style: SparklingTypography.headlineSmall.copyWith(
          fontSize: 20,
          color: selected ? cs.onPrimaryContainer : cs.onSurface,
        ),
      ),
    );
  }
}
