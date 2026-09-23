import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';
import 'quote_widgets.dart';

/// Quotation detail (CUS-030..034): itemised attention areas with category
/// chips, damage photos (authed), items note, assessor + outlet, validity,
/// and the one-time Accept / Decline with confirm sheets. After the decision
/// the screen locks ("Accepted on 12 Sep in app" / "… via link"); a 409 from
/// the API refreshes the quote and shows "Already decided".
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  Future<Quotation>? _future;
  bool _busy = false;
  bool _alreadyDecided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.repos.customer.quotation(widget.quotationId);
  }

  void _reload() {
    final f = context.repos.customer.quotation(widget.quotationId);
    setState(() {
      _future = f;
    });
  }

  Future<bool> _confirm(Quotation q, {required bool accept}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _DecisionSheet(quotation: q, accept: accept),
      ),
    );
    return ok ?? false;
  }

  Future<void> _decide(Quotation q, {required bool accept}) async {
    if (_busy) return;
    String? note;
    if (accept) {
      if (!await _confirm(q, accept: true)) return;
    } else {
      final result = await showModalBottomSheet<String?>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _DeclineSheet(quotation: q),
        ),
      );
      if (result == null) return;
      note = result.trim().isEmpty ? null : result.trim();
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await context.repos.customer.decideQuotation(
        q.id,
        accept: accept,
        note: note,
      );
      if (!mounted) return;
      AppHaptics.success(context);
      showSnack(
        context,
        accept
            ? 'Quote ${updated.ref} accepted.'
            : 'Quote ${updated.ref} declined.',
      );
      setState(() {
        _future = Future.value(updated);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        // Decided elsewhere (public link / another device): refresh + lock.
        setState(() => _alreadyDecided = true);
        showSnack(context, 'Already decided — ${e.message}');
        _reload();
      } else if (e.code == 'gone' || e.statusCode == 410) {
        showSnack(context, e.message);
        _reload();
      } else {
        showSnack(context, describeError(e));
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
        child: AsyncView<Quotation>(
          future: _future!,
          onRetry: _reload,
          loading: const Column(
            children: [
              ScreenHeader(title: 'Quote'),
              LoadingView(),
            ],
          ),
          builder: (context, q) {
            final expired = q.isExpired || q.status == QuotationStatus.expired;
            final canDecide = q.canDecide && !_alreadyDecided;
            return Column(
              children: [
                ScreenHeader(
                  title: q.ref,
                  titleWidget: Text(
                    q.ref,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SparklingTypography.mono(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  subtitle: '${q.category} · ${q.vehicleLabel ?? ''}',
                  trailing: StatusChip(
                    label: expired && q.status == QuotationStatus.quoted
                        ? 'Expired'
                        : q.status.label,
                    tone: expired && q.status == QuotationStatus.quoted
                        ? StatusChipTone.error
                        : quotationTone(q.status),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      if (_alreadyDecided && !q.isDecided)
                        const InfoBanner(
                          tone: InfoTone.warning,
                          icon: Symbols.sync_problem_rounded,
                          title: 'Already decided',
                          text:
                              'This quote was answered elsewhere (public link or another device). Refreshing…',
                        )
                      else if (q.isDecided)
                        _DecisionBanner(quotation: q)
                      else if (q.status == QuotationStatus.quoted && expired)
                        InfoBanner(
                          tone: InfoTone.error,
                          icon: Symbols.event_busy_rounded,
                          title: 'This quote has expired',
                          text:
                              '${validityLabel(q)}. Ask ${shortOutletName(q.outletName)} for a fresh one.',
                        )
                      else if (q.status.awaitingDecision)
                        InfoBanner(
                          tone: InfoTone.warning,
                          icon: Symbols.schedule_rounded,
                          title: 'Your decision is needed',
                          text:
                              '${validityLabel(q)}. Nothing is booked until you approve — you can answer once.',
                        )
                      else if (q.status == QuotationStatus.requested ||
                          q.status == QuotationStatus.assessing)
                        const InfoBanner(
                          tone: InfoTone.info,
                          icon: Symbols.schedule_rounded,
                          text:
                              'An estimator is reviewing your request and will reply within 24 h.',
                        ),
                      const SizedBox(height: 14),
                      KeyValueTile(
                        label: 'Outlet',
                        value: q.outletName ?? '—',
                        helper: q.assessorName == null
                            ? null
                            : 'Assessed by ${q.assessorName}',
                      ),
                      if (q.validUntil != null) ...[
                        const SizedBox(height: 10),
                        KeyValueTile(
                          label: 'Valid until',
                          value: SparklingDates.dayMonth(q.validUntil!),
                          warning: expired && !q.isDecided,
                          helper: q.isDecided ? null : expiryHelper(q),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DESCRIPTION',
                              style: SparklingTypography.overline.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              q.description,
                              style: SparklingTypography.bodyLarge.copyWith(
                                fontSize: 15,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (q.items.isNotEmpty || q.amountCents != null) ...[
                        const SizedBox(height: 10),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'WHAT NEEDS ATTENTION',
                                style: SparklingTypography.overline.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              for (final li in q.items)
                                _ItemRow(item: li),
                              const SizedBox(height: 8),
                              const DashedDivider(),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Quoted total',
                                      style: SparklingTypography.titleMedium
                                          .copyWith(color: cs.onSurface),
                                    ),
                                  ),
                                  Text(
                                    Money.formatZar(
                                      q.amountCents ?? q.itemsTotalCents,
                                    ),
                                    style: SparklingTypography.headlineMedium
                                        .copyWith(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary,
                                        ),
                                  ),
                                ],
                              ),
                              if (q.itemsNote != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Symbols.sticky_note_2_rounded,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        q.itemsNote!,
                                        style: SparklingTypography.bodyMedium
                                            .copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                'TERMS',
                                style: SparklingTypography.overline.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                q.terms ?? kQuoteTerms,
                                style: SparklingTypography.bodySmall.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (q.photos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SectionHeader(
                          title: 'Damage photos',
                          trailing: Text(
                            '${q.photos.length}',
                            style: SparklingTypography.bodyLarge.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final a in q.photos)
                              QuotePhotoTile(
                                key: ValueKey('quote-photo-${a.id}'),
                                attachment: a,
                              ),
                          ],
                        ),
                      ],
                      if (q.decisionNote != null) ...[
                        const SizedBox(height: 10),
                        KeyValueTile(label: 'Your note', value: q.decisionNote!),
                      ],
                      // Accepted: the job is booked in at once (work order
                      // awaiting the car) and the total is settled at the
                      // counter — "Paid · cash · RCP-…" once staff recorded it.
                      if (quoteWorkOrderLabel(q) case final workOrder?) ...[
                        const SizedBox(height: 10),
                        KeyValueTile(
                          key: const ValueKey('quote-work-order'),
                          label: 'Work order',
                          value: workOrder,
                          helper: q.workOrder?.awaitingCheckIn ?? false
                              ? 'Bring the car to ${shortOutletName(q.outletName)} — the repair starts once it is checked in.'
                              : 'Track progress under Bookings.',
                        ),
                      ],
                      if (q.paymentLabel case final payment?) ...[
                        const SizedBox(height: 10),
                        KeyValueTile(
                          key: const ValueKey('quote-payment'),
                          label: 'Payment',
                          value: payment,
                          warning: !q.isPaid,
                          helper: q.isPaid
                              ? 'Receipt issued at the counter.'
                              : 'Cash or card at the counter when you drop off or collect the car.',
                        ),
                      ],
                      if (q.pdfUrl != null || q.status != QuotationStatus.requested) ...[
                        const SizedBox(height: 16),
                        PillButton(
                          key: const ValueKey('quote-download-pdf'),
                          label: 'Download PDF',
                          icon: Symbols.picture_as_pdf_rounded,
                          variant: PillButtonVariant.outlined,
                          expand: true,
                          minHeight: 52,
                          onPressed: () => QuotePdf.download(context, q),
                        ),
                      ],
                      if (canDecide) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                key: const ValueKey('quote-decline'),
                                label: 'Decline',
                                variant: PillButtonVariant.outlinedError,
                                expand: true,
                                minHeight: 54,
                                onPressed: _busy
                                    ? null
                                    : () => _decide(q, accept: false),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: PillButton(
                                key: const ValueKey('quote-accept'),
                                label:
                                    'Accept ${Money.formatZarCompact(q.amountCents ?? q.itemsTotalCents)}',
                                expand: true,
                                minHeight: 54,
                                loading: _busy,
                                onPressed: _busy
                                    ? null
                                    : () => _decide(q, accept: true),
                              ),
                            ),
                          ],
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

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(SparklingShapes.tile),
    ),
    child: child,
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final LineItem item;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.category != null) ...[
                      CategoryChip(category: item.category!),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        item.quantity == 1
                            ? item.label
                            : '${item.label} × ${item.quantity}',
                        style: SparklingTypography.bodyLarge.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.description != null &&
                    item.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description!,
                    style: SparklingTypography.bodyMedium.copyWith(
                      fontSize: 13.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            Money.formatZar(item.totalCents),
            style: SparklingTypography.bodyLarge.copyWith(
              fontSize: 15.5,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Locked state after the one-time decision.
class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({required this.quotation});
  final Quotation quotation;

  @override
  Widget build(BuildContext context) {
    final q = quotation;
    final declined = q.status == QuotationStatus.declined;
    final verb = declined ? 'Declined' : 'Accepted';
    final when = q.decidedAt == null
        ? ''
        : ' on ${SparklingDates.dayMonth(q.decidedAt!)}';
    final how = switch (q.decisionSource) {
      QuoteDecisionSource.publicLink => ' via link',
      QuoteDecisionSource.staff => ' at the counter',
      _ => ' in app',
    };
    return InfoBanner(
      key: const ValueKey('quote-decided-banner'),
      tone: declined ? InfoTone.error : InfoTone.success,
      icon: declined ? Symbols.cancel_rounded : Symbols.task_alt_rounded,
      title: '$verb$when$how',
      text: declined
          ? 'This quote is closed. Request a new one if anything changes.'
          : q.status == QuotationStatus.converted
          ? 'Work order ${q.workOrderRef ?? ''} created — track progress under Bookings.'
                .replaceFirst('order  ', 'order ')
          : q.workOrder?.awaitingCheckIn ?? false
          ? 'Booked in as ${q.workOrder!.ref} — ${shortOutletName(q.outletName)} is expecting your car. Decisions are final.'
          : '${shortOutletName(q.outletName)} will schedule the repair and confirm on WhatsApp. Decisions are final.',
    );
  }
}

/// Accept confirmation sheet.
class _DecisionSheet extends StatelessWidget {
  const _DecisionSheet({required this.quotation, required this.accept});
  final Quotation quotation;
  final bool accept;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final q = quotation;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Accept this quote?'),
            Text(
              '${Money.formatZar(q.amountCents ?? q.itemsTotalCents)} for ${q.items.length} item${q.items.length == 1 ? '' : 's'} at ${shortOutletName(q.outletName)}. '
              'They will schedule the work and contact you on WhatsApp.',
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            const InfoBanner(
              tone: InfoTone.info,
              icon: Symbols.lock_rounded,
              text:
                  'You can answer once — accepting locks the quote for both of us.',
            ),
            const SizedBox(height: 16),
            PillButton(
              key: const ValueKey('quote-accept-confirm'),
              label: 'Yes, accept',
              icon: Symbols.check_rounded,
              expand: true,
              minHeight: 54,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Not yet',
              variant: PillButtonVariant.outlined,
              expand: true,
              minHeight: 50,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decline sheet with an optional note. Pops with the note (may be empty)
/// or null when cancelled.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet({required this.quotation});
  final Quotation quotation;

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Decline this quote?'),
            Text(
              'Let ${shortOutletName(widget.quotation.outletName)} know why (optional). Declining is final.',
              style: SparklingTypography.bodyLarge.copyWith(
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('quote-decline-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              maxLength: 240,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Going with another quote',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            PillButton(
              key: const ValueKey('quote-decline-confirm'),
              label: 'Decline quote',
              variant: PillButtonVariant.outlinedError,
              expand: true,
              minHeight: 54,
              onPressed: () => Navigator.of(context).pop(_note.text),
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Keep it open',
              variant: PillButtonVariant.outlined,
              expand: true,
              minHeight: 50,
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        ),
      ),
    );
  }
}
