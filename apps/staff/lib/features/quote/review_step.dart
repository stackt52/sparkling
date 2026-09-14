import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/feedback.dart';
import '../../widgets/live_sync_chip.dart';
import '../walk_in/walk_in_widgets.dart';
import 'quote_widgets.dart';
import 'raise_quote_controller.dart';

/// Step 4 of 4 — review & send: summary card (customer, vehicle, outlet,
/// items table, total, valid until), photo thumbnails, "Send to customer
/// now" switch and the CTA: `POST /quotations` → sequential photo uploads
/// (`POST /quotations/:id/photos`, failures skipped with a warning) →
/// confirmation.
class ReviewStep extends StatefulWidget {
  const ReviewStep({super.key, required this.flow, required this.onBack});

  final RaiseQuoteController flow;
  final VoidCallback onBack;

  @override
  State<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<ReviewStep> {
  bool _busy = false;
  String? _stage;
  double? _progress;
  Future<Outlet?>? _outlet;

  RaiseQuoteController get _flow => widget.flow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outlet ??= context.repositories.catalogue.outlet(context.session.outletId);
  }

  Future<Uint8List?> _bytesOf(QuotePhotoDraft p) async {
    if (p.bytes != null) return p.bytes;
    if (p.path != null) {
      try {
        return await File(p.path!).readAsBytes();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final flow = _flow;
    if (!flow.canReview || _busy) return;
    final staff = context.repositories.staff;
    final outletId = context.session.outletId;
    setState(() {
      _busy = true;
      _stage = 'Raising quote…';
      _progress = null;
    });
    try {
      final quotation = await staff.raiseQuotation(
        flow.toInput(outletId: outletId),
        deferredPhotos: flow.deferredPhotos,
      );
      if (!mounted) return;
      var uploaded = 0;
      var failed = 0;
      var deferred = 0;
      final photos = flow.photos;
      if (quotation.pendingSync) {
        deferred = flow.deferredPhotos.length;
        failed = photos.length - deferred;
      } else {
        for (var i = 0; i < photos.length; i++) {
          setState(() {
            _stage = 'Uploading photo ${i + 1} of ${photos.length}…';
            _progress = photos.isEmpty ? null : i / photos.length;
          });
          final p = photos[i];
          final bytes = await _bytesOf(p);
          if (bytes == null) {
            failed++;
            continue;
          }
          try {
            await staff.uploadQuotationPhoto(
              quotation.id,
              bytes,
              caption: p.caption,
              mimeType: p.mimeType,
              filename: p.fileName,
            );
            uploaded++;
          } on ApiException {
            failed++;
          } catch (_) {
            failed++;
          }
          if (!mounted) return;
        }
      }
      if (!mounted) return;
      final outcome = RaiseQuoteOutcome(
        quotation: quotation,
        customer: flow.customer,
        uploaded: uploaded,
        failedUploads: failed,
        deferredPhotos: deferred,
        sentToCustomer: flow.sendToCustomer,
      );
      StaffHaptics.success(context);
      flow.reset();
      context.go(Routes.quoteConfirmation(quotation.id), extra: outcome);
    } on ApiException catch (e) {
      if (!mounted) return;
      StaffHaptics.error(context);
      if (e.isConflict) {
        flow.rotateOpId();
        await showConflictDialog(context, e);
      } else if (e.isValidation) {
        flow.rotateOpId();
        StaffSnack.error(context, e);
      } else {
        StaffSnack.error(context, e);
      }
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
          _progress = null;
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
      builder: (context, _) {
        if (!flow.canReview) {
          return Column(
            children: [
              BookingStepHeader(
                title: 'Raise quote',
                step: 4,
                subtitle: 'Review & send',
                onBack: widget.onBack,
              ),
              Expanded(
                child: Center(
                  child: PillButton(
                    label: 'Finish the earlier steps',
                    variant: PillButtonVariant.tonal,
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            ],
          );
        }
        final offline = !context.syncStatus.online;
        final customer = flow.customer!;
        return Column(
          children: [
            BookingStepHeader(
              title: 'Raise quote',
              step: 4,
              subtitle: 'Review & send',
              onBack: _busy ? null : widget.onBack,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                children: [
                  const LiveOfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                  FutureBuilder<Outlet?>(
                    future: _outlet,
                    builder: (context, snap) =>
                        _SummaryCard(flow: flow, outlet: snap.data),
                  ),
                  if (flow.photos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: 'Damage photos',
                      trailing: Text(
                        '${flow.photos.length}',
                        style: SparklingTypography.bodyLarge.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in flow.photos) ...[
                            DraftPhotoTile(photo: p, size: 72),
                            const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'Sending'),
                  ListTileCard(
                    key: const ValueKey('quote-send-switch'),
                    onTap: _busy
                        ? null
                        : () => flow.setSendToCustomer(!flow.sendToCustomer),
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                    leading: Icon(
                      Symbols.send_rounded,
                      color: cs.primary,
                      fill: 1,
                    ),
                    title: const Text('Send to customer now'),
                    subtitle: Text(
                      flow.sendToCustomer
                          ? 'Push + WhatsApp with the public link to ${customer.firstName}${customer.phone == null ? '' : ' (${customer.phone})'}'
                          : 'Kept for later — share the link from the quote screen',
                      maxLines: 2,
                    ),
                    trailing: Switch(
                      value: flow.sendToCustomer,
                      onChanged: _busy ? null : flow.setSendToCustomer,
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
                          offline
                              ? 'You are offline: the quote is queued under your name; photos upload once it syncs.'
                              : 'The quote is raised under your name and audited. The customer accepts or declines once — in the app or on the public page.',
                          style: SparklingTypography.bodyMedium.copyWith(
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
            BottomActionBar(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_stage != null) ...[
                    Text(
                      _stage!,
                      textAlign: TextAlign.center,
                      style: SparklingTypography.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  PillButton(
                    key: const ValueKey('quote-raise-cta'),
                    label: 'Raise quote · ${compactZar(flow.totalCents)}',
                    icon: Symbols.request_quote_rounded,
                    expand: true,
                    minHeight: 56,
                    loading: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.flow, required this.outlet});
  final RaiseQuoteController flow;
  final Outlet? outlet;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final customer = flow.customer!;
    final vehicle = flow.vehicle!;
    final metaStyle = SparklingTypography.bodyMedium.copyWith(
      fontSize: 14.5,
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
              const TintedIconTile(icon: Symbols.request_quote_rounded, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SparklingTypography.titleLarge.copyWith(
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          vehicle.registrationNo,
                          style: SparklingTypography.mono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: cs.onSurface,
                          ),
                        ),
                        if (vehicle.displayName.isNotEmpty)
                          Flexible(
                            child: Text(
                              ' · ${vehicle.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metaStyle,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      outlet?.name ?? 'Your outlet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 6),
          for (final item in flow.items)
            QuoteItemRow(
              label: item.label,
              amountCents: item.amountCents,
              category: item.category,
              description: item.description,
              serviceName: item.serviceName,
            ),
          const SizedBox(height: 10),
          const DashedDivider(),
          const SizedBox(height: 12),
          QuoteTotalRow(totalCents: flow.totalCents),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Symbols.event_available_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valid until ${SparklingDates.dayMonth(flow.validUntil)} · ${flow.validityDays} days',
                  style: metaStyle,
                ),
              ),
            ],
          ),
          if (flow.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              flow.description.trim(),
              style: SparklingTypography.bodyMedium.copyWith(
                fontSize: 14.5,
                color: cs.onSurface,
              ),
            ),
          ],
          if (flow.itemsNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.sticky_note_2_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(flow.itemsNote.trim(), style: metaStyle)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
