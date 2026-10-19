import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Method + reference fields of a counter payment (cash / card terminal /
/// EFT), shared by the hand-over sheet, the check-in forms (assign sheet,
/// scan review) and the quotation cash sheet. The amount is fixed to the
/// booking / quotation total — the API refuses anything else — so only the
/// method and its reference are asked for; an EFT needs its reference.
///
/// Keys: `<keyPrefix>-method-cash|card|eft`, `<keyPrefix>-reference`.
class CounterPaymentFields extends StatelessWidget {
  const CounterPaymentFields({
    super.key,
    required this.method,
    required this.onMethodChanged,
    required this.reference,
    this.enabled = true,
    this.keyPrefix = 'payment',
  });

  final PaymentMethodKind method;
  final ValueChanged<PaymentMethodKind> onMethodChanged;
  final TextEditingController reference;
  final bool enabled;
  final String keyPrefix;

  /// The payment these fields describe, for [amountCents]; `null` while an
  /// EFT has no reference yet.
  static CounterPaymentInput? inputFor({
    required PaymentMethodKind method,
    required TextEditingController reference,
    required int amountCents,
    required String idempotencyKey,
  }) {
    final input = CounterPaymentInput(
      method: method,
      reference: reference.text,
      amountCents: amountCents,
      idempotencyKey: idempotencyKey,
    );
    return input.isMissingReference ? null : input;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          ignoring: !enabled,
          child: Row(
            children: [
              for (final (i, m) in PaymentMethodKind.values.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _MethodPill(
                    key: ValueKey(
                      '$keyPrefix-method-${switch (m) {
                        PaymentMethodKind.cash => 'cash',
                        PaymentMethodKind.cardTerminal => 'card',
                        PaymentMethodKind.eft => 'eft',
                      }}',
                    ),
                    method: m,
                    selected: m == method,
                    onTap: () => onMethodChanged(m),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ValueKey('$keyPrefix-reference'),
          controller: reference,
          enabled: enabled,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: method.referenceHint,
            prefixIcon: Icon(
              method == PaymentMethodKind.eft
                  ? Symbols.account_balance_rounded
                  : Symbols.receipt_long_rounded,
            ),
            helperText: method.requiresReference
                ? 'The bank reference is kept on the receipt.'
                : null,
            helperStyle: SparklingTypography.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethodKind method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final bg = selected
        ? (dark ? cs.primary : SparklingColors.navy)
        : cs.surfaceContainer;
    final fg = selected
        ? (dark ? cs.onPrimary : Colors.white)
        : cs.onSurfaceVariant;
    final icon = switch (method) {
      PaymentMethodKind.cash => Symbols.payments_rounded,
      PaymentMethodKind.cardTerminal => Symbols.credit_card_rounded,
      PaymentMethodKind.eft => Symbols.account_balance_rounded,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: method.label,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg, fill: selected ? 1 : 0),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    method.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SparklingTypography.titleMedium.copyWith(
                      fontSize: 14,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Take payment now · R x" switch that reveals [CounterPaymentFields] — the
/// check-in forms use it so the car can be checked in and paid for in one go.
class TakePaymentToggle extends StatelessWidget {
  const TakePaymentToggle({
    super.key,
    required this.amountCents,
    required this.value,
    required this.onChanged,
    required this.method,
    required this.onMethodChanged,
    required this.reference,
    this.enabled = true,
    this.keyPrefix = 'check-in-payment',
    this.subtitle,
  });

  final int amountCents;
  final bool value;
  final ValueChanged<bool> onChanged;
  final PaymentMethodKind method;
  final ValueChanged<PaymentMethodKind> onMethodChanged;
  final TextEditingController reference;
  final bool enabled;
  final String keyPrefix;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTileCard(
          key: ValueKey('$keyPrefix-toggle'),
          onTap: enabled ? () => onChanged(!value) : null,
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          leading: Icon(
            Symbols.point_of_sale_rounded,
            color: value ? cs.primary : cs.onSurfaceVariant,
            fill: value ? 1 : 0,
          ),
          title: Text('Take payment now · ${Money.formatZar(amountCents)}'),
          subtitle: Text(
            subtitle ??
                'The booking is unpaid. Record the payment with the check-in, '
                    'or leave it for collection.',
          ),
          trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
        ),
        if (value) ...[
          const SizedBox(height: 10),
          CounterPaymentFields(
            method: method,
            onMethodChanged: onMethodChanged,
            reference: reference,
            enabled: enabled,
            keyPrefix: keyPrefix,
          ),
        ],
      ],
    );
  }
}

/// Short receipt line for a recorded counter [payment]
/// ("R 120.00 card terminal · RCP-70001").
String counterPaymentLabel(Payment payment) {
  final method = PaymentMethodKind.fromDb(payment.method).label.toLowerCase();
  final amount = Money.formatZar(payment.amountCents);
  return payment.receiptNo == null
      ? '$amount $method'
      : '$amount $method · ${payment.receiptNo}';
}
