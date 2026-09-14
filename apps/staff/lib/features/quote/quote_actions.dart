import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../widgets/feedback.dart';

/// Public-link and PDF actions shared by the confirmation and detail screens.
abstract final class QuoteActions {
  /// Test hook: replaces the platform share sheet.
  static Future<void> Function(ShareParams params)? shareOverride;

  static Future<void> _share(ShareParams params) async {
    final o = shareOverride;
    if (o != null) return o(params);
    await SharePlus.instance.share(params);
  }

  static Future<void> copyLink(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    StaffHaptics.tap(context);
    StaffSnack.show(context, 'Link copied');
  }

  static Future<void> shareLink(
    BuildContext context,
    Quotation q,
    String url,
  ) async {
    try {
      await _share(
        ShareParams(
          text:
              'Sparkling quote ${q.ref}${q.amountCents == null ? '' : ' · ${Money.formatZar(q.amountCents!)}'}: $url',
          subject: 'Sparkling quote ${q.ref}',
        ),
      );
    } catch (e) {
      if (context.mounted) StaffSnack.error(context, e);
    }
  }

  /// `GET /quotations/:id/pdf` → temp file → share sheet.
  static Future<void> downloadPdf(BuildContext context, Quotation q) async {
    try {
      final bytes = await context.repositories.staff.quotationPdf(q.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${q.ref}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await _share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Sparkling quote ${q.ref}',
          text: 'Quote ${q.ref}',
        ),
      );
    } catch (e) {
      if (context.mounted) StaffSnack.error(context, e);
    }
  }
}

/// "Resend WhatsApp" with the 60 s cooldown (`POST /quotations/:id/share`).
class ResendLinkButton extends StatefulWidget {
  const ResendLinkButton({
    super.key,
    required this.quotation,
    this.onShared,
    this.variant = PillButtonVariant.tonal,
    this.expand = true,
    this.minHeight = 52,
  });

  final Quotation quotation;
  final ValueChanged<SharedQuoteLink>? onShared;
  final PillButtonVariant variant;
  final bool expand;
  final double minHeight;

  @override
  State<ResendLinkButton> createState() => _ResendLinkButtonState();
}

class _ResendLinkButtonState extends State<ResendLinkButton> {
  static const cooldown = Duration(seconds: 60);
  bool _busy = false;
  DateTime? _sentAt;
  int _left = 0;

  void _tick() {
    if (!mounted) return;
    final at = _sentAt;
    if (at == null) return;
    final left = cooldown.inSeconds - DateTime.now().difference(at).inSeconds;
    setState(() => _left = left < 0 ? 0 : left);
    if (_left > 0) Future.delayed(const Duration(seconds: 1), _tick);
  }

  Future<void> _resend() async {
    if (_busy || _left > 0) return;
    setState(() => _busy = true);
    try {
      final link = await context.repositories.staff.shareQuotation(
        widget.quotation.id,
      );
      if (!mounted) return;
      StaffHaptics.success(context);
      _sentAt = DateTime.now();
      _tick();
      StaffSnack.show(context, 'Quote re-sent on WhatsApp and push');
      widget.onShared?.call(link);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isRateLimited) {
        final retry = (e.data?['retry_after_seconds'] as num?)?.toInt() ?? 60;
        _sentAt = DateTime.now().subtract(cooldown - Duration(seconds: retry));
        _tick();
      }
      StaffSnack.error(context, e);
    } catch (e) {
      if (mounted) StaffSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PillButton(
    key: const ValueKey('quote-resend'),
    label: _left > 0 ? 'Resend in $_left s' : 'Resend WhatsApp',
    icon: Symbols.forward_to_inbox_rounded,
    variant: widget.variant,
    expand: widget.expand,
    minHeight: widget.minHeight,
    loading: _busy,
    onPressed: _busy || _left > 0 ? null : _resend,
  );
}

/// Public link card: url in mono + Copy link / Share.
class PublicLinkCard extends StatelessWidget {
  const PublicLinkCard({super.key, required this.quotation, required this.url});
  final Quotation quotation;
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(SparklingShapes.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.link_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Public quote page',
                  style: SparklingTypography.titleMedium.copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            url,
            key: const ValueKey('quote-public-url'),
            maxLines: 2,
            style: SparklingTypography.mono(
              fontSize: 12.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  key: const ValueKey('quote-copy-link'),
                  label: 'Copy link',
                  icon: Symbols.content_copy_rounded,
                  variant: PillButtonVariant.outlined,
                  expand: true,
                  minHeight: 48,
                  onPressed: () => QuoteActions.copyLink(context, url),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  key: const ValueKey('quote-share-link'),
                  label: 'Share',
                  icon: Symbols.share_rounded,
                  variant: PillButtonVariant.tonal,
                  expand: true,
                  minHeight: 48,
                  onPressed: () =>
                      QuoteActions.shareLink(context, quotation, url),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
