import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'duplicate_vehicle.dart';

/// Review decoded disc fields before saving (1e, CUS-013/015).
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.result});

  final DiscScanResult result;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late String _registration = widget.result.registrationNoFormatted;
  Future<Vehicle?>? _duplicate;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _duplicate ??= _findDuplicate();
  }

  Future<Vehicle?> _findDuplicate() async {
    try {
      final list = await context.repos.customer.vehicles();
      final norm = Vehicle.normaliseRegistration(_registration);
      final vin = widget.result.vin;
      return list
          .where(
            (v) =>
                v.normalisedRegistration == norm ||
                (vin != null && v.vin == vin),
          )
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  String get _maskedVin {
    final vin = widget.result.vin;
    if (vin == null) return '—';
    if (vin.length <= 12) return vin;
    return '${vin.substring(0, 8)}•••••${vin.substring(vin.length - 4)}';
  }

  Future<void> _editRegistration() async {
    final controller = TextEditingController(text: _registration);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registration'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: SparklingTypography.mono(fontSize: 18, letterSpacing: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || Vehicle.normaliseRegistration(value).length < 2) {
      return;
    }
    setState(() {
      _registration = Pdf417DiscParser.formatRegistration(value.trim());
      _duplicate = _findDuplicate();
    });
  }

  Future<void> _save(Vehicle? duplicate) async {
    setState(() => _busy = true);
    final repos = context.repos;
    final input = widget.result.toVehicleInput().copyWith(
      registrationNo: _registration,
    );
    try {
      final Vehicle? saved;
      if (duplicate != null) {
        saved = await repos.customer.updateVehicle(duplicate.id, input);
      } else {
        saved = await saveVehicleHandlingDuplicates(context, repos, input);
      }
      if (saved == null || !mounted) return;
      AppHaptics.success(context);
      showSnack(
        context,
        duplicate != null
            ? '${saved.shortName} updated from your disc.'
            : '${saved.shortName} added — disc verified.',
      );
      context.go(Routes.vehicles);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final r = widget.result;
    final expiry = r.discExpiry;
    final days = expiry?.difference(DateTime.now()).inDays;
    final expiryWarn = days != null && days < 90;
    final expiryHelper = days == null
        ? null
        : days < 0
        ? 'expired'
        : days < 90
        ? 'soon'
        : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Confirm vehicle',
              subtitle: 'Scanned from licence disc',
            ),
            Expanded(
              child: FutureBuilder<Vehicle?>(
                future: _duplicate,
                builder: (context, snap) {
                  final dup = snap.data;
                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          children: [
                            const InfoBanner(
                              tone: InfoTone.success,
                              text: 'Barcode decoded and validated. Review before saving — nothing is committed silently.',
                            ),
                            const SizedBox(height: 14),
                            KeyValueTile(
                              label: 'Registration',
                              value: _registration,
                              mono: true,
                              onTap: _editRegistration,
                              trailing: Icon(
                                Symbols.edit_rounded,
                                color: cs.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(height: 10),
                            KeyValueTile(
                              label: 'VIN',
                              value: _maskedVin,
                              mono: true,
                              locked: true,
                            ),
                            const SizedBox(height: 10),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: KeyValueTile(
                                      label: 'Make',
                                      value: r.make ?? '—',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: KeyValueTile(
                                      label: 'Model',
                                      value: r.model ?? '—',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: KeyValueTile(
                                      label: 'Colour',
                                      value: r.colour ?? '—',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: KeyValueTile(
                                      label: 'Disc expiry',
                                      value: expiry == null
                                          ? '—'
                                          : '${SparklingDates.dayMonth(expiry)} ${expiry.year}${expiryHelper == null ? '' : ' · $expiryHelper'}',
                                      warning: expiryWarn,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (r.licenceNo != null) ...[
                              const SizedBox(height: 10),
                              KeyValueTile(
                                label: 'Licence no',
                                value: r.licenceNo!,
                                mono: true,
                                locked: true,
                              ),
                            ],
                            if (dup != null) ...[
                              const SizedBox(height: 14),
                              InfoBanner(
                                tone: InfoTone.info,
                                text:
                                    'Looks like ${dup.shortName} · ${dup.registrationNo} already exists. Saving will update that record instead of duplicating it.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: PillButton(
                                label: 'Rescan',
                                variant: PillButtonVariant.outlined,
                                expand: true,
                                minHeight: 54,
                                onPressed: _busy ? null : () => context.pop(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: PillButton(
                                label: 'Save vehicle',
                                expand: true,
                                minHeight: 54,
                                loading: _busy,
                                onPressed: () => _save(dup),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
