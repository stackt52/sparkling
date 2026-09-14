import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../widgets/feedback.dart';
import 'walk_in_flow.dart';
import 'walk_in_widgets.dart';

/// Step 2 of 4 — pick one of the customer's vehicles, scan a disc, or add
/// one by hand (`POST /staff/customers/:id/vehicles`; duplicates → select
/// the existing record).
class VehicleStep extends StatefulWidget {
  const VehicleStep({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onBack,
    this.title = 'Walk-in booking',
    this.nextLabel = 'Choose service',
    this.totalSteps = 4,
  });

  final CustomerVehicleFlow flow;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final String title;
  final String nextLabel;
  final int totalSteps;

  @override
  State<VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<VehicleStep> {
  bool _busy = false;

  CustomerVehicleFlow get _flow => widget.flow;

  /// Creates [input] for the current customer; on a duplicate the existing
  /// vehicle is selected instead. Returns `true` when a vehicle got selected.
  Future<bool> _create(VehicleInput input) async {
    final flow = _flow;
    final customer = flow.customer;
    if (customer == null) return false;
    setState(() => _busy = true);
    final staff = context.repositories.staff;
    try {
      Vehicle created;
      try {
        created = await staff.createCustomerVehicle(customer.id, input);
      } on ApiException catch (e) {
        final existingId = e.existingVehicleId;
        if (!e.isConflict || existingId == null) rethrow;
        final existing = customer.vehicles
            .where((v) => v.id == existingId)
            .firstOrNull;
        if (existing != null) {
          if (!mounted) return false;
          StaffSnack.show(
            context,
            '${existing.registrationNo} is already on file — selected.',
          );
          flow.setVehicle(existing);
          return true;
        }
        // Not in the cached summary: refresh the customer and pick it.
        final fresh = await _refreshCustomer(customer);
        final found = fresh?.vehicles
            .where((v) => v.id == existingId)
            .firstOrNull;
        if (found == null) rethrow;
        if (!mounted) return false;
        flow.setVehicle(found);
        return true;
      }
      final summary = CustomerVehicleSummary.fromVehicle(created);
      flow.refreshCustomer(
        customer.copyWith(vehicles: [...customer.vehicles, summary]),
      );
      flow.setVehicle(summary);
      if (!mounted) return false;
      StaffHaptics.success(context);
      StaffSnack.show(
        context,
        '${created.registrationNo} added to ${customer.firstName}.',
      );
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      StaffSnack.error(context, e);
      return false;
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<CustomerSummary?> _refreshCustomer(CustomerSummary c) async {
    try {
      final key = c.phone ?? c.email ?? c.fullName;
      final list = await context.repositories.staff.searchCustomers(key);
      final fresh = list.where((x) => x.id == c.id).firstOrNull;
      if (fresh != null && mounted) _flow.refreshCustomer(fresh);
      return fresh;
    } catch (_) {
      return null;
    }
  }

  Future<void> _scan() async {
    final result = await context.push<DiscScanResult>(Routes.walkInScan);
    if (result == null || !mounted) return;
    _flow.setScannedVehicle(result);
    await _addScanned();
  }

  Future<void> _addScanned() async {
    final scanned = _flow.scannedVehicle;
    if (scanned == null) return;
    // The disc description (sedan / station wagon / …) picks the size class
    // that drives the small / large price.
    final ok = await _create(
      scanned.toVehicleInput().copyWith(
        sizeClass: VehicleSize.fromDiscDescription(scanned.description),
      ),
    );
    if (ok && mounted) _flow.setScannedVehicle(null);
  }

  Future<void> _addManually() async {
    final input = await showModalBottomSheet<VehicleInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: const _VehicleFormSheet(),
      ),
    );
    if (input == null || !mounted) return;
    await _create(input);
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final customer = flow.customer;
        final scanned = flow.scannedVehicle;
        final vehicles = customer?.vehicles ?? const <CustomerVehicleSummary>[];
        final scannedOnFile =
            scanned != null &&
            vehicles.any(
              (v) =>
                  v.normalisedRegistration ==
                  Vehicle.normaliseRegistration(scanned.registrationNo),
            );
        return Column(
          children: [
            BookingStepHeader(
              title: widget.title,
              step: 2,
              total: widget.totalSteps,
              subtitle: 'Vehicle',
              onBack: widget.onBack,
            ),
            Expanded(
              child: customer == null
                  ? Center(
                      child: PillButton(
                        label: 'Choose a customer first',
                        variant: PillButtonVariant.tonal,
                        onPressed: widget.onBack,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      children: [
                        CustomerCard(
                          customer: customer,
                          compact: true,
                          onChange: widget.onBack,
                        ),
                        const SizedBox(height: 16),
                        if (scanned != null && !scannedOnFile) ...[
                          Builder(
                            builder: (context) {
                              final makeModel = [
                                scanned.make,
                                scanned.model,
                              ].whereType<String>().join(' ').trim();
                              return InfoBanner(
                                tone: InfoTone.azure,
                                icon: Symbols.qr_code_scanner_rounded,
                                title:
                                    'Scanned ${scanned.registrationNoFormatted}',
                                text: makeModel.isEmpty
                                    ? 'Not on file for ${customer.firstName} yet.'
                                    : '$makeModel — not on file for ${customer.firstName} yet.',
                                actionLabel: _busy ? null : 'Add & select',
                                onAction: _addScanned,
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        SectionHeader(
                          title: vehicles.isEmpty
                              ? 'No vehicles on file'
                              : 'Which vehicle?',
                        ),
                        if (vehicles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Scan the licence disc (marks it verified) or '
                              'type the registration.',
                              style: SparklingTypography.bodyMedium.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        for (final v in vehicles) ...[
                          _VehicleCard(
                            vehicle: v,
                            selected: flow.vehicle?.id == v.id,
                            onSelect: () {
                              StaffHaptics.tap(context);
                              flow.setVehicle(v);
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Scan disc',
                                icon: Symbols.qr_code_scanner_rounded,
                                variant: PillButtonVariant.outlined,
                                expand: true,
                                minHeight: 52,
                                onPressed: _busy ? null : _scan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PillButton(
                                label: 'Add manually',
                                icon: Symbols.keyboard_rounded,
                                variant: PillButtonVariant.tonal,
                                expand: true,
                                minHeight: 52,
                                loading: _busy,
                                onPressed: _busy ? null : _addManually,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            BottomActionBar(
              leadingLabel: 'Vehicle',
              leadingValue: flow.vehicle?.registrationNo ?? '—',
              child: PillButton(
                label: widget.nextLabel,
                trailingIcon: Symbols.arrow_forward_rounded,
                expand: true,
                minHeight: 56,
                onPressed: flow.vehicle == null ? null : widget.onNext,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.selected,
    required this.onSelect,
  });

  final CustomerVehicleSummary vehicle;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final v = vehicle;
    return RadioCard(
      selected: selected,
      onChanged: (_) => onSelect(),
      radioPosition: RadioCardRadioPosition.trailing,
      leading: Icon(
        Symbols.directions_car_rounded,
        color: selected ? cs.onPrimaryContainer : cs.primary,
        fill: 1,
        size: 26,
      ),
      title: Text(
        v.registrationNo,
        style: SparklingTypography.mono(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
      subtitle: Text(
        [
          v.displayName.isEmpty ? 'Make / model unknown' : v.displayName,
          if (v.colour != null) v.colour!,
          '${v.sizeClass.label} vehicle',
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(
            label: v.discVerified ? 'Disc verified' : 'Manual',
            tone: v.discVerified
                ? StatusChipTone.success
                : StatusChipTone.neutral,
            dense: true,
          ),
          const SizedBox(height: 4),
          StatusChip(label: v.sizeClass.label, dense: true),
        ],
      ),
    );
  }
}

/// Manual vehicle form (registration, make, model, colour) → [VehicleInput].
class _VehicleFormSheet extends StatefulWidget {
  const _VehicleFormSheet();

  @override
  State<_VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends State<_VehicleFormSheet> {
  final _form = GlobalKey<FormState>();
  final _reg = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  VehicleSize _size = VehicleSize.small;

  @override
  void dispose() {
    for (final c in [_reg, _make, _model, _colour]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      VehicleInput(
        registrationNo: Pdf417DiscParser.formatRegistration(_reg.text.trim()),
        make: _make.text.trim().isEmpty ? null : _make.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        colour: _colour.text.trim().isEmpty ? null : _colour.text.trim(),
        sizeClass: _size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Add vehicle'),
              TextFormField(
                controller: _reg,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                style: SparklingTypography.mono(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: cs.onSurface,
                ),
                decoration: const InputDecoration(
                  labelText: 'Registration',
                  hintText: 'KL 45 MN GP',
                ),
                validator: (v) =>
                    Vehicle.normaliseRegistration(v ?? '').length < 2
                    ? 'Enter the registration number'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _make,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Make'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Model'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _colour,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Colour'),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 14),
              VehicleSizeSelector(
                value: _size,
                onChanged: (s) => setState(() => _size = s),
              ),
              const SizedBox(height: 18),
              PillButton(
                label: 'Save vehicle',
                icon: Symbols.check_rounded,
                expand: true,
                minHeight: 52,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
