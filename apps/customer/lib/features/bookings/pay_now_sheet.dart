import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';

/// "Pay now" for an unpaid booking after it was made — the car is checked in
/// or ready for collection (or the online payment never completed): the
/// customer picks a saved method and pays in-app through the same provider
/// flow as "Review & pay" (`POST /payments/intents` + sandbox confirm,
/// CUS-041/042). Staff can otherwise take the payment at the counter.
///
/// Pops with the verified [Payment], or `null` when dismissed / still
/// pending with the provider.
Future<Payment?> showPayNowSheet(BuildContext context, Booking booking) {
  return showModalBottomSheet<Payment>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) => PayNowSheet(booking: booking),
  );
}

/// Bottom-sheet body of [showPayNowSheet] (public so tests can host it).
class PayNowSheet extends StatefulWidget {
  const PayNowSheet({super.key, required this.booking});

  final Booking booking;

  @override
  State<PayNowSheet> createState() => _PayNowSheetState();
}

class _PayNowSheetState extends State<PayNowSheet> {
  Future<List<PaymentMethod>>? _methods;
  String? _methodId;
  bool _paying = false;
  String? _stage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _methods ??= _load();
  }

  Future<List<PaymentMethod>> _load() async {
    final methods = await context.repos.customer.paymentMethods();
    if (mounted && _methodId == null && methods.isNotEmpty) {
      final def =
          methods.where((m) => m.isDefault).firstOrNull ?? methods.first;
      setState(() => _methodId = def.id);
    }
    return methods;
  }

  Future<void> _pay() async {
    if (_paying) return;
    final repos = context.repos;
    final b = widget.booking;
    setState(() {
      _paying = true;
      _stage = 'Contacting payment provider…';
    });
    try {
      final intent = await repos.customer.createPaymentIntent(
        bookingId: b.id,
        methodId: _methodId,
      );
      if (!mounted) return;
      setState(() => _stage = 'Verifying payment…');
      final payment = await repos.customer.confirmSandboxPayment(
        intent.payment.id,
      );
      if (!mounted) return;
      if (payment.status.isVerified) {
        AppHaptics.success(context);
        Navigator.of(context).pop(payment);
        return;
      }
      showSnack(
        context,
        payment.failureReason ??
            'Payment is still ${payment.status.label.toLowerCase()}. '
                'We will update your booking when the provider confirms.',
      );
      Navigator.of(context).pop(null);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict && e.message.toLowerCase().contains('already paid')) {
        showSnack(context, 'This booking is already paid.');
        Navigator.of(context).pop(null);
      } else {
        showSnack(context, e.message);
      }
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) {
        setState(() {
          _paying = false;
          _stage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final b = widget.booking;
    final amount = Money.formatZar(b.totalCents);
    final moment = b.status == BookingStatus.completed
        ? 'Your car is ready — settle the booking before you collect it.'
        : b.isInService
        ? 'Your car is being looked after — you can settle the booking now.'
        : 'This booking has not been paid yet.';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: DragHandle()),
              const SizedBox(height: 14),
              Text(
                'Pay $amount',
                style: SparklingTypography.headlineSmall.copyWith(
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${b.ref} · ${b.title}',
                style: SparklingTypography.bodyLarge.copyWith(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              InfoBanner(
                tone: InfoTone.info,
                icon: Symbols.payments_rounded,
                text: b.isCashOnCollection
                    ? '$moment You chose to pay ${b.paysAtCheckIn ? 'at check-in' : 'on collection'} — paying here '
                          'means nothing is due at the counter.'
                    : moment,
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<PaymentMethod>>(
                future: _methods,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorView(
                      error: snap.error,
                      onRetry: () => setState(() => _methods = _load()),
                    );
                  }
                  final methods = snap.data;
                  if (methods == null) return const LoadingView();
                  if (methods.isEmpty) {
                    return const InfoBanner(
                      tone: InfoTone.warning,
                      text:
                          'No saved card or instant EFT yet. Add one under '
                          'Profile, or pay at the counter.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Payment method'),
                      for (final m in methods) ...[
                        RadioCard(
                          key: ValueKey('pay-now-method-${m.id}'),
                          selected: m.id == _methodId,
                          onChanged: _paying
                              ? null
                              : (_) {
                                  AppHaptics.selection(context);
                                  setState(() => _methodId = m.id);
                                },
                          radioPosition: RadioCardRadioPosition.trailing,
                          leading: BrandPlate(brand: m.brand),
                          title: Text(
                            m.displayLabel,
                            style: SparklingTypography.titleLarge.copyWith(
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Text(
                            m.isCard
                                ? (m.isDefault
                                      ? 'Default card · tokenised'
                                      : 'Tokenised card')
                                : 'Pay from your bank app',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              PillButton(
                key: const ValueKey('pay-now-confirm'),
                label: _stage ?? 'Pay $amount securely',
                icon: Symbols.lock_rounded,
                expand: true,
                minHeight: 56,
                loading: _paying,
                onPressed: _paying || _methodId == null ? null : _pay,
              ),
              const SizedBox(height: 8),
              Text(
                'Your card details never touch our servers — the provider '
                'confirms the payment and we issue the receipt.',
                textAlign: TextAlign.center,
                style: SparklingTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
