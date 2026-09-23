import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import '../quote/raise_quote_controller.dart';
import 'walk_in_flow.dart';
import 'walk_in_widgets.dart';

/// Walk-in confirmed (1g): confetti blob, ref in mono, receipt number,
/// detail rows, "Open checklist" when checked in, "New walk-in" / "Done".
/// Queued offline → SyncChip + "Will sync when online".
class WalkInConfirmationScreen extends StatefulWidget {
  const WalkInConfirmationScreen({
    super.key,
    required this.bookingId,
    this.outcome,
  });

  final String bookingId;
  final WalkInOutcome? outcome;

  @override
  State<WalkInConfirmationScreen> createState() =>
      _WalkInConfirmationScreenState();
}

class _WalkInConfirmationScreenState extends State<WalkInConfirmationScreen> {
  Future<WalkInOutcome>? _outcome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outcome ??= widget.outcome != null
        ? Future.value(widget.outcome)
        : _load();
  }

  /// Deep link without `extra`: find the booking in the outlet list.
  Future<WalkInOutcome> _load() async {
    final list = await context.repositories.staff.outletBookings(
      outletId: context.session.outletId,
    );
    final b = list.where((b) => b.id == widget.bookingId).firstOrNull;
    if (b == null) {
      throw const ApiException(
        code: 'not_found',
        message: 'Booking not found at this outlet.',
        statusCode: 404,
      );
    }
    return WalkInOutcome(booking: b);
  }

  void _raiseQuote(WalkInOutcome o) {
    final v = o.booking.vehicle;
    context.push(
      Routes.quoteNew,
      extra: RaiseQuoteArgs(
        customer: o.customer,
        vehicle: v == null
            ? null
            : CustomerVehicleSummary(
                id: v.id,
                registrationNo: v.registrationNo,
                make: v.make,
                model: v.model,
              ),
      ),
    );
  }

  void _openChecklist(Booking b) {
    final wo = b.workOrder;
    if (wo == null) return;
    context.go(Routes.tasks);
    context.push(Routes.checklist(wo.id));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<WalkInOutcome>(
          future: _outcome,
          builder: (context, snap) => AsyncView<WalkInOutcome>(
            snapshot: snap,
            onRetry: () => setState(() => _outcome = _load()),
            builder: (context, o) {
              final b = o.booking;
              final pay = o.payment;
              final queued = o.queued;
              // Every confirmed walk-in has its work order at once; only a
              // stamped check-in means the car is in the bay.
              final checkedIn = b.workOrder?.isCheckedIn ?? false;
              final paid =
                  (pay?.status.isVerified ?? false) ||
                  (b.payment?.status.isVerified ?? false);
              final receipt = pay?.receiptNo ?? b.payment?.receiptNo;
              final amount = pay?.amountCents ?? b.totalCents;
              final title = queued
                  ? 'Walk-in queued'
                  : checkedIn
                  ? 'Checked in'
                  : 'Walk-in confirmed';
              final customerName =
                  o.customer?.fullName ??
                  b.vehicle?.displayName ??
                  'The customer';
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      children: [
                        Center(
                          child: ConfettiBlob(
                            size: 160,
                            icon: queued
                                ? Symbols.cloud_upload_rounded
                                : Symbols.check_rounded,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: SparklingTypography.headlineLarge.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          queued
                              ? '$customerName\'s ${b.vehicle?.shortName ?? 'vehicle'} is booked on this device.'
                              : checkedIn
                              ? '$customerName\'s ${b.vehicle?.shortName ?? 'vehicle'} is ${b.workOrder?.bay == null ? 'in the queue' : 'in ${b.workOrder!.bay}'}.'
                              : '${shortOutletName(b.outlet?.name)} is expecting $customerName\'s ${b.vehicle?.shortName ?? 'vehicle'}.',
                          textAlign: TextAlign.center,
                          style: SparklingTypography.bodyLarge.copyWith(
                            fontSize: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (queued)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: SyncChip(
                                state: SyncState.queued,
                                label: 'Will sync when online',
                              ),
                            ),
                          )
                        else
                          Text.rich(
                            TextSpan(
                              text: 'Reference ',
                              style: SparklingTypography.bodyLarge.copyWith(
                                fontSize: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              children: [
                                TextSpan(
                                  text: b.ref,
                                  style: SparklingTypography.mono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                                if (receipt != null) ...[
                                  const TextSpan(text: ' · Receipt '),
                                  TextSpan(
                                    text: receipt,
                                    style: SparklingTypography.mono(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(
                              SparklingShapes.card,
                            ),
                          ),
                          child: Column(
                            children: [
                              _DetailRow(
                                icon: serviceIcon(b.service?.icon),
                                text:
                                    '${b.service?.name ?? 'Service'} · ${b.vehicle?.registrationNo ?? ''}',
                              ),
                              for (final a in b.addons)
                                _DetailRow(
                                  icon: Symbols.add_circle_rounded,
                                  text:
                                      'Add-on · ${a.name} · ${Money.formatZar(a.priceCents)}',
                                ),
                              if (b.membership?.isIncluded ?? false)
                                _DetailRow(
                                  icon: Symbols.workspace_premium_rounded,
                                  iconColor: context.sparkling.success,
                                  text: b.discountLabel ?? 'Included in plan',
                                )
                              else if (b.discountCents > 0 &&
                                  b.discountLabel != null)
                                _DetailRow(
                                  icon: Symbols.sell_rounded,
                                  iconColor: context.sparkling.success,
                                  text:
                                      '${b.discountLabel} · ${Money.minus} ${Money.formatZar(b.discountCents)}',
                                ),
                              if (b.vatCents > 0)
                                _DetailRow(
                                  icon: Symbols.percent_rounded,
                                  text:
                                      'Incl. VAT ${VatMode.vatPct}% · ${Money.formatZar(b.vatCents)}',
                                ),
                              _DetailRow(
                                icon: Symbols.schedule_rounded,
                                text: queued
                                    ? 'Now · slot assigned on sync'
                                    : SparklingDates.long(b.slotStart),
                              ),
                              _DetailRow(
                                icon: Symbols.receipt_long_rounded,
                                text: paid
                                    ? 'Paid ${Money.formatZar(amount)}${pay?.provider == 'pos' ? ' · ${pay!.receipt?['method'] == 'card_terminal' ? 'card terminal' : 'cash'}' : ''}'
                                    : (pay?.pendingSync ?? false)
                                    ? 'Payment ${Money.formatZar(amount)} queued'
                                    : b.totalCents == 0 && b.isIncluded
                                    ? 'Nothing to pay · included in plan'
                                    : 'Due ${Money.formatZar(amount)} · customer pays in app',
                                iconColor: paid
                                    ? context.sparkling.success
                                    : null,
                              ),
                              if (checkedIn)
                                _DetailRow(
                                  icon: Symbols.garage_rounded,
                                  text:
                                      '${b.workOrder!.ref}${b.workOrder!.bay == null ? '' : ' · ${b.workOrder!.bay}'} · ${b.workOrder!.status.label}',
                                )
                              else if (b.workOrder != null && !queued)
                                _DetailRow(
                                  icon: Symbols.garage_rounded,
                                  text:
                                      '${b.workOrder!.ref} · awaiting check-in',
                                ),
                              if (b.pointsPending > 0)
                                _DetailRow(
                                  icon: Symbols.sell_rounded,
                                  iconColor: context.sparkling.gold,
                                  text:
                                      '+${b.pointsPending} pts for $customerName on completion',
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        InfoBanner(
                          tone: queued ? InfoTone.warning : InfoTone.info,
                          icon: queued
                              ? Symbols.cloud_off_rounded
                              : Symbols.notifications_active_rounded,
                          text: queued
                              ? 'The booking and payment are in the sync queue. The reference and receipt number arrive once the server confirms them.'
                              : 'The customer gets the ${paid ? 'receipt and ' : ''}service updates on WhatsApp / push, and the collection code when the wash is verified.',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (checkedIn && !queued) ...[
                          PillButton(
                            label: 'Open checklist',
                            icon: Symbols.checklist_rounded,
                            variant: PillButtonVariant.navy,
                            expand: true,
                            minHeight: 54,
                            onPressed: () => _openChecklist(b),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (o.customer != null && !queued) ...[
                          PillButton(
                            key: const ValueKey('walkin-raise-quote'),
                            label: 'Raise a quote for this vehicle',
                            icon: Symbols.request_quote_rounded,
                            variant: PillButtonVariant.tonal,
                            expand: true,
                            minHeight: 54,
                            onPressed: () => _raiseQuote(o),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Done',
                                variant: PillButtonVariant.outlined,
                                expand: true,
                                minHeight: 54,
                                onPressed: () => context.go(Routes.tasks),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PillButton(
                                label: 'New walk-in',
                                icon: Symbols.person_add_rounded,
                                expand: true,
                                minHeight: 54,
                                onPressed: () {
                                  StaffHaptics.tap(context);
                                  context.go(Routes.walkIn);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? cs.primary, fill: 1, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: SparklingTypography.titleMedium.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
