import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// Booking confirmed (1g): expressive blob, ref, details, notice, actions.
class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key, required this.bookingId, this.initial});

  final String bookingId;
  final Booking? initial;

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  Future<Booking>? _booking;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _booking ??= widget.initial != null
        ? Future.value(widget.initial)
        : context.repos.customer.booking(widget.bookingId);
  }

  Future<void> _showReceipt(Booking b) async {
    final pay = b.payment;
    if (pay == null) {
      showSnack(context, 'No receipt yet — payment is still pending.');
      return;
    }
    Payment? full;
    try {
      full = await context.repos.customer.payment(pay.id);
    } catch (_) {
      full = null;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Receipt'),
              KeyValueTile(
                label: 'Receipt no',
                value: full?.receiptNo ?? pay.receiptNo ?? '—',
                mono: true,
              ),
              const SizedBox(height: 8),
              KeyValueTile(
                label: 'Amount',
                value: Money.formatZar(full?.amountCents ?? pay.amountCents),
              ),
              const SizedBox(height: 8),
              KeyValueTile(
                label: 'Status',
                value: (full?.status ?? pay.status).label,
                helper: full?.verifiedAt == null
                    ? 'Awaiting provider confirmation'
                    : 'Verified ${SparklingDates.long(full!.verifiedAt!)}',
              ),
              const SizedBox(height: 8),
              KeyValueTile(label: 'Booking', value: b.ref, mono: true),
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
        child: AsyncView<Booking>(
          future: _booking!,
          onRetry: () => setState(
            () => _booking = context.repos.customer.booking(widget.bookingId),
          ),
          builder: (context, b) {
            final paid = b.payment?.status.isVerified ?? false;
            final amount = b.payment?.amountCents ?? b.totalCents;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    children: [
                      const Center(child: ConfettiBlob(size: 190)),
                      const SizedBox(height: 8),
                      Text(
                        'Booking confirmed',
                        textAlign: TextAlign.center,
                        style: SparklingTypography.headlineLarge.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${shortOutletName(b.outlet?.name)} is expecting your ${b.vehicle?.shortName ?? 'vehicle'}.',
                        textAlign: TextAlign.center,
                        style: SparklingTypography.bodyLarge.copyWith(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                              icon: Symbols.calendar_month_rounded,
                              text: SparklingDates.long(b.slotStart),
                              actionLabel: 'Add to calendar',
                              onAction: () => showSnack(
                                context,
                                'Calendar export is coming soon.',
                              ),
                            ),
                            _DetailRow(
                              icon: serviceIcon(b.service?.icon),
                              text:
                                  '${b.service?.name ?? 'Service'} · ${paid ? 'paid' : 'due'} ${Money.formatZar(amount)}',
                              actionLabel: paid ? 'Receipt' : null,
                              onAction: () => _showReceipt(b),
                            ),
                            _DetailRow(
                              icon: Symbols.sell_rounded,
                              iconColor: context.sparkling.gold,
                              text:
                                  '+${b.pointsPending} pts pending completion',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      InfoBanner(
                        tone: InfoTone.info,
                        icon: Symbols.notifications_active_rounded,
                        text: "We'll notify you on WhatsApp and push when your wash starts and when it's ready.",
                      ),
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
                          label: 'Done',
                          variant: PillButtonVariant.outlined,
                          expand: true,
                          minHeight: 54,
                          onPressed: () => context.go(Routes.home),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: PillButton(
                          label: 'Track service',
                          variant: PillButtonVariant.navy,
                          expand: true,
                          minHeight: 54,
                          onPressed: () {
                            context.go(Routes.bookings);
                            context.push(Routes.track(b.id));
                          },
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
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.text,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;

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
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
