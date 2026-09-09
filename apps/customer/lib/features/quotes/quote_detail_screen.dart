import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';

/// Quotation detail with accept / decline for `quoted` status (CUS-033).
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  Future<Quotation>? _future;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context.repos.customer.quotation(widget.quotationId);
  }

  void _reload() {
    setState(
      () => _future = context.repos.customer.quotation(widget.quotationId),
    );
  }

  Future<void> _decide(Quotation q, {required bool accept}) async {
    String? note;
    if (!accept) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline quote?'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      note = controller.text.trim().isEmpty ? null : controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Accept quote?'),
          content: Text(
            'Accept ${Money.formatZar(q.amountCents ?? 0)} for ${q.category.toLowerCase()} repair. ${shortOutletName(q.outletName)} will schedule the work and contact you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );
      if (ok != true) return;
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
      setState(() => _future = Future.value(updated));
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
            final rowStyle = SparklingTypography.bodyLarge.copyWith(
              fontSize: 15,
              color: cs.onSurfaceVariant,
            );
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
                    label: q.status.label,
                    tone: quotationTone(q.status),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      if (q.status.awaitingDecision)
                        InfoBanner(
                          tone: InfoTone.warning,
                          icon: Symbols.schedule_rounded,
                          title: 'Your decision is needed',
                          text: q.validUntil == null
                              ? 'Accept or decline — nothing is booked until you approve.'
                              : 'Valid until ${SparklingDates.dayMonth(q.validUntil!)}. Nothing is booked until you approve.',
                        ),
                      if (q.status == QuotationStatus.requested ||
                          q.status == QuotationStatus.assessing)
                        const InfoBanner(
                          tone: InfoTone.info,
                          icon: Symbols.schedule_rounded,
                          text: 'An estimator is reviewing your request and will reply within 24 h.',
                        ),
                      const SizedBox(height: 14),
                      KeyValueTile(
                        label: 'Outlet',
                        value: q.outletName ?? '—',
                        helper: q.assessorName == null
                            ? null
                            : 'Assessor ${q.assessorName}',
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(
                            SparklingShapes.tile,
                          ),
                        ),
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
                      if (q.amountCents != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(
                              SparklingShapes.tile,
                            ),
                          ),
                          child: Column(
                            children: [
                              for (final li in q.lineItems) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        li.quantity == 1
                                            ? li.label
                                            : '${li.label} × ${li.quantity}',
                                        style: rowStyle,
                                      ),
                                    ),
                                    Text(
                                      Money.formatZar(li.amountCents),
                                      style: rowStyle,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                              ],
                              const SizedBox(height: 4),
                              const DashedDivider(),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Quoted total',
                                      style: SparklingTypography.titleMedium
                                          .copyWith(color: cs.onSurface),
                                    ),
                                  ),
                                  Text(
                                    Money.formatZar(q.amountCents!),
                                    style: SparklingTypography.headlineSmall
                                        .copyWith(color: cs.primary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (q.attachments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const SectionHeader(title: 'Photos'),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final a in q.attachments) ...[
                                PhotoPlaceholder(
                                  caption: a.mimeType.split('/').last,
                                  child: a.downloadUrl == null
                                      ? null
                                      : Image.network(
                                          a.downloadUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                ),
                                const SizedBox(width: 12),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (q.decisionNote != null) ...[
                        const SizedBox(height: 10),
                        KeyValueTile(
                          label: 'Your note',
                          value: q.decisionNote!,
                        ),
                      ],
                      if (q.status == QuotationStatus.accepted ||
                          q.status == QuotationStatus.converted) ...[
                        const SizedBox(height: 14),
                        InfoBanner(
                          tone: InfoTone.success,
                          text: q.status == QuotationStatus.converted
                              ? 'Work order created — track progress under Bookings.'
                              : 'Accepted. ${shortOutletName(q.outletName)} will schedule the repair and confirm on WhatsApp.',
                        ),
                      ],
                      if (q.status.awaitingDecision) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
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
                                label:
                                    'Accept ${Money.formatZarCompact(q.amountCents ?? 0)}',
                                expand: true,
                                minHeight: 54,
                                loading: _busy,
                                onPressed: () => _decide(q, accept: true),
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
