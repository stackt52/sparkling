import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import '../quotes/quote_request_screen.dart';
import 'booking_flow.dart';
import 'booking_widgets.dart';

/// Step 3 of 3 — order summary + payment method + pay (1f).
///
/// Price shown here is an estimate from the catalogue and the customer's
/// membership benefit (covered service → "Included in your plan", R 0 base;
/// otherwise the plan discount); the server recomputes it on `POST /bookings`
/// (CUS-022/023) and the payment is only shown as paid after the (sandbox)
/// webhook confirms it (CUS-041/042). A booking with nothing to pay is
/// confirmed without a payment.
///
/// When the `cash_on_collection` flag (`GET /config`) is on and there is
/// something to pay, **Cash on collection** is offered beside the saved
/// methods: `POST /bookings { payment_method: 'cash' }` confirms the booking
/// at once and the customer pays at the counter when collecting the car (no
/// payment intent). A 409 `cash_disabled` deselects the option again.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

/// Saved methods + the public flags the step depends on.
typedef _PaymentOptions = ({List<PaymentMethod> methods, PublicFlags flags});

class _PaymentScreenState extends State<PaymentScreen> {
  Future<_PaymentOptions>? _data;
  bool _paying = false;
  String? _stage;

  /// Set after a 409 `cash_disabled`: hides the option for this attempt.
  bool _cashRefused = false;

  BookingFlowController get _flow => context.bookingFlow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_PaymentOptions> _load() async {
    final repos = context.repos;
    await _flow.loadMembership();
    final (methods, config) = await (
      repos.customer.paymentMethods(),
      repos.config.config(),
    ).wait;
    if (mounted && _flow.methodId == null && methods.isNotEmpty) {
      final def =
          methods.where((m) => m.isDefault).firstOrNull ?? methods.first;
      _flow.setMethod(def.id, choice: _choiceFor(def));
    } else if (mounted && _flow.paymentChoice == null && _flow.methodId != null) {
      // Draft restored from disk: derive the choice from the saved method.
      final saved = methods.where((m) => m.id == _flow.methodId).firstOrNull;
      if (saved != null) _flow.setMethod(saved.id, choice: _choiceFor(saved));
    }
    return (methods: methods, flags: config.flags);
  }

  static PaymentChoice _choiceFor(PaymentMethod m) =>
      m.isCard ? PaymentChoice.card : PaymentChoice.eft;

  Future<void> _pay(int totalCents) async {
    final flow = _flow;
    final repos = context.repos;
    final cash = flow.payCash && !flow.nothingToPay;
    setState(() {
      _paying = true;
      _stage = 'Confirming slot…';
    });
    try {
      final booking = await repos.customer.createBooking(flow.toInput());
      if (!mounted) return;
      if (booking.totalCents <= 0 || cash) {
        // Included in the plan (nothing to pay) or cash on collection — the
        // booking is confirmed without a payment intent.
        final detail = await repos.customer.booking(booking.id);
        if (!mounted) return;
        AppHaptics.success(context);
        flow.reset();
        context.go(Routes.bookDone(booking.id), extra: detail);
        return;
      }
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
      if (e.isByQuote) {
        // Quote-only service (409 validation_error {reason: by_quote}).
        showSnack(context, '${e.message} Opening a quote request.');
        final args = QuoteRequestArgs(
          service: flow.service,
          outlet: flow.outlet,
          vehicle: flow.vehicle,
        );
        flow.reset();
        context.go(Routes.quoteNew, extra: args);
      } else if (e.isCashDisabled) {
        // Flag switched off since the config was fetched: fall back to the
        // saved method and hide the cash option.
        showSnack(context, e.message);
        final methods = (await _data)?.methods ?? const <PaymentMethod>[];
        if (!mounted) return;
        final def =
            methods.where((m) => m.id == flow.methodId).firstOrNull ??
            methods.where((m) => m.isDefault).firstOrNull ??
            methods.firstOrNull;
        flow.setMethod(def?.id, choice: def == null ? null : _choiceFor(def));
        setState(() => _cashRefused = true);
      } else if (e.isConflict && e.message.toLowerCase().contains('slot')) {
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
                child: AsyncView<_PaymentOptions>(
                  future: _data!,
                  onRetry: () => setState(() => _data = _load()),
                  builder: (context, options) {
                    final methods = options.methods;
                    final price = flow.baseCents;
                    final discount = flow.membershipDiscountCents;
                    final vat = flow.estimatedVatCents;
                    final total = flow.estimatedTotalCents;
                    final nothingToPay = flow.nothingToPay;
                    final cashOffered =
                        options.flags.cashOnCollection &&
                        !_cashRefused &&
                        !nothingToPay &&
                        total > 0;
                    final payCash = cashOffered && flow.payCash;
                    final selectedMethod = payCash
                        ? null
                        : methods
                              .where((m) => m.id == flow.methodId)
                              .firstOrNull;
                    final canPay =
                        nothingToPay || payCash || selectedMethod != null;

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
                                vat: vat,
                                total: total,
                              ),
                              const SizedBox(height: 22),
                              if (nothingToPay)
                                InfoBanner(
                                  tone: InfoTone.success,
                                  icon: Symbols.workspace_premium_rounded,
                                  title: 'Nothing to pay',
                                  text:
                                      'This ${flow.service!.name} is included in your ${flow.membership?.planName ?? ''} plan. Confirm to reserve the slot.',
                                )
                              else
                                const SectionHeader(title: 'Payment method'),
                              if (!nothingToPay)
                              for (final m in methods) ...[
                                RadioCard(
                                  selected: !payCash && m.id == flow.methodId,
                                  onChanged: (_) {
                                    AppHaptics.selection(context);
                                    flow.setMethod(m.id, choice: _choiceFor(m));
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
                              if (cashOffered) ...[
                                RadioCard(
                                  key: const ValueKey('pay-cash'),
                                  selected: payCash,
                                  onChanged: (_) {
                                    AppHaptics.selection(context);
                                    flow.setPayCash();
                                  },
                                  radioPosition:
                                      RadioCardRadioPosition.trailing,
                                  leading: TintedIconTile(
                                    icon: Symbols.payments_rounded,
                                    size: 48,
                                    radius: 14,
                                    background:
                                        context.sparkling.warningContainer,
                                    foreground:
                                        context.sparkling.onWarningContainer,
                                  ),
                                  title: Text(
                                    'Cash on collection',
                                    style: SparklingTypography.titleLarge
                                        .copyWith(fontSize: 17),
                                  ),
                                  subtitle: Text(
                                    'Pay ${Money.formatZar(total)} in cash at the counter when you collect your car',
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
                                  label: nothingToPay
                                      ? 'Confirm booking · included'
                                      : payCash
                                      ? 'Confirm booking · pay on collection'
                                      : 'Pay ${Money.formatZar(total)} securely',
                                  icon: nothingToPay || payCash
                                      ? Symbols.check_rounded
                                      : Symbols.lock_rounded,
                                  expand: true,
                                  minHeight: 56,
                                  loading: _paying,
                                  onPressed: canPay ? () => _pay(total) : null,
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
    required this.vat,
    required this.total,
  });

  final BookingFlowController flow;
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
                    flow.isIncluded
                        ? 'Included in your plan · ${flow.membershipLabel?.split(' · ').last ?? ''}'
                        : '${flow.membershipLabel ?? 'Plan discount'} on this booking',
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
