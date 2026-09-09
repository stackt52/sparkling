import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// Quotation list (requested → quoted → accepted / declined …).
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  Stream<List<Quotation>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= context.repos.customer.watchQuotations();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Repair quotes',
              subtitle: 'Body & paint estimates',
              trailing: IconTileButton(
                icon: Symbols.add_rounded,
                tone: IconTileTone.primary,
                tooltip: 'Request quote',
                onPressed: () => context.push(Routes.quoteNew),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Quotation>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorView(
                      error: snap.error,
                      onRetry: () => setState(
                        () =>
                            _stream = context.repos.customer.watchQuotations(),
                      ),
                    );
                  }
                  final list = snap.data;
                  if (list == null) return const LoadingView();
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Symbols.request_quote_rounded,
                      title: 'No quotes yet',
                      message: 'Send photos of the damage and an estimator will reply within 24 h.',
                      actionLabel: 'Request quote',
                      onAction: () => context.push(Routes.quoteNew),
                    );
                  }
                  final sorted = [...list]
                    ..sort(
                      (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0))
                          .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0)),
                    );
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final q = sorted[i];
                      return ListTileCard(
                        onTap: () => context.push(Routes.quote(q.id)),
                        borderColor: q.status.awaitingDecision
                            ? context.sparkling.gold
                            : null,
                        leading: TintedIconTile(
                          icon: Symbols.car_crash_rounded,
                          size: 48,
                          background: cs.secondaryContainer,
                          foreground: cs.onSecondaryContainer,
                        ),
                        title: Text('${q.category} · ${q.vehicleLabel ?? ''}'),
                        subtitle: Text(
                          [
                            q.ref,
                            if (q.amountCents != null)
                              Money.formatZar(q.amountCents!),
                            if (q.outletName != null)
                              shortOutletName(q.outletName),
                          ].join(' · '),
                        ),
                        trailing: StatusChip(
                          label: q.status.label,
                          tone: quotationTone(q.status),
                          dense: true,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
