import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import '../quotes/quote_request_screen.dart';
import 'booking_flow.dart';
import 'booking_widgets.dart';

/// Step 1 of 3 — choose outlet, vehicle and service (1b).
///
/// Offers are grouped under the catalogue groups (Car Wash Options,
/// Combinations, Auto Body Repair); prices resolve for the selected
/// vehicle's size ("From R x"), composites show what they include, `excl`
/// offers carry a VAT note, by-quote offers route to a quotation request
/// and add-ons of the chosen service's group appear as checkbox cards.
class ServiceSelectScreen extends StatefulWidget {
  const ServiceSelectScreen({super.key});

  @override
  State<ServiceSelectScreen> createState() => _ServiceSelectScreenState();
}

class _ServiceSelectScreenState extends State<ServiceSelectScreen> {
  List<Outlet>? _outlets;
  List<Vehicle>? _vehicles;
  OutletCatalogue? _catalogue;
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
    unawaited(_flow.loadMembership());
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
    if (_servicesForOutlet == outlet.id && _catalogue != null) return;
    setState(() {
      _catalogue = null;
      _servicesForOutlet = outlet.id;
    });
    try {
      final catalogue = await context.repos.catalogue.outletServices(outlet.id);
      if (!mounted || _flow.outlet?.id != outlet.id) return;
      setState(() => _catalogue = catalogue);
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

  void _select(OutletService s) {
    if (s.isByQuote) {
      AppHaptics.light(context);
      context.push(
        Routes.quoteNew,
        extra: QuoteRequestArgs(
          service: s,
          outlet: _flow.outlet,
          vehicle: _flow.vehicle,
        ),
      );
      return;
    }
    AppHaptics.selection(context);
    _flow.setService(s);
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
            final size = flow.vehicleSize;
            final catalogue = _catalogue;
            final addons = flow.service == null || catalogue == null
                ? const <OutletService>[]
                : catalogue.addonsFor(flow.service!.groupName);
            return Column(
              children: [
                BookingStepHeader(
                  title: 'Book a service',
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
                              title: 'Services',
                              trailing: VehicleChip(
                                vehicle: flow.vehicle,
                                onTap: _pickVehicle,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                flow.vehicle == null
                                    ? 'Prices are "from" prices for a small vehicle until you choose a vehicle.'
                                    : 'Prices shown for a ${size.label.toLowerCase()} vehicle (${flow.vehicle!.shortName}). "From" prices are minimums.',
                                style: SparklingTypography.bodyMedium.copyWith(
                                  fontSize: 13.5,
                                  color: cs.onSurfaceVariant,
                                ),
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
                            if (catalogue == null)
                              const LoadingView()
                            else if (catalogue.bookableGroups.isEmpty)
                              EmptyState(
                                icon: Symbols.local_car_wash_rounded,
                                title: 'No services here',
                                message: 'Try another outlet.',
                                actionLabel: 'Change outlet',
                                onAction: _pickOutlet,
                              )
                            else
                              for (final group in catalogue.bookableGroups) ...[
                                _GroupHeader(group: group),
                                for (final s in catalogue.offersIn(group)) ...[
                                  ServiceOfferCard(
                                    key: ValueKey('offer-${s.code}'),
                                    service: s,
                                    size: size,
                                    selected: flow.service?.id == s.id,
                                    points: flow.service?.id == s.id
                                        ? flow.pointsEstimate
                                        : null,
                                    included: flow.isCovered(s),
                                    benefitTag: flow.benefitTagFor(s),
                                    onSelect: () => _select(s),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (flow.service?.groupName == group &&
                                    addons.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  const SectionHeader(title: 'Add-ons'),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Added to your ${flow.service!.name}.',
                                      style: SparklingTypography.bodyMedium
                                          .copyWith(
                                            fontSize: 13.5,
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  for (final a in addons) ...[
                                    AddonCard(
                                      key: ValueKey('addon-${a.code}'),
                                      addon: a,
                                      size: size,
                                      selected: flow.hasAddon(a.serviceId),
                                      onChanged: (v) {
                                        AppHaptics.selection(context);
                                        flow.toggleAddon(a, v);
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                                const SizedBox(height: 8),
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
                    leadingLabel: flow.service == null
                        ? 'Selected'
                        : flow.isIncluded
                        ? (flow.addons.isEmpty
                              ? 'Included in your plan'
                              : 'Included · ${flow.addons.length} add-on${flow.addons.length == 1 ? '' : 's'}')
                        : flow.membershipLabel != null
                        ? flow.membershipLabel!
                        : flow.isExclVat
                        ? 'Incl. VAT'
                        : flow.addons.isEmpty
                        ? 'From'
                        : 'From · ${flow.addons.length} add-on${flow.addons.length == 1 ? '' : 's'}',
                    leadingValue: flow.service == null
                        ? '—'
                        : compactZar(flow.quotedCents),
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

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});
  final String group;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final (icon, hint) = switch (group) {
      ServiceGroups.carWashOptions => (
        Symbols.local_car_wash_rounded,
        'Single washes and cleans',
      ),
      ServiceGroups.combinations => (
        Symbols.auto_awesome_rounded,
        'Detailing packages · add-ons available',
      ),
      ServiceGroups.autoBodyRepair => (
        Symbols.car_crash_rounded,
        'Prices excl. VAT · 15% added at checkout',
      ),
      _ => (Symbols.category_rounded, null),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary, fill: 1),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group,
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: SparklingTypography.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Offer card (1b): name, description · duration, "Includes: a · b · c" for
/// composites, VAT note for `excl` offers, resolved "From R x" or "By quote"
/// price, the "Earn N pts" chip when selected and the membership benefit —
/// "Included in your plan" with R 0 for a covered service, or the plan
/// discount tag ("Gold −10%").
class ServiceOfferCard extends StatelessWidget {
  const ServiceOfferCard({
    super.key,
    required this.service,
    required this.size,
    required this.selected,
    required this.onSelect,
    this.points,
    this.included = false,
    this.benefitTag,
  });

  final OutletService service;
  final VehicleSize size;
  final bool selected;
  final VoidCallback onSelect;

  /// Overrides the points chip value (e.g. including add-ons).
  final int? points;

  /// The customer's plan covers this service (allowance left).
  final bool included;

  /// "Included · 3 of 4 left" / "Gold −10%".
  final String? benefitTag;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final s = service;
    final pts = points ?? s.pointsFor(size);
    final includes = s.includesLabel;
    final priceLabel = s.priceLabel(size);
    final fromPrefix = priceLabel.startsWith('From ') && !included;
    final captionStyle = SparklingTypography.bodySmall.copyWith(
      fontSize: 12.5,
      color: selected
          ? cs.onPrimaryContainer.withValues(alpha: 0.85)
          : cs.onSurfaceVariant,
    );
    return RadioCard(
      selected: selected,
      enabled: s.isAvailable,
      onChanged: (_) => onSelect(),
      radioPosition: RadioCardRadioPosition.trailing,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      leading: Icon(
        s.isByQuote ? Symbols.request_quote_rounded : serviceIcon(s.icon),
        color: selected ? cs.onPrimaryContainer : cs.primary,
        fill: 1,
        size: 26,
      ),
      title: Text(
        s.name,
        style: SparklingTypography.titleLarge.copyWith(fontSize: 17),
      ),
      subtitle: Text(
        [
          if (s.description != null) s.description!,
          '${s.durationMinutes} min',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: SparklingTypography.bodyMedium.copyWith(fontSize: 14),
      ),
      footer: (includes == null && !s.isExclVat && !s.isByQuote &&
              benefitTag == null &&
              !(selected && pts > 0))
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (benefitTag != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: MembershipBenefitChip(
                      label: included ? 'Included in your plan' : benefitTag!,
                      detail: included ? benefitTag : null,
                      included: included,
                    ),
                  ),
                if (includes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(
                      TextSpan(
                        text: 'Includes: ',
                        style: captionStyle.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        children: [
                          TextSpan(text: includes, style: captionStyle),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (s.isByQuote)
                  Text(
                    'Priced after an assessment — tap to request a quote.',
                    style: captionStyle,
                  )
                else if (s.isExclVat)
                  Text('Excl. VAT · 15% added at checkout.', style: captionStyle),
                if (selected && pts > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: PointsChip(points: pts),
                      ),
                    ),
                  ),
              ],
            ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fromPrefix)
            Text(
              'From',
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          if (included)
            Text(
              compactZar(s.priceFor(size) ?? 0),
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12,
                decoration: TextDecoration.lineThrough,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          Text(
            s.isByQuote
                ? 'By quote'
                : included
                ? 'R 0'
                : compactZar(s.priceFor(size) ?? 0),
            textAlign: TextAlign.end,
            style: SparklingTypography.headlineSmall.copyWith(
              fontSize: s.isByQuote ? 16 : 19,
              color: included
                  ? (selected ? cs.onPrimaryContainer : x.success)
                  : (selected ? cs.onPrimaryContainer : cs.onSurface),
            ),
          ),
          if (s.isExclVat && !s.isByQuote && !included)
            Text(
              'excl. VAT',
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 11,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Checkbox card for an add-on of the chosen service's group.
class AddonCard extends StatelessWidget {
  const AddonCard({
    super.key,
    required this.addon,
    required this.size,
    required this.selected,
    required this.onChanged,
  });

  final OutletService addon;
  final VehicleSize size;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(SparklingShapes.card);
    final price = addon.priceFor(size);
    return Semantics(
      checked: selected,
      label: 'Add-on ${addon.name}',
      child: AnimatedContainer(
        duration: SparklingMotion.durationFor(context, SparklingMotion.fast),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : cs.surfaceContainer,
          borderRadius: radius,
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: price == null ? null : () => onChanged(!selected),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Symbols.add_circle_rounded,
                    color: cs.primary,
                    fill: selected ? 1 : 0,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          addon.name,
                          style: SparklingTypography.titleMedium.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        if (addon.description != null)
                          Text(
                            addon.description!,
                            style: SparklingTypography.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    price == null ? 'By quote' : '+ ${compactZar(price)}',
                    style: SparklingTypography.titleMedium.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Checkbox(
                    value: selected,
                    onChanged: price == null
                        ? null
                        : (v) => onChanged(v ?? false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Included in your plan · 3 of 4 left" (success tint) or "Gold −10%"
/// (gold tint) tag on an offer card / summary.
class MembershipBenefitChip extends StatelessWidget {
  const MembershipBenefitChip({
    super.key,
    required this.label,
    this.detail,
    this.included = false,
  });

  final String label;
  final String? detail;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final x = context.sparkling;
    final dark = context.isDark;
    final bg = included
        ? x.successContainer
        : (dark ? SparklingColors.goldDeep.withValues(alpha: 0.18) : SparklingColors.goldLight);
    final fg = included
        ? x.onSuccessContainer
        : (dark ? SparklingColors.goldLight : SparklingColors.onGold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            included ? Symbols.check_circle_rounded : Symbols.workspace_premium_rounded,
            size: 15,
            color: fg,
            fill: 1,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              detail == null ? label : '$label · $detail',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SparklingTypography.labelLarge.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
