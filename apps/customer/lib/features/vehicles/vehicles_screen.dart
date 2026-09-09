import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// Vehicle list with add (scan / manual), edit and remove.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  Stream<List<Vehicle>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= context.repos.customer.watchVehicles();
  }

  Future<void> _remove(Vehicle v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text(
          '${v.shortName} · ${v.registrationNo} will be hidden from your garage. Past bookings are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.repos.customer.deleteVehicle(v.id);
      if (mounted) showSnack(context, '${v.shortName} removed.');
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    }
  }

  void _add() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Add a vehicle'),
              ListTileCard(
                onTap: () {
                  Navigator.of(sheet).pop();
                  context.push(Routes.scan);
                },
                leading: const TintedIconTile(
                  icon: Symbols.qr_code_scanner_rounded,
                  size: 48,
                ),
                title: const Text('Scan licence disc'),
                subtitle: const Text(
                  'PDF417 barcode · decoded on your phone, even offline',
                ),
                trailing: Icon(
                  Symbols.chevron_right_rounded,
                  color: sheet.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              ListTileCard(
                onTap: () {
                  Navigator.of(sheet).pop();
                  context.push(Routes.vehicleAdd);
                },
                leading: TintedIconTile(
                  icon: Symbols.keyboard_rounded,
                  size: 48,
                  background: sheet.colors.secondaryContainer,
                  foreground: sheet.colors.onSecondaryContainer,
                ),
                title: const Text('Enter manually'),
                subtitle: const Text('Registration, make and model'),
                trailing: Icon(
                  Symbols.chevron_right_rounded,
                  color: sheet.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Your vehicles',
              subtitle: 'Disc-verified cars skip the check-in queue',
              trailing: IconTileButton(
                icon: Symbols.add_rounded,
                tone: IconTileTone.primary,
                tooltip: 'Add vehicle',
                onPressed: _add,
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Vehicle>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorView(
                      error: snap.error,
                      onRetry: () => setState(
                        () => _stream = context.repos.customer.watchVehicles(),
                      ),
                    );
                  }
                  final list = snap.data;
                  if (list == null) return const LoadingView();
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Symbols.directions_car_rounded,
                      title: 'No vehicles yet',
                      message: 'Scan the licence disc on your windscreen or add the details by hand.',
                      actionLabel: 'Add vehicle',
                      onAction: _add,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final v = list[i];
                      final expiry = v.discExpiry;
                      return ListTileCard(
                        onTap: () =>
                            context.push(Routes.vehicleEdit(v.id), extra: v),
                        borderColor: v.discExpiringSoon
                            ? context.sparkling.gold
                            : null,
                        leading: TintedIconTile(
                          icon: Symbols.directions_car_rounded,
                          size: 48,
                        ),
                        title: Text(
                          v.displayName.isEmpty ? v.shortName : v.displayName,
                        ),
                        subtitle: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: v.registrationNo,
                                style: SparklingTypography.monoBody.copyWith(
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (expiry != null)
                                TextSpan(
                                  text:
                                      '  ·  disc ${v.discExpired ? 'expired' : 'expires'} ${SparklingDates.dayMonth(expiry)} ${expiry.year}',
                                ),
                            ],
                          ),
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(
                              label: v.discVerified
                                  ? 'Disc verified'
                                  : 'Manual entry',
                              tone: v.discVerified
                                  ? StatusChipTone.success
                                  : StatusChipTone.neutral,
                              dense: true,
                            ),
                            SizedBox(
                              height: 36,
                              child: TextButton(
                                onPressed: () => _remove(v),
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.error,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Remove'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
