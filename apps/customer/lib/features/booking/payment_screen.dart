import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'booking_flow.dart';
import 'booking_widgets.dart';

/// Step 3 of 3 — order summary + payment method + pay (1f).
///
/// Price shown here is an estimate from the catalogue and published tier
/// discount; the server recomputes it on `POST /bookings` (CUS-022/023) and
/// the payment is only shown as paid after the (sandbox) webhook confirms it
/// (CUS-041/042).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Future<(List<PaymentMethod>, LoyaltyAccountSummary?)>? _data;
  bool _paying = false;
  String? _stage;

  BookingFlowController get _flow => context.bookingFlow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<PaymentMethod>, LoyaltyAccountSummary?)> _load() async {
    final repos = context.repos;
    final methods = await repos.customer.paymentMethods();
    LoyaltyAccountSummary? loyalty;
    try {
      loyalty = await repos.loyalty.account();
    } catch (_) {
      loyalty = null;
    }
    if (mounted && _flow.methodId == null && methods.isNotEmpty) {
      final def =
          methods.where((m) => m.isDefault).firstOrNull ?? methods.first;
      _flow.setMethod(def.id);
    }
    return (methods, loyalty);
  }

  Future<void> _pay(int totalCents) async {
    final flow = _flow;
    final repos = context.repos;
    setState(() {
      _paying = true;
      _stage = 'Confirming slot…';
    });
    try {
      final booking = await repos.customer.createBooking(flow.toInput());
      if (!mounted) return;
      setState(() => _stage = 'Contacting payment provider…');
      final intent = await repos.customer.createPaymentIntent(
        bookingId: booking.id,
        methodId: flow.methodId,
      );
      if (!mounted) return;
      setState(() => _stage = 'Verifying payment…');
      final payment = await repos.customer.confirmSandboxPayment(
        intent.payment.id,
      );
      if (!mounted) return;
      if (!payment.status.isVerified) {
        showSnack(
          context,
          payment.failureReason ??
              'Payment is still ${payment.status.label.toLowerCase()}. '
                  'We will update your booking when the provider confirms.',
        );
      }
      final detail = await repos.customer.booking(booking.id);
      if (!mounted) return;
      AppHaptics.success(context);
      flow.reset();
      context.go(Routes.bookDone(booking.id), extra: detail);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict && e.message.toLowerCase().contains('slot')) {
        showSnack(context, '${e.message} Please pick another time.');
        flow.setSlot(null);
        context.go(Routes.bookSlot);
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
    final flow = _flow;
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) =>
          flow.canPay ? _body(context, cs, flow) : _incomplete(context),
    );
  }

  Widget _incomplete(BuildContext context) {
    {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const ScreenHeader(title: 'Review & pay'),
              EmptyState(
                icon: Symbols.receipt_long_rounded,
                title: 'Your booking draft is incomplete',
                actionLabel: 'Start again',
                onAction: () => context.go(Routes.bookService),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _body(
    BuildContext context,
    ColorScheme cs,
    BookingFlowController flow,
  ) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) => Column(
            children: [
              BookingStepHeader(
                title: 'Review & pay',
                step: 3,
                subtitle: 'Payment',
                onBack: _paying ? () {} : null,
              ),
              Expanded(
                child: AsyncView<(List<PaymentMethod>, LoyaltyAccountSummary?)>(
                  future: _data!,
                  onRetry: () => setState(() => _data = _load()),
                  builder: (context, data) {
                    final (methods, loyalty) = data;
                    final price = flow.service!.priceCents;
                    final tierCfg = loyalty?.currentTierConfig;
                    final pct = tierCfg?.discountPct ?? 0;
                    final discount = (price * pct / 100).round();
                    final total = price - discount;
                    final selectedMethod = methods
                        .where((m) => m.id == flow.methodId)
                        .firstOrNull;

                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                            children: [
                              _SummaryCard(
                                flow: flow,
                                price: price,
                                discount: discount,
                                total: total,
                                tierLabel: loyalty?.tier.label,
                                pct: pct,
                              ),
                              const SizedBox(height: 22),
                              const SectionHeader(title: 'Payment method'),
                              for (final m in methods) ...[
                                RadioCard(
                                  selected: m.id == flow.methodId,
                                  onChanged: (_) {
                                    AppHaptics.selection(context);
                                    flow.setMethod(m.id);
                                  },
                                  radioPosition:
                                      RadioCardRadioPosition.trailing,
                                  leading: BrandPlate(brand: m.brand),
                                  title: Text(
                                    m.displayLabel,
                                    style: SparklingTypography.titleLarge
                                        .copyWith(fontSize: 17),
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
                              ListTileCard(
                                onTap: () => showSnack(
                                  context,
                                  'Adding a card opens the payment provider’s secure page. '
                                  'Not available in this build.',
                                ),
                                leading: TintedIconTile(
                                  icon: Symbols.add_card_rounded,
                                  size: 48,
                                  radius: 14,
                                  background: cs.surfaceContainerHigh,
                                  foreground: cs.onSurfaceVariant,
                                ),
                                title: Text(
                                  'Add card or instant EFT',
                                  style: SparklingTypography.titleLarge
                                      .copyWith(fontSize: 17),
                                ),
                                trailing: Icon(
                                  Symbols.chevron_right_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
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
                                      'Card details are handled by our approved payment provider. '
                                      'Sparkling never stores your card number.',
                                      style: SparklingTypography.bodyMedium
                                          .copyWith(
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
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surface,
                            border: Border(
                              top: BorderSide(color: cs.outlineVariant),
                            ),
                          ),
                          child: BottomActionBar(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_stage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _stage!,
                                      textAlign: TextAlign.center,
                                      style: SparklingTypography.bodyMedium
                                          .copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                PillButton(
                                  label:
                                      'Pay ${Money.formatZar(total)} securely',
                                  icon: Symbols.lock_rounded,
                                  expand: true,
                                  minHeight: 56,
                                  loading: _paying,
                                  onPressed: selectedMethod == null
                                      ? null
                                      : () => _pay(total),
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.flow,
    required this.price,
    required this.discount,
    required this.total,
    required this.tierLabel,
    required this.pct,
  });

  final BookingFlowController flow;
  final int price;
  final int discount;
  final int total;
  final String? tierLabel;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final s = flow.service!;
    final rowStyle = SparklingTypography.bodyLarge.copyWith(
      fontSize: 16,
      color: cs.onSurfaceVariant,
    );
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
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${shortOutletName(flow.outlet!.name)} · ${SparklingDates.long(flow.slotStart!)}',
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
              Expanded(child: Text(s.name, style: rowStyle)),
              Text(
                Money.formatZar(price),
                style: rowStyle.copyWith(color: cs.onSurface),
              ),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Symbols.sell_rounded, size: 18, color: x.success, fill: 1),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tierLabel ?? 'Loyalty'} reward · $pct% off',
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
