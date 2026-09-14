import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import '../../widgets/segmented_pills.dart';
import '../quote/raise_quote_controller.dart';
import 'walk_in_flow.dart';
import 'walk_in_widgets.dart';

/// Step 4 of 4 — order summary (1f), payment method (cash / card terminal /
/// customer pays in app), optional immediate check-in (bay + priority) and
/// the confirm CTA: `POST /bookings` (walk-in) → `POST /payments/record`.
///
/// Prices shown are the catalogue estimate; the server recomputes on
/// submit and the payment is recorded against the returned total.
class PaymentStep extends StatefulWidget {
  const PaymentStep({super.key, required this.flow, required this.onBack});

  final WalkInFlowController flow;
  final VoidCallback onBack;

  @override
  State<PaymentStep> createState() => _PaymentStepState();
}

class _PaymentStepState extends State<PaymentStep> {
  late final _bay = TextEditingController(text: widget.flow.bay ?? '');
  late final _reference = TextEditingController(
    text: widget.flow.paymentReference ?? '',
  );
  bool _busy = false;
  String? _stage;

  WalkInFlowController get _flow => widget.flow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flow.customer != null && _flow.membership == null) {
      unawaited(_flow.loadMembership(context.repositories));
    }
  }

  @override
  void dispose() {
    _bay.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final flow = _flow;
    if (!flow.canPay) return;
    final staff = context.repositories.staff;
    flow.setCheckIn(bay: _bay.text);
    flow.setPaymentReference(_reference.text);
    setState(() {
      _busy = true;
      _stage = flow.bookNow ? 'Checking bay capacity…' : 'Confirming slot…';
    });
    try {
      final booking = await staff.createWalkInBooking(flow.toBookingInput());
      if (!mounted) return;
      Payment? payment;
      final payInput = flow.toPaymentInput(booking);
      if (payInput != null) {
        setState(() => _stage = 'Recording ${flow.payment.label.toLowerCase()}…');
        try {
          payment = await staff.recordPayment(payInput);
        } on ApiException catch (e) {
          // The booking exists — surface the payment problem and continue.
          if (!mounted) return;
          StaffSnack.show(
            context,
            'Booking ${booking.ref} created, but the payment was not recorded: ${e.message}',
          );
        }
      }
      if (!mounted) return;
      final outcome = WalkInOutcome(
        booking: booking,
        payment: payment,
        customer: flow.customer,
      );
      StaffHaptics.success(context);
      flow.reset();
      context.go(Routes.walkInConfirmation(booking.id), extra: outcome);
    } on ApiException catch (e) {
      if (!mounted) return;
      StaffHaptics.error(context);
      final msg = e.message.toLowerCase();
      if (e.isByQuote) {
        // Quote-only service: hand the customer + vehicle to the quote flow.
        StaffSnack.show(context, '${e.message} Raising a quote instead.');
        final args = RaiseQuoteArgs(
          customer: flow.customer,
          vehicle: flow.vehicle,
          service: flow.service,
        );
        flow.rotateOpIds();
        context.push(Routes.quoteNew, extra: args);
      } else if (e.isConflict &&
          (msg.contains('bay') || msg.contains('slot') || msg.contains('busy'))) {
        // No bay free / slot gone: keep the draft, suggest a slot.
        flow.rotateOpIds();
        flow.setSlot(null);
        flow.setBookNow(false);
        StaffSnack.show(context, '${e.message} Pick a slot instead.');
        widget.onBack();
      } else if (e.isConflict) {
        flow.rotateOpIds();
        await showConflictDialog(context, e);
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        if (!flow.canPay) {
          return Column(
            children: [
              BookingStepHeader(
                title: 'Walk-in booking',
                step: 4,
                subtitle: 'Payment & confirm',
                onBack: widget.onBack,
              ),
              Expanded(
                child: Center(
                  child: PillButton(
                    label: 'Finish the earlier steps',
                    variant: PillButtonVariant.tonal,
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            ],
          );
        }
        final price = flow.priceCents;
        final discount = flow.membershipDiscountCents;
        final vat = flow.estimatedVatCents;
        final total = flow.estimatedTotalCents;
        final nothingToPay = flow.nothingToPay;
        final offline = !context.syncStatus.online;
        return Column(
          children: [
            BookingStepHeader(
              title: 'Walk-in booking',
              step: 4,
              subtitle: 'Payment & confirm',
              onBack: _busy ? null : widget.onBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                children: [
                  const LiveOfflineBanner(
                    margin: EdgeInsets.only(bottom: 12),
                  ),
                  _SummaryCard(
                    flow: flow,
                    price: price,
                    discount: discount,
                    vat: vat,
                    total: total,
                  ),
                  const SizedBox(height: 22),
                  if (nothingToPay)
                    InfoBanner(
                      key: const ValueKey('nothing-to-pay'),
                      tone: InfoTone.success,
                      icon: Symbols.workspace_premium_rounded,
                      title: 'Nothing to pay',
                      text:
                          '${flow.service!.name} is included in ${flow.customer!.firstName}\'s ${flow.membership?.planName ?? ''} plan (${flow.membershipLabel?.split(' · ').last ?? ''} after this wash).',
                    )
                  else
                    const SectionHeader(title: 'Payment'),
                  if (!nothingToPay)
                  for (final p in WalkInPayment.values) ...[
                    RadioCard(
                      selected: flow.payment == p,
                      onChanged: (_) {
                        StaffHaptics.tap(context);
                        flow.setPayment(p);
                      },
                      radioPosition: RadioCardRadioPosition.trailing,
                      leading: TintedIconTile(
                        icon: switch (p) {
                          WalkInPayment.cash => Symbols.payments_rounded,
                          WalkInPayment.cardTerminal =>
                            Symbols.contactless_rounded,
                          WalkInPayment.inApp =>
                            Symbols.phone_android_rounded,
                        },
                        size: 44,
                        radius: SparklingShapes.iconTileSmall,
                        background: flow.payment == p
                            ? cs.primary.withValues(alpha: 0.18)
                            : cs.surfaceContainerHigh,
                        foreground: flow.payment == p
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                      title: Text(
                        p.label,
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 17,
                        ),
                      ),
                      subtitle: Text(switch (p) {
                        WalkInPayment.cash =>
                          'Recorded now · receipt issued (staff-attested)',
                        WalkInPayment.cardTerminal =>
                          'Recorded now · add the slip reference',
                        WalkInPayment.inApp =>
                          'Booking stays pending payment in the customer app',
                      }),
                      footer: p == WalkInPayment.cardTerminal &&
                              flow.payment == p
                          ? TextField(
                              controller: _reference,
                              textCapitalization:
                                  TextCapitalization.characters,
                              onChanged: flow.setPaymentReference,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Terminal reference (optional)',
                                hintText: 'e.g. slip 4471',
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 12),
                  const SectionHeader(title: 'Check-in'),
                  ListTileCard(
                    onTap: () => flow.setCheckIn(now: !flow.checkInNow),
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                    leading: Icon(
                      Symbols.local_car_wash_rounded,
                      color: cs.primary,
                      fill: 1,
                    ),
                    title: const Text('Check in now'),
                    subtitle: Text(
                      flow.checkInNow
                          ? 'Creates the work order and task immediately'
                          : 'Vehicle is checked in later from the scanner',
                      maxLines: 2,
                    ),
                    trailing: Switch(
                      value: flow.checkInNow,
                      onChanged: (v) => flow.setCheckIn(now: v),
                    ),
                  ),
                  if (flow.checkInNow) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bay,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) => flow.setCheckIn(bay: v),
                      decoration: const InputDecoration(
                        hintText: 'Bay (e.g. Bay 2)',
                        prefixIcon: Icon(Symbols.garage_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedPills<int>(
                      selected: flow.priority,
                      onChanged: (p) => flow.setCheckIn(priority: p),
                      segments: const [
                        PillSegment(value: 1, label: 'P1 · urgent'),
                        PillSegment(value: 2, label: 'P2'),
                        PillSegment(value: 3, label: 'P3'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Symbols.verified_user_rounded,
                        size: 20,
                        color: cs.onSurfaceVariant,
                        fill: 1,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          offline
                              ? 'You are offline: the booking and payment are queued with your name and will sync when you reconnect.'
                              : 'Cash and terminal payments are recorded under your name and audited. The customer gets the receipt by WhatsApp / push.',
                          style: SparklingTypography.bodyMedium.copyWith(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            BottomActionBar(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_stage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _stage!,
                        textAlign: TextAlign.center,
                        style: SparklingTypography.bodyMedium.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  PillButton(
                    label: 'Confirm walk-in · ${compactZar(total)}',
                    icon: flow.checkInNow
                        ? Symbols.check_rounded
                        : Symbols.event_available_rounded,
                    expand: true,
                    minHeight: 56,
                    loading: _busy,
                    onPressed: _busy ? null : _confirm,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.flow,
    required this.price,
    required this.discount,
    required this.vat,
    required this.total,
  });

  final WalkInFlowController flow;
  final int price;
  final int discount;
  final int vat;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final s = flow.service!;
    final rowStyle = SparklingTypography.bodyLarge.copyWith(
      fontSize: 16,
      color: cs.onSurfaceVariant,
    );
    final when = flow.bookNow
        ? 'now'
        : SparklingDates.long(flow.slotStart!);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TintedIconTile(icon: serviceIcon(s.service.icon), size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.name} · ${flow.vehicle!.shortName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${flow.customer!.fullName} · ${shortOutletName(flow.outlet!.name)} · $when',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.bodyMedium.copyWith(
                        fontSize: 14.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.name} · ${flow.vehicleSize.label.toLowerCase()}',
                  style: rowStyle,
                ),
              ),
              Text(
                Money.formatZar(price),
                style: rowStyle.copyWith(color: cs.onSurface),
              ),
            ],
          ),
          for (final a in flow.addons) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Symbols.add_circle_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                  fill: 1,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(a.name, style: rowStyle)),
                Text(
                  Money.formatZar(a.priceFor(flow.vehicleSize) ?? 0),
                  style: rowStyle.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ],
          if (flow.addons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subtotal',
                    style: rowStyle.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  Money.formatZar(flow.subtotalCents),
                  style: rowStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (discount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  flow.isIncluded
                      ? Symbols.workspace_premium_rounded
                      : Symbols.sell_rounded,
                  size: 18,
                  color: x.success,
                  fill: 1,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    flow.membershipLabel ?? 'Plan discount',
                    style: rowStyle.copyWith(color: x.success),
                  ),
                ),
                Text(
                  '${Money.minus} ${Money.formatZar(discount)}',
                  style: rowStyle.copyWith(
                    color: x.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (vat > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('VAT ${VatMode.vatPct}%', style: rowStyle),
                ),
                Text(
                  Money.formatZar(vat),
                  style: rowStyle.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const DashedDivider(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Total due',
                  style: SparklingTypography.titleLarge.copyWith(
                    fontSize: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                Money.formatZar(total),
                style: SparklingTypography.headlineMedium.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
