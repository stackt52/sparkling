import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'duplicate_vehicle.dart';

/// Manual add / edit vehicle form (CUS-014). Scanned fields are prefilled
/// when arriving from the scanner with "Enter manually".
class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({
    super.key,
    this.vehicleId,
    this.existing,
    this.prefill,
  });

  final String? vehicleId;
  final Vehicle? existing;
  final DiscScanResult? prefill;

  bool get isEdit => vehicleId != null;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _reg;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _colour;
  late final TextEditingController _year;
  late final TextEditingController _vin;
  DateTime? _expiry;
  bool _busy = false;
  Vehicle? _loaded;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    final p = widget.prefill;
    _reg = TextEditingController(
      text: v?.registrationNo ?? p?.registrationNoFormatted ?? '',
    );
    _make = TextEditingController(text: v?.make ?? p?.make ?? '');
    _model = TextEditingController(text: v?.model ?? p?.model ?? '');
    _colour = TextEditingController(text: v?.colour ?? p?.colour ?? '');
    _year = TextEditingController(text: v?.year?.toString() ?? '');
    _vin = TextEditingController(text: v?.vin ?? p?.vin ?? '');
    _expiry = v?.discExpiry ?? p?.discExpiry;
    _loaded = v;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isEdit && _loaded == null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final list = await context.repos.customer.vehicles();
      final v = list.where((x) => x.id == widget.vehicleId).firstOrNull;
      if (v == null || !mounted) return;
      setState(() {
        _loaded = v;
        _reg.text = v.registrationNo;
        _make.text = v.make ?? '';
        _model.text = v.model ?? '';
        _colour.text = v.colour ?? '';
        _year.text = v.year?.toString() ?? '';
        _vin.text = v.vin ?? '';
        _expiry = v.discExpiry;
      });
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    }
  }

  @override
  void dispose() {
    for (final c in [_reg, _make, _model, _colour, _year, _vin]) {
      c.dispose();
    }
    super.dispose();
  }

  VehicleInput _input({bool force = false}) => VehicleInput(
    registrationNo: Pdf417DiscParser.formatRegistration(_reg.text.trim()),
    vin: _vin.text.trim().isEmpty ? null : _vin.text.trim().toUpperCase(),
    make: _make.text.trim().isEmpty ? null : _make.text.trim(),
    model: _model.text.trim().isEmpty ? null : _model.text.trim(),
    colour: _colour.text.trim().isEmpty ? null : _colour.text.trim(),
    year: int.tryParse(_year.text.trim()),
    discExpiry: _expiry,
    source: widget.prefill != null ? VehicleSource.scan : VehicleSource.manual,
    discHash: widget.prefill?.rawHash,
    force: force,
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repos = context.repos;
    try {
      if (widget.isEdit) {
        await repos.customer.updateVehicle(widget.vehicleId!, _input());
        if (!mounted) return;
        showSnack(context, 'Vehicle updated.');
        context.pop();
        return;
      }
      final saved = await saveVehicleHandlingDuplicates(
        context,
        repos,
        _input(),
      );
      if (saved != null && mounted) {
        showSnack(context, '${saved.shortName} added to your garage.');
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(Routes.vehicles);
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      helpText: 'Licence disc expiry',
    );
    if (d != null) setState(() => _expiry = d);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final fromScan = widget.prefill != null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: widget.isEdit ? 'Edit vehicle' : 'Add vehicle',
              subtitle: fromScan
                  ? 'Details from your licence disc'
                  : widget.isEdit
                  ? _loaded?.registrationNo
                  : 'Manual entry',
            ),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (!widget.isEdit && !fromScan)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InfoBanner(
                          tone: InfoTone.azure,
                          icon: Symbols.qr_code_scanner_rounded,
                          text: 'Scanning the licence disc fills this in and marks the vehicle as verified.',
                          actionLabel: 'Scan',
                          onAction: () => context.pushReplacement(Routes.scan),
                        ),
                      ),
                    TextFormField(
                      controller: _reg,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9 \-]'),
                        ),
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
                            decoration: const InputDecoration(
                              labelText: 'Make',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _model,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Model',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _colour,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Colour',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _year,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Year',
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              final y = int.tryParse(v);
                              final max = DateTime.now().year + 1;
                              return (y == null || y < 1950 || y > max)
                                  ? 'Year 1950–$max'
                                  : null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _vin,
                      readOnly: fromScan || (_loaded?.discVerified ?? false),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [LengthLimitingTextInputFormatter(17)],
                      style: SparklingTypography.mono(
                        fontSize: 15,
                        letterSpacing: 1,
                        color: cs.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'VIN (optional)',
                        suffixIcon: fromScan || (_loaded?.discVerified ?? false)
                            ? const Icon(Symbols.lock_rounded, fill: 1)
                            : null,
                        helperText: fromScan
                            ? 'From the disc — not editable'
                            : null,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        return RegExp(r'^[A-HJ-NPR-Za-hj-npr-z0-9]{17}$')
                                .hasMatch(v.trim())
                            ? null
                            : 'A VIN has 17 characters (no I, O, Q)';
                      },
                    ),
                    const SizedBox(height: 12),
                    KeyValueTile(
                      label: 'Disc expiry',
                      value: _expiry == null
                          ? 'Not set'
                          : '${SparklingDates.dayMonth(_expiry!)} ${_expiry!.year}',
                      warning:
                          _expiry != null &&
                          _expiry!.difference(DateTime.now()).inDays < 90,
                      helper:
                          _expiry != null &&
                              _expiry!.difference(DateTime.now()).inDays < 90
                          ? 'Renew soon'
                          : 'Tap to change',
                      trailing: Icon(
                        Symbols.edit_calendar_rounded,
                        color: cs.primary,
                      ),
                      onTap: _pickExpiry,
                    ),
                    const SizedBox(height: 24),
                    PillButton(
                      label: widget.isEdit ? 'Save changes' : 'Save vehicle',
                      expand: true,
                      loading: _busy,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
