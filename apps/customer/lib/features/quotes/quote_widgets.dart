import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';

/// "Booked in · WO-2026-4819 awaiting your car" while the accepted quote's
/// work order waits for the check-in, "WO-2026-4819 · checked in" (or the
/// work status) once the car is on site. Null before acceptance.
String? quoteWorkOrderLabel(Quotation q) {
  final wo = q.workOrder;
  final ref = wo?.ref ?? q.workOrderRef;
  if (ref == null) return null;
  if (wo == null) return 'Booked in · $ref';
  if (wo.awaitingCheckIn) return 'Booked in · $ref awaiting your car';
  if (wo.status == WorkStatus.queued || wo.status == WorkStatus.assigned) {
    return '$ref · checked in';
  }
  return '$ref · ${wo.status.label.toLowerCase()}';
}

/// Glyph for an attention category.
IconData categoryIcon(String? category) => switch (category) {
  'Dent' => Symbols.compress_rounded,
  'Scratch' => Symbols.gesture_rounded,
  'Bumper' => Symbols.car_crash_rounded,
  'Panel' => Symbols.view_agenda_rounded,
  'Paint' => Symbols.format_paint_rounded,
  'Glass' => Symbols.window_rounded,
  _ => Symbols.build_rounded,
};

/// Small tonal category chip ("Dent", "Scratch" …).
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category});
  final String category;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: category,
    icon: categoryIcon(category),
    tone: StatusChipTone.primary,
    dense: true,
  );
}

/// Loads an attachment with the bearer token through
/// `CustomerRepository.photoBytes` (demo `demo://` photos come from memory)
/// and renders it; striped placeholder while loading.
class AuthedImage extends StatefulWidget {
  const AuthedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  static final Map<String, Uint8List> _cache = {};

  @override
  State<AuthedImage> createState() => _AuthedImageState();
}

class _AuthedImageState extends State<AuthedImage> {
  Future<Uint8List>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _load();
  }

  @override
  void didUpdateWidget(covariant AuthedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _bytes = _load();
  }

  Future<Uint8List> _load() async {
    final cached = AuthedImage._cache[widget.url];
    if (cached != null) return cached;
    final bytes = await context.repos.customer.photoBytes(widget.url);
    AuthedImage._cache[widget.url] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    Widget broken() => Container(
      width: widget.width,
      height: widget.height,
      color: cs.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Symbols.broken_image_rounded, color: cs.onSurfaceVariant),
    );
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return broken();
        final data = snap.data;
        if (data == null) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const PhotoPlaceholder(radius: 0),
          );
        }
        return Image.memory(
          data,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => broken(),
        );
      },
    );
  }
}

/// Photo tile with caption overlay; tap → full-screen viewer.
class QuotePhotoTile extends StatelessWidget {
  const QuotePhotoTile({super.key, required this.attachment, this.size = 96});
  final Attachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = attachment.imageUrl;
    return PhotoPlaceholder(
      size: size,
      caption: url == null ? attachment.caption ?? 'Photo' : null,
      onTap: url == null ? null : () => _open(context),
      child: url == null
          ? null
          : Stack(
              fit: StackFit.expand,
              children: [
                AuthedImage(url: url, width: size, height: size),
                if (attachment.caption != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Text(
                        attachment.caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SparklingTypography.labelMedium.copyWith(
                          color: Colors.white,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _open(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Symbols.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Center(
                    child: AuthedImage(
                      url: attachment.imageUrl!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              if (attachment.caption != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    attachment.caption!,
                    textAlign: TextAlign.center,
                    style: SparklingTypography.bodyLarge.copyWith(
                      color: Colors.white,
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

/// "Valid until 26 Sep · expires in 14 days" / "Expired 2 days ago".
String validityLabel(Quotation q) {
  final v = q.validUntil;
  if (v == null) return 'No expiry';
  final days = q.daysLeft ?? 0;
  final date = SparklingDates.dayMonth(v);
  if (days < 0) {
    final ago = -days;
    return 'Expired ${ago == 1 ? 'yesterday' : '$ago days ago'}';
  }
  if (days == 0) return 'Expires today ($date)';
  return 'Valid until $date · expires in $days day${days == 1 ? '' : 's'}';
}

/// "Expires in 14 days" / "Expires today" / "Expired 2 days ago".
String expiryHelper(Quotation q) {
  final days = q.daysLeft;
  if (days == null) return 'No expiry';
  if (days < 0) return 'Expired ${-days == 1 ? 'yesterday' : '${-days} days ago'}';
  if (days == 0) return 'Expires today';
  return 'Expires in $days day${days == 1 ? '' : 's'}';
}

/// PDF download → temp file → share sheet (`GET /quotations/:id/pdf`).
abstract final class QuotePdf {
  /// Test hook: replaces the platform share sheet.
  static Future<void> Function(ShareParams params)? shareOverride;

  static Future<void> download(BuildContext context, Quotation q) async {
    try {
      final bytes = await context.repos.customer.quotationPdf(q.id);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${q.ref}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      final params = ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Sparkling quote ${q.ref}',
        text: 'Quote ${q.ref}',
      );
      final o = shareOverride;
      if (o != null) {
        await o(params);
      } else {
        await SharePlus.instance.share(params);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, describeError(e));
    }
  }
}
