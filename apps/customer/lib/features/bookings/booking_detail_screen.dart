import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// Booking detail: summary, payment, points, track / reschedule / cancel.
class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, this.initial});

  final String bookingId;
  final Booking? initial;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Stream<Booking>? _stream;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= context.repos.customer.watchBooking(widget.bookingId);
  }

  Future<void> _cancel(Booking b) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _CancelSheet(),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.repos.customer.cancelBooking(b.id, reason: reason);
      if (mounted) showSnack(context, 'Booking ${b.ref} cancelled.');
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule(Booking b) async {
    final repos = context.repos;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: b.slotStart.isAfter(now) ? b.slotStart : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted || b.outletId == null || b.serviceId == null) {
      return;
    }
    final slots = await repos.catalogue.availability(
      outletId: b.outletId!,
      serviceId: b.serviceId!,
      date: day,
    );
    if (!mounted) return;
    final chosen = await showModalBottomSheet<AvailabilitySlot>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: SparklingDates.dayMonth(day)),
              if (slots.isEmpty)
                const EmptyState(
                  icon: Symbols.event_busy_rounded,
                  title: 'Closed on this day',
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in slots)
                    SizedBox(
                      width: 100,
                      child: SlotChip(
                        label: SparklingDates.hhmm(s.slotStart),
                        state: s.available
                            ? SlotState.available
                            : SlotState.booked,
                        onTap: () => Navigator.of(context).pop(s),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await repos.customer.rescheduleBooking(b.id, chosen.slotStart);
      if (mounted) {
        showSnack(
          context,
          'Moved to ${SparklingDates.relativeSlot(chosen.slotStart)}.',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Booking>(
          stream: _stream,
          initialData: widget.initial,
          builder: (context, snap) {
            if (snap.hasError && !snap.hasData) {
              return Column(
                children: [
                  const ScreenHeader(title: 'Booking'),
                  ErrorView(
                    error: snap.error,
                    onRetry: () => setState(
                      () => _stream = context.repos.customer.watchBooking(
                        widget.bookingId,
                      ),
                    ),
                  ),
                ],
              );
            }
            final b = snap.data;
            if (b == null) {
              return const Column(
                children: [
                  ScreenHeader(title: 'Booking'),
                  LoadingView(),
                ],
              );
            }
            final showTrack =
                b.isInService || b.status == BookingStatus.completed;
            return Column(
              children: [
                ScreenHeader(
                  titleWidget: Text(
                    b.ref,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SparklingTypography.mono(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  title: b.ref,
                  subtitle: b.title,
                  trailing: StatusChip(
                    label: b.status.label,
                    tone: bookingTone(b.status),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      if (b.isInService && b.workOrder != null)
                        HeroCard.navy(
                          onTap: () => context.push(Routes.track(b.id)),
                          child: Row(
                            children: [
                              ProgressRing(
                                value: b.workOrder!.progress.clamp(0, 1),
                                label:
                                    '${(b.workOrder!.progress * 100).round()}%',
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.workOrder!.stageTitle ?? 'In service',
                                      style: SparklingTypography.titleLarge
                                          .copyWith(
                                            fontSize: 18,
                                            color: Colors.white,
                                          ),
                                    ),
                                    Text(
                                      'Stage ${b.workOrder!.stage} of ${b.workOrder!.stageCount} · tap to track',
                                      style: SparklingTypography.bodyMedium
                                          .copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (b.isInService) const SizedBox(height: 14),
                      KeyValueTile(
                        label: 'When',
                        value: SparklingDates.long(b.slotStart),
                        helper: b.service?.durationMinutes == null
                            ? null
                            : '±${b.service!.durationMinutes} min',
                      ),
                      const SizedBox(height: 8),
                      KeyValueTile(
                        label: 'Outlet',
                        value: b.outlet?.name ?? '—',
                      ),
                      const SizedBox(height: 8),
                      KeyValueTile(
                        label: 'Vehicle',
                        value: b.vehicle?.registrationNo ?? '—',
                        mono: true,
                        helper: b.vehicle?.displayName,
                      ),
                      const SizedBox(height: 8),
                      _PriceCard(booking: b),
                      const SizedBox(height: 8),
                      KeyValueTile(
                        label: 'Loyalty',
                        value: b.status == BookingStatus.completed
                            ? '+${b.pointsPending} pts earned'
                            : '+${b.pointsPending} pts pending completion',
                        helper: 'Points post when the service is verified',
                      ),
                      if (b.cancelReason != null) ...[
                        const SizedBox(height: 8),
                        KeyValueTile(
                          label: 'Cancel reason',
                          value: b.cancelReason!,
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (showTrack)
                        PillButton(
                          label: b.isInService
                              ? 'Track service'
                              : 'View timeline',
                          icon: Symbols.timeline_rounded,
                          expand: true,
                          onPressed: () => context.push(Routes.track(b.id)),
                        ),
                      if (b.canCancel) ...[
                        const SizedBox(height: 10),
                        PillButton(
                          label: 'Reschedule',
                          icon: Symbols.edit_calendar_rounded,
                          variant: PillButtonVariant.tonal,
                          expand: true,
                          loading: _busy,
                          onPressed: () => _reschedule(b),
                        ),
                        const SizedBox(height: 10),
                        PillButton(
                          label: 'Cancel booking',
                          variant: PillButtonVariant.outlinedError,
                          expand: true,
                          onPressed: _busy ? null : () => _cancel(b),
                        ),
                      ],
                    ],
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

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final b = booking;
    final style = SparklingTypography.bodyLarge.copyWith(
      fontSize: 15,
      color: cs.onSurfaceVariant,
    );
    final paid = b.payment?.status.isVerified ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.tile),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(b.service?.name ?? 'Service', style: style)),
              Text(Money.formatZar(b.priceCents), style: style),
            ],
          ),
          if (b.discountCents > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.discountLabel ?? 'Discount',
                    style: style.copyWith(color: x.success),
                  ),
                ),
                Text(
                  '${Money.minus} ${Money.formatZar(b.discountCents)}',
                  style: style.copyWith(color: x.success),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const DashedDivider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  paid ? 'Paid' : 'Total due',
                  style: SparklingTypography.titleMedium.copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                Money.formatZar(b.totalCents),
                style: SparklingTypography.headlineSmall.copyWith(
                  color: cs.primary,
                ),
              ),
            ],
          ),
          if (b.payment != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: StatusChip(
                label: paid
                    ? 'Payment verified${b.payment!.receiptNo == null ? '' : ' · ${b.payment!.receiptNo}'}'
                    : 'Payment ${b.payment!.status.label.toLowerCase()}',
                tone: paid ? StatusChipTone.success : StatusChipTone.warning,
                dense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  static const _reasons = [
    'Change of plans',
    'Found another time',
    'Vehicle not available',
    'Other',
  ];
  String _reason = _reasons.first;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Cancel booking?'),
            const InfoBanner(
              tone: InfoTone.warning,
              text: 'Free until 2 h before your slot. Paid amounts are refunded to the original method.',
            ),
            const SizedBox(height: 12),
            for (final r in _reasons) ...[
              RadioCard(
                selected: _reason == r,
                onChanged: (_) => setState(() => _reason = r),
                title: Text(r),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Keep booking',
                    variant: PillButtonVariant.outlined,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: 'Cancel booking',
                    variant: PillButtonVariant.filled,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(_reason),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
