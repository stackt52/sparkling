import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../../widgets/segmented_pills.dart';

/// Arguments for [ScanReviewScreen].
class ScanReviewArgs {
  const ScanReviewArgs({required this.result, this.manual = false});
  final DiscScanResult result;
  final bool manual;
}

/// Scan review (STF-011/012): decoded fields as key-value tiles (VIN locked),
/// disc-expiry warning, then match to today's booking and check in via
/// `staff.checkinBooking` (bay + priority).
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, this.result, this.args});

  final DiscScanResult? result;
  final ScanReviewArgs? args;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  Future<List<Booking>>? _matches;
  final _bay = TextEditingController();
  int _priority = 2;
  bool _busy = false;

  ScanReviewArgs? get _args =>
      widget.args ??
      (widget.result == null ? null : ScanReviewArgs(result: widget.result!));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _matches ??= _findBookings();
  }

  @override
  void dispose() {
    _bay.dispose();
    super.dispose();
  }

  Future<List<Booking>> _findBookings() async {
    final args = _args;
    if (args == null) return const [];
    final reg = Vehicle.normaliseRegistration(args.result.registrationNo);
    final list = await context.repositories.staff.outletBookings(
      outletId: context.session.outletId,
    );
    final today = DateTime.now();
    return list.where((b) {
      final plate = b.vehicle?.registrationNo;
      if (plate == null) return false;
      if (Vehicle.normaliseRegistration(plate) != reg) return false;
      if (!b.status.isActive) return false;
      final d = b.slotStart.toLocal();
      return d.year == today.year && d.month == today.month && d.day == today.day ||
          b.status == BookingStatus.inService;
    }).toList()..sort((a, b) => a.slotStart.compareTo(b.slotStart));
  }

  Future<void> _checkIn(Booking booking) async {
    setState(() => _busy = true);
    try {
      final result = await runMutation(
        context,
        () => context.repositories.staff.checkinBooking(
          booking.id,
          bay: _bay.text.trim().isEmpty ? null : _bay.text.trim(),
          priority: _priority,
        ),
        onConflict: () => setState(() => _matches = _findBookings()),
      );
      if (result != null && mounted) {
        StaffHaptics.success(context);
        StaffSnack.show(
          context,
          '${booking.ref} checked in${result.workOrder == null ? '' : ' · ${result.workOrder!.ref}'}',
        );
        context.go(Routes.tasks);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final args = _args;
    if (args == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Symbols.qr_code_scanner_rounded,
          title: 'Nothing to review',
          text: 'Scan a disc first.',
        ),
      );
    }
    final r = args.result;
    final expiry = r.discExpiry;
    final expiryWarning =
        expiry != null &&
        (r.isExpired || expiry.difference(DateTime.now()).inDays <= 60);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                IconTileButton(
                  icon: Symbols.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    args.manual ? 'Manual entry' : 'Review scan',
                    style: SparklingTypography.headlineMedium.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InfoBanner(
              tone: args.manual ? InfoTone.info : InfoTone.success,
              icon: args.manual ? Symbols.keyboard_rounded : null,
              title: args.manual
                  ? 'Entered by hand'
                  : 'Disc decoded on your device',
              text: args.manual
                  ? 'No disc data — the vehicle is matched by plate only.'
                  : 'Check the details before you check the vehicle in — nothing is committed silently.',
            ),
            const SizedBox(height: 14),
            KeyValueTile(
              label: 'Registration',
              value: r.registrationNoFormatted,
              mono: true,
            ),
            const SizedBox(height: 10),
            if (r.vin != null) ...[
              KeyValueTile(
                label: 'VIN',
                value: '•••• ${r.vin!.substring(r.vin!.length - 4)}',
                mono: true,
                locked: true,
                helper: 'From the disc — not editable',
              ),
              const SizedBox(height: 10),
            ],
            if (r.make != null || r.model != null) ...[
              KeyValueTile(
                label: 'Make & model',
                value: [r.make, r.model].whereType<String>().join(' '),
              ),
              const SizedBox(height: 10),
            ],
            if (r.colour != null) ...[
              KeyValueTile(label: 'Colour', value: r.colour!),
              const SizedBox(height: 10),
            ],
            if (r.licenceNo != null) ...[
              KeyValueTile(
                label: 'Licence no.',
                value: r.licenceNo!,
                mono: true,
              ),
              const SizedBox(height: 10),
            ],
            if (expiry != null) ...[
              KeyValueTile(
                label: 'Disc expiry',
                value: SparklingDates.isoDay(expiry),
                warning: expiryWarning,
                helper: r.isExpired
                    ? 'Expired — let the customer know'
                    : expiryWarning
                    ? 'Expires within 60 days'
                    : null,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            SectionHeader(title: "Today's booking"),
            FutureBuilder<List<Booking>>(
              future: _matches,
              builder: (context, snap) => AsyncView<List<Booking>>(
                snapshot: snap,
                onRetry: () => setState(() => _matches = _findBookings()),
                loading: const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingState(label: 'Matching plate…'),
                ),
                builder: (context, bookings) {
                  if (bookings.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoBanner(
                          tone: InfoTone.warning,
                          bordered: true,
                          title: 'No booking for ${r.registrationNoFormatted}',
                          text:
                              'No active booking at this outlet today. Walk-in '
                              'check-in is not available in the staff API yet — '
                              'ask the customer to book in the app or create the '
                              'booking from the admin dashboard.',
                        ),
                        const SizedBox(height: 14),
                        PillButton(
                          label: 'Rescan',
                          icon: Symbols.refresh_rounded,
                          variant: PillButtonVariant.outlined,
                          expand: true,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    );
                  }
                  final booking = bookings.first;
                  final inService = booking.status == BookingStatus.inService;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTileCard(
                        leading: Icon(
                          Symbols.event_available_rounded,
                          color: cs.primary,
                          fill: 1,
                        ),
                        title: Text(booking.title),
                        subtitle: Text(
                          '${booking.ref} · ${SparklingDates.relativeSlot(booking.slotStart)}'
                          '${booking.workOrder == null ? '' : ' · ${booking.workOrder!.ref}'}',
                        ),
                        trailing: StatusChip(
                          label: booking.status.label,
                          tone: inService
                              ? StatusChipTone.primary
                              : StatusChipTone.success,
                          dot: true,
                        ),
                      ),
                      if (inService)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: InfoBanner(
                            tone: InfoTone.info,
                            text:
                                'Already checked in — find it under Tasks (${booking.workOrder?.ref ?? 'in service'}).',
                          ),
                        )
                      else ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _bay,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Bay (e.g. Bay 2)',
                            prefixIcon: Icon(Symbols.local_car_wash_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedPills<int>(
                          selected: _priority,
                          onChanged: (p) => setState(() => _priority = p),
                          segments: const [
                            PillSegment(value: 1, label: 'P1 · urgent'),
                            PillSegment(value: 2, label: 'P2'),
                            PillSegment(value: 3, label: 'P3'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PillButton(
                          label: 'Check in ${booking.vehicle?.shortName ?? ''}'
                              .trim(),
                          icon: Symbols.check_rounded,
                          expand: true,
                          minHeight: 56,
                          loading: _busy,
                          onPressed: () => _checkIn(booking),
                        ),
                      ],
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
