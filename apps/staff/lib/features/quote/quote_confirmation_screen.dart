import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import 'quote_actions.dart';
import 'quote_widgets.dart';
import 'raise_quote_controller.dart';

/// Quote raised (1g style): confetti blob, ref in mono, total, "Sent to
/// {name} on WhatsApp" banner, public link (copy / share / resend), PDF,
/// View quote / New quote / Done.
class QuoteConfirmationScreen extends StatefulWidget {
  const QuoteConfirmationScreen({
    super.key,
    required this.quotationId,
    this.outcome,
  });

  final String quotationId;
  final RaiseQuoteOutcome? outcome;

  @override
  State<QuoteConfirmationScreen> createState() =>
      _QuoteConfirmationScreenState();
}

class _QuoteConfirmationScreenState extends State<QuoteConfirmationScreen> {
  Future<RaiseQuoteOutcome>? _outcome;
  String? _publicUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outcome ??= widget.outcome != null
        ? Future.value(widget.outcome)
        : _load();
  }

  Future<RaiseQuoteOutcome> _load() async {
    final q = await context.repositories.staff.quotation(widget.quotationId);
    return RaiseQuoteOutcome(quotation: q);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<RaiseQuoteOutcome>(
          future: _outcome,
          builder: (context, snap) => AsyncView<RaiseQuoteOutcome>(
            snapshot: snap,
            onRetry: () {
              final f = _load();
              setState(() {
                _outcome = f;
              });
            },
            builder: (context, o) {
              final q = o.quotation;
              final queued = o.queued;
              final firstName =
                  o.customer?.firstName ??
                  q.customerName?.split(' ').first ??
                  'the customer';
              final url = _publicUrl ?? q.publicUrl;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      children: [
                        Center(
                          child: ConfettiBlob(
                            size: 150,
                            icon: queued
                                ? Symbols.cloud_upload_rounded
                                : Symbols.request_quote_rounded,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          queued ? 'Quote queued' : 'Quote raised',
                          textAlign: TextAlign.center,
                          style: SparklingTypography.headlineLarge.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                                  text: q.ref,
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
                        const SizedBox(height: 8),
                        Text(
                          Money.formatZar(q.amountCents ?? q.itemsTotalCents),
                          key: const ValueKey('quote-confirmation-total'),
                          textAlign: TextAlign.center,
                          style: SparklingTypography.headlineMedium.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        Text(
                          [
                            '${q.items.length} item${q.items.length == 1 ? '' : 's'}',
                            if (q.vehicleLabel != null) q.vehicleLabel!,
                            if (q.validUntil != null)
                              'valid until ${SparklingDates.dayMonth(q.validUntil!)}',
                          ].join(' · '),
                          textAlign: TextAlign.center,
                          style: SparklingTypography.bodyMedium.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        InfoBanner(
                          tone: queued
                              ? InfoTone.warning
                              : o.sentToCustomer
                              ? InfoTone.success
                              : InfoTone.info,
                          icon: queued
                              ? Symbols.cloud_off_rounded
                              : o.sentToCustomer
                              ? Symbols.chat_rounded
                              : Symbols.drafts_rounded,
                          title: queued
                              ? 'Sent once online'
                              : o.sentToCustomer
                              ? 'Sent to $firstName on WhatsApp'
                              : 'Not sent yet',
                          text: queued
                              ? 'The quote and its ${o.deferredPhotos} photo${o.deferredPhotos == 1 ? '' : 's'} are in the sync queue. The reference and public link arrive when the server confirms them.'
                              : o.sentToCustomer
                              ? '$firstName also got a push notification. They accept or decline in the app or on the public page — once.'
                              : 'Share the public link below or resend from the quote screen when ready.',
                        ),
                        // Work order state: created the moment the customer
                        // accepts, awaiting check-in until the car arrives.
                        const SizedBox(height: 10),
                        if (q.workOrder != null || quotePaymentLabel(q) != null)
                          QuoteStateChips(
                            quotation: q,
                            alignment: WrapAlignment.center,
                          )
                        else if (!queued)
                          Text(
                            'Work order · created the moment $firstName accepts, then on the board awaiting check-in until the car arrives.',
                            key: const ValueKey('quote-work-order-note'),
                            textAlign: TextAlign.center,
                            style: SparklingTypography.bodyMedium.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (o.failedUploads > 0) ...[
                          const SizedBox(height: 10),
                          InfoBanner(
                            tone: InfoTone.warning,
                            icon: Symbols.broken_image_rounded,
                            text:
                                '${o.failedUploads} photo${o.failedUploads == 1 ? '' : 's'} could not be uploaded — add ${o.failedUploads == 1 ? 'it' : 'them'} again from the quote screen.',
                          ),
                        ],
                        if (url != null) ...[
                          const SizedBox(height: 14),
                          PublicLinkCard(quotation: q, url: url),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ResendLinkButton(
                                  quotation: q,
                                  onShared: (link) =>
                                      setState(() => _publicUrl = link.publicUrl),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PillButton(
                                  key: const ValueKey('quote-download-pdf'),
                                  label: 'Download PDF',
                                  icon: Symbols.picture_as_pdf_rounded,
                                  variant: PillButtonVariant.outlined,
                                  expand: true,
                                  minHeight: 52,
                                  onPressed: () =>
                                      QuoteActions.downloadPdf(context, q),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!queued) ...[
                          PillButton(
                            key: const ValueKey('quote-view'),
                            label: 'View quote',
                            icon: Symbols.receipt_long_rounded,
                            variant: PillButtonVariant.navy,
                            expand: true,
                            minHeight: 54,
                            onPressed: () {
                              context.go(Routes.tasks);
                              context.push(Routes.quoteDetail(q.id));
                            },
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
                                label: 'New quote',
                                icon: Symbols.add_rounded,
                                expand: true,
                                minHeight: 54,
                                onPressed: () {
                                  StaffHaptics.tap(context);
                                  context.go(Routes.quoteNew);
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
