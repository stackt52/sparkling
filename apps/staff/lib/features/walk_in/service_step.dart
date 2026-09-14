import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../../widgets/segmented_pills.dart';
import '../quote/raise_quote_controller.dart';
import 'walk_in_flow.dart';
import 'walk_in_widgets.dart';

enum _When { now, slot }

/// Step 3 of 4 — the staff member's outlet (navy card), the outlet catalogue
/// grouped (Car Wash Options / Combinations / Auto Body Repair) with prices
/// resolved for the customer's vehicle size, composites' "Includes", VAT
/// notes, add-ons as checkbox cards, by-quote offers → "Raise quote
/// instead", and "Now (walk-in)" vs a date/slot grid (1c).
class ServiceStep extends StatefulWidget {
  const ServiceStep({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onBack,
    this.daysAhead = 7,
  });

  final WalkInFlowController flow;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final int daysAhead;

  @override
  State<ServiceStep> createState() => _ServiceStepState();
}

class _ServiceStepState extends State<ServiceStep> {
  List<Outlet>? _myOutlets;
  OutletCatalogue? _catalogue;
  String? _servicesForOutlet;
  Object? _error;
  late DateTime _day;
  Future<List<AvailabilitySlot>>? _slots;

  WalkInFlowController get _flow => widget.flow;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_myOutlets == null && _error == null) _load();
    if (_flow.customer != null && _flow.membership == null) {
      unawaited(_flow.loadMembership(context.repositories));
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repos = context.repositories;
    final session = context.session;
    try {
      final all = await repos.catalogue.outlets();
      if (!mounted) return;
      final ids = session.outletIds.isEmpty
          ? [session.outletId]
          : session.outletIds;
      final mine = all.where((o) => ids.contains(o.id)).toList();
      final current =
          _flow.outlet != null && mine.any((o) => o.id == _flow.outlet!.id)
          ? _flow.outlet!
          : (mine.where((o) => o.id == session.outletId).firstOrNull ??
                mine.firstOrNull ??
                all.firstOrNull);
      if (current != null && _flow.outlet?.id != current.id) {
        _flow.setOutlet(current);
      }
      setState(() => _myOutlets = mine.isEmpty ? all : mine);
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
      final catalogue = await context.repositories.catalogue.outletServices(
        outlet.id,
      );
      if (!mounted || _flow.outlet?.id != outlet.id) return;
      setState(() => _catalogue = catalogue);
      if (!_flow.bookNow) _reloadSlots();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickOutlet() async {
    final outlets = _myOutlets;
    if (outlets == null || outlets.length < 2) return;
    final chosen = await showModalBottomSheet<Outlet>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Which outlet?'),
              for (final o in outlets) ...[
                RadioCard(
                  selected: o.id == _flow.outlet?.id,
                  onChanged: (_) => Navigator.of(ctx).pop(o),
                  leading: Icon(
                    Symbols.storefront_rounded,
                    color: ctx.colors.primary,
                    fill: 1,
                  ),
                  title: Text(o.name),
                  subtitle: Text('${o.bayCount} bays'),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _flow.setOutlet(chosen);
    await _loadServices();
  }

  void _reloadSlots() {
    final flow = _flow;
    if (flow.outlet == null || flow.service == null) return;
    setState(() {
      _slots = context.repositories.catalogue.availability(
        outletId: flow.outlet!.id,
        serviceId: flow.service!.id,
        date: _day,
      );
    });
  }

  void _selectDay(DateTime d) {
    if (_day == d) return;
    StaffHaptics.tap(context);
    setState(() => _day = d);
    final start = _flow.slotStart;
    if (start != null &&
        !(start.year == d.year &&
            start.month == d.month &&
            start.day == d.day)) {
      _flow.setSlot(null);
    }
    _reloadSlots();
  }

  void _setWhen(_When w) {
    StaffHaptics.tap(context);
    _flow.setBookNow(w == _When.now);
    if (w == _When.slot) _reloadSlots();
  }

  /// By-quote offers cannot be booked: jump to the raise-quote flow with
  /// the customer and vehicle carried over.
  void _raiseQuoteInstead(OutletService s) {
    final flow = _flow;
    StaffHaptics.tap(context);
    context.push(
      Routes.quoteNew,
      extra: RaiseQuoteArgs(
        customer: flow.customer,
        vehicle: flow.vehicle,
        service: s,
      ),
    );
  }

  void _select(OutletService s) {
    if (s.isByQuote) {
      _raiseQuoteInstead(s);
      return;
    }
    StaffHaptics.tap(context);
    _flow.setService(s);
    if (!_flow.bookNow) _reloadSlots();
  }

  bool _isOpen(DateTime d) => _flow.outlet?.hoursFor(d.weekday) != null;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final total = flow.estimatedTotalCents;
        final size = flow.vehicleSize;
        final catalogue = _catalogue;
        final addons = flow.service == null || catalogue == null
            ? const <OutletService>[]
            : catalogue.addonsFor(flow.service!.groupName);
        return Column(
          children: [
            BookingStepHeader(
              title: 'Walk-in booking',
              step: 3,
              subtitle: 'Service & time',
              onBack: widget.onBack,
            ),
            Expanded(
              child: _error != null
                  ? ErrorState(error: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      children: [
                        OutletCard(
                          outlet: flow.outlet,
                          onTap: (_myOutlets?.length ?? 0) > 1
                              ? _pickOutlet
                              : null,
                        ),
                        const SizedBox(height: 20),
                        SectionHeader(
                          title: 'Services',
                          trailing: flow.vehicle == null
                              ? null
                              : Text(
                                  '${flow.vehicle!.registrationNo} · ${size.label}',
                                  style: SparklingTypography.mono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Prices resolved for a ${size.label.toLowerCase()} vehicle. "From" prices are minimums; the server prices the booking.',
                            style: SparklingTypography.bodyMedium.copyWith(
                              fontSize: 13.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (catalogue == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: LoadingState(),
                          )
                        else if (catalogue.bookableGroups.isEmpty)
                          const EmptyState(
                            icon: Symbols.local_car_wash_rounded,
                            title: 'No services at this outlet',
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
                              if (s.isByQuote)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 4,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      key: ValueKey('raise-quote-${s.code}'),
                                      onPressed: () => _raiseQuoteInstead(s),
                                      icon: const Icon(
                                        Symbols.request_quote_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Raise quote instead'),
                                    ),
                                  ),
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
                                  'Added to ${flow.service!.name}.',
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
                                    StaffHaptics.tap(context);
                                    flow.toggleAddon(a, v);
                                  },
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                            const SizedBox(height: 8),
                          ],
                        const SizedBox(height: 12),
                        const SectionHeader(title: 'When'),
                        SegmentedPills<_When>(
                          selected: flow.bookNow ? _When.now : _When.slot,
                          onChanged: _setWhen,
                          segments: const [
                            PillSegment(value: _When.now, label: 'Now (walk-in)'),
                            PillSegment(value: _When.slot, label: 'Pick a slot'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!flow.bookNow) ...[
                          if (flow.service == null)
                            Text(
                              'Choose a service to see available slots.',
                              style: SparklingTypography.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          else ...[
                            Text(
                              monthYear(_day),
                              style: SparklingTypography.headlineSmall.copyWith(
                                fontSize: 20,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _DateStrip(
                              daysAhead: widget.daysAhead,
                              selected: _day,
                              isOpen: _isOpen,
                              onSelect: _selectDay,
                            ),
                            const SizedBox(height: 20),
                            Text.rich(
                              TextSpan(
                                text: 'Available slots',
                                style: SparklingTypography.headlineSmall
                                    .copyWith(fontSize: 20, color: cs.onSurface),
                                children: [
                                  TextSpan(
                                    text: ' · revalidated on submit',
                                    style: SparklingTypography.bodyMedium
                                        .copyWith(
                                          fontSize: 15,
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_slots == null)
                              const LoadingState()
                            else
                              FutureBuilder<List<AvailabilitySlot>>(
                                future: _slots,
                                builder: (context, snap) =>
                                    AsyncView<List<AvailabilitySlot>>(
                                      snapshot: snap,
                                      onRetry: _reloadSlots,
                                      builder: (context, slots) {
                                        if (slots.isEmpty) {
                                          return const EmptyState(
                                            icon: Symbols.event_busy_rounded,
                                            title: 'Closed on this day',
                                            text: 'Choose another date.',
                                          );
                                        }
                                        return _SlotGrid(
                                          slots: slots,
                                          selected: flow.slotStart,
                                          onSelect: (s) {
                                            StaffHaptics.tap(context);
                                            flow.setSlot(s.slotStart);
                                          },
                                        );
                                      },
                                    ),
                              ),
                          ],
                          const SizedBox(height: 20),
                        ],
                        if (flow.service != null &&
                            (flow.bookNow || flow.slotStart != null))
                          _SummaryBanner(flow: flow, total: total),
                      ],
                    ),
            ),
            BottomActionBar(
              leadingLabel: flow.service == null
                  ? 'Total'
                  : [
                      if (flow.isIncluded)
                        'Included in plan'
                      else if (flow.membershipLabel != null)
                        flow.membershipLabel!,
                      if (flow.isExclVat) 'Incl. VAT',
                      if (flow.addons.isNotEmpty)
                        '${flow.addons.length} add-on${flow.addons.length == 1 ? '' : 's'}',
                      if (!flow.isExclVat &&
                          flow.membershipLabel == null &&
                          flow.addons.isEmpty)
                        'Total',
                    ].join(' · '),
              leadingValue: flow.service == null ? '—' : compactZar(total),
              child: PillButton(
                label: 'Review & confirm',
                trailingIcon: Symbols.arrow_forward_rounded,
                expand: true,
                minHeight: 56,
                onPressed: flow.canPay ? widget.onNext : null,
              ),
            ),
          ],
        );
      },
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
        'Prices excl. VAT · 15% added to the total',
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

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.daysAhead,
    required this.selected,
    required this.isOpen,
    required this.onSelect,
  });

  final int daysAhead;
  final DateTime selected;
  final bool Function(DateTime) isOpen;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(
      daysAhead,
      (i) => DateTime(today.year, today.month, today.day + i),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 5-up on a phone; chips stay tappable (≥ 48px wide).
        final w = ((constraints.maxWidth - 4 * 10) / 5).clamp(56.0, 80.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final d in days) ...[
                DateChip(
                  weekday: SparklingDates.weekday(d),
                  day: '${d.day}',
                  width: w,
                  selected: d == selected,
                  enabled: isOpen(d),
                  onTap: () => onSelect(d),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  final List<AvailabilitySlot> slots;
  final DateTime? selected;
  final ValueChanged<AvailabilitySlot> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final w = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in slots)
              SizedBox(
                width: w,
                child: SlotChip(
                  label: SparklingDates.hhmm(s.slotStart),
                  height: 48,
                  state: !s.available
                      ? SlotState.booked
                      : (selected != null &&
                            selected!.isAtSameMomentAs(s.slotStart))
                      ? SlotState.selected
                      : SlotState.available,
                  onTap: () => onSelect(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.flow, required this.total});
  final WalkInFlowController flow;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fg = cs.onSecondaryContainer;
    final s = flow.service!;
    final when = flow.bookNow ? 'Now' : SparklingDates.long(flow.slotStart!);
    final addons = flow.addons.isEmpty
        ? ''
        : ' + ${flow.addons.map((a) => a.name).join(', ')}';
    final vat = flow.estimatedVatCents;
    final benefit = flow.membershipLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            flow.bookNow
                ? Symbols.bolt_rounded
                : Symbols.event_available_rounded,
            color: cs.primary,
            fill: 1,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: SparklingTypography.bodyLarge.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  color: fg,
                ),
                children: [
                  TextSpan(
                    text: when,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        ' at ${shortOutletName(flow.outlet?.name)} · ${s.name}$addons for ${flow.vehicle?.registrationNo ?? 'vehicle'} (${flow.vehicleSize.label.toLowerCase()}), ±${s.durationMinutes} min.\n',
                  ),
                  TextSpan(
                    text:
                        '${[
                          'Total ${Money.formatZar(total)}',
                          if (benefit != null)
                            flow.isIncluded
                                ? '— $benefit'
                                : 'after $benefit',
                          if (vat > 0) 'incl. ${Money.formatZar(vat)} VAT',
                        ].join(' ')}.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
