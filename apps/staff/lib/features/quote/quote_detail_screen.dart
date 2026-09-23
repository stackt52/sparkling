import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/feedback.dart';
import 'quote_actions.dart';
import 'quote_widgets.dart';

/// Staff quotation detail (`/quotes/:id`): items, damage photos (authed),
/// status timeline (raised → sent → decided with the decision source → work
/// order), work-order / payment chips ("WO-… · awaiting check-in",
/// "R x due" / "Paid · RCP-…"), public link actions, PDF and, for
/// supervisors / managers, "Confirm check-in" on the accepted quote's work
/// order (`POST /quotations/:id/convert` → `converted`).
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  Future<Quotation>? _future;
  StreamSubscription<List<Quotation>>? _sub;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.repositories.staff.quotation(widget.quotationId);
    _sub ??= context.repositories.staff
        .watchQuotations(outletId: context.session.outletId)
        .listen((list) {
          final q = list.where((q) => q.id == widget.quotationId).firstOrNull;
          if (q != null && mounted) {
            setState(() {
              _future = Future.value(q);
            });
          }
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    final f = context.repositories.staff.quotation(widget.quotationId);
    setState(() {
      _future = f;
    });
  }

  Future<void> _removePhoto(Quotation q, Attachment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        content: Text(a.caption ?? 'This photo is removed from the quote.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.repositories.staff.deleteQuotationPhoto(q.id, a.id);
      if (!mounted) return;
      if (a.imageUrl != null) AuthedImage.evict(a.imageUrl!);
      StaffSnack.show(context, 'Photo removed');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        await showConflictDialog(context, e, onRefresh: _reload);
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    }
    if (mounted) _reload();
  }

  Future<void> _convert(Quotation q) async {
    setState(() => _busy = true);
    try {
      final result = await runMutation(
        context,
        () => context.repositories.staff.convertQuotation(q.id),
        onConflict: _reload,
      );
      if (result != null && mounted) {
        StaffHaptics.success(context);
        StaffSnack.show(
          context,
          '${q.ref} converted — ${result.workOrderRef ?? 'work order'} checked in',
        );
        setState(() {
          _future = Future.value(result);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<Quotation>(
          future: _future,
          builder: (context, snap) => AsyncView<Quotation>(
            snapshot: snap,
            onRetry: _reload,
            builder: (context, q) {
              final url = q.publicUrl;
              final canConvert =
                  session.canSupervise && q.status == QuotationStatus.accepted;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        IconTileButton(
                          icon: Symbols.arrow_back_rounded,
                          tooltip: 'Back',
                          onPressed: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(Routes.tasks);
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                q.ref,
                                style: SparklingTypography.mono(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                [
                                  q.customerName,
                                  q.vehicleLabel,
                                ].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SparklingTypography.bodyLarge.copyWith(
                                  fontSize: 14.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        StatusChip(
                          label: q.isExpired ? 'Expired' : q.status.label,
                          tone: q.isExpired
                              ? StatusChipTone.error
                              : quotationTone(q.status),
                          dot: true,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        if (q.decisionLabel != null)
                          InfoBanner(
                            tone: q.status == QuotationStatus.declined
                                ? InfoTone.error
                                : InfoTone.success,
                            icon: q.status == QuotationStatus.declined
                                ? Symbols.cancel_rounded
                                : Symbols.task_alt_rounded,
                            title: q.decisionLabel,
                            text: [
                              if (q.decidedAt != null)
                                SparklingDates.long(q.decidedAt!),
                              if (q.decisionNote != null)
                                'Note: ${q.decisionNote}',
                            ].join(' · '),
                          )
                        else if (q.status == QuotationStatus.quoted)
                          InfoBanner(
                            tone: q.isExpired ? InfoTone.error : InfoTone.warning,
                            icon: Symbols.schedule_rounded,
                            title: q.isExpired
                                ? 'Expired — raise a new quote'
                                : 'Waiting for the customer',
                            text: validityLabel(q),
                          ),
                        if (q.workOrder != null ||
                            quotePaymentLabel(q) != null) ...[
                          const SizedBox(height: 10),
                          QuoteStateChips(quotation: q),
                        ],
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MetaRow(
                                icon: Symbols.person_rounded,
                                text: q.customerName ?? q.customerId,
                              ),
                              _MetaRow(
                                icon: Symbols.directions_car_rounded,
                                text: q.vehicleLabel ?? q.vehicleId,
                                mono: true,
                              ),
                              _MetaRow(
                                icon: Symbols.storefront_rounded,
                                text:
                                    '${q.outletName ?? 'Outlet'}${q.assessorName == null ? '' : ' · ${q.assessorName}'}',
                              ),
                              if (q.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  q.description,
                                  style: SparklingTypography.bodyMedium.copyWith(
                                    fontSize: 14.5,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final li in q.items)
                                QuoteItemRow(
                                  label: li.label,
                                  amountCents: li.amountCents,
                                  quantity: li.quantity,
                                  category: li.category,
                                  description: li.description,
                                ),
                              const SizedBox(height: 8),
                              const _Dashed(),
                              const SizedBox(height: 12),
                              QuoteTotalRow(
                                totalCents: q.amountCents ?? q.itemsTotalCents,
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
                        const SizedBox(height: 18),
                        SectionHeader(
                          title: 'Damage photos',
                          trailing: Text(
                            '${q.photos.length}',
                            style: SparklingTypography.bodyLarge.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (q.photos.isEmpty)
                          Text(
                            'No photos attached.',
                            style: SparklingTypography.bodyMedium.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final a in q.photos)
                                AttachmentTile(
                                  key: ValueKey('quote-attachment-${a.id}'),
                                  attachment: a,
                                  size: 96,
                                  onTap: () =>
                                      showPhotoViewer(context, attachment: a),
                                  onRemove: q.isDecided
                                      ? null
                                      : () => _removePhoto(q, a),
                                ),
                            ],
                          ),
                        const SizedBox(height: 18),
                        const SectionHeader(title: 'Status'),
                        _Timeline(quotation: q),
                        if (url != null) ...[
                          const SizedBox(height: 10),
                          PublicLinkCard(quotation: q, url: url),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ResendLinkButton(
                                  quotation: q,
                                  onShared: (_) => _reload(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PillButton(
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
                        ] else ...[
                          const SizedBox(height: 10),
                          PillButton(
                            label: 'Download PDF',
                            icon: Symbols.picture_as_pdf_rounded,
                            variant: PillButtonVariant.outlined,
                            expand: true,
                            minHeight: 52,
                            onPressed: () => QuoteActions.downloadPdf(context, q),
                          ),
                        ],
                        if (canConvert) ...[
                          const SizedBox(height: 16),
                          PillButton(
                            key: const ValueKey('quote-convert'),
                            label: q.workOrder != null
                                ? 'Confirm check-in · ${q.workOrder!.ref}'
                                : 'Convert to work order',
                            icon: q.workOrder != null
                                ? Symbols.login_rounded
                                : Symbols.build_rounded,
                            variant: PillButtonVariant.navy,
                            expand: true,
                            minHeight: 54,
                            loading: _busy,
                            onPressed: _busy ? null : () => _convert(q),
                          ),
                        ],
                        if (q.status == QuotationStatus.converted)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: PillButton(
                              label: 'Open tasks',
                              icon: Symbols.checklist_rounded,
                              variant: PillButtonVariant.tonal,
                              expand: true,
                              minHeight: 52,
                              onPressed: () => context.go(Routes.tasks),
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
      borderRadius: BorderRadius.circular(SparklingShapes.card),
    ),
    child: child,
  );
}

class _Dashed extends StatelessWidget {
  const _Dashed();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Row(
      children: List.generate(
        (c.maxWidth / 10).floor(),
        (_) => Container(
          width: 6,
          height: 1,
          margin: const EdgeInsets.only(right: 4),
          color: context.colors.outline,
        ),
      ),
    ),
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text, this.mono = false});
  final IconData icon;
  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? SparklingTypography.mono(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: cs.onSurface,
                    )
                  : SparklingTypography.bodyLarge.copyWith(
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Raised → Sent → Decided (with the decision source) → Work order.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.quotation});
  final Quotation quotation;

  @override
  Widget build(BuildContext context) {
    final q = quotation;
    final decided = q.isDecided;
    final converted = q.status == QuotationStatus.converted;
    final rows = <(String, String?, TimelineState, IconData?)>[
      (
        'Raised',
        [
          if (q.quotedAt != null) SparklingDates.long(q.quotedAt!),
          if (q.assessorName != null) 'by ${q.assessorName}',
        ].join(' · '),
        TimelineState.done,
        null,
      ),
      (
        'Sent to customer',
        q.publicUrl == null
            ? 'Public link not shared yet'
            : 'Push + WhatsApp with the public link',
        TimelineState.done,
        Symbols.send_rounded,
      ),
      (
        decided
            ? q.decisionLabel ?? 'Decided'
            : q.isExpired
            ? 'Expired'
            : 'Awaiting decision',
        decided
            ? (q.decidedAt == null ? null : SparklingDates.long(q.decidedAt!))
            : validityLabel(q),
        decided
            ? TimelineState.done
            : q.isExpired
            ? TimelineState.pending
            : TimelineState.current,
        decided
            ? (q.status == QuotationStatus.declined
                  ? Symbols.close_rounded
                  : Symbols.check_rounded)
            : null,
      ),
      (
        'Work order',
        [
          quoteWorkOrderLabel(q) ??
              (converted
                  ? 'Created from this quote'
                  : q.status == QuotationStatus.accepted
                  ? 'Convert to schedule the repair'
                  : 'Created on acceptance, then awaiting check-in'),
          if (q.workOrder?.awaitingCheckIn ?? false)
            'confirm the check-in when the car arrives',
          ?quotePaymentLabel(q),
        ].join(' · '),
        converted || (q.workOrder?.isCheckedIn ?? false)
            ? TimelineState.done
            : q.status == QuotationStatus.accepted
            ? TimelineState.current
            : TimelineState.pending,
        Symbols.build_rounded,
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          TimelineTile(
            title: rows[i].$1,
            subtitle: rows[i].$2,
            state: rows[i].$3,
            icon: rows[i].$4,
            isFirst: i == 0,
            isLast: i == rows.length - 1,
            indicatorSize: 34,
          ),
      ],
    );
  }
}
