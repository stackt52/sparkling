import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'raise_quote_controller.dart';

/// Status chip tone for a quotation state.
StatusChipTone quotationTone(QuotationStatus status) => switch (status) {
  QuotationStatus.quoted => StatusChipTone.gold,
  QuotationStatus.accepted ||
  QuotationStatus.converted => StatusChipTone.success,
  QuotationStatus.declined || QuotationStatus.expired => StatusChipTone.error,
  QuotationStatus.assessing => StatusChipTone.primary,
  QuotationStatus.requested => StatusChipTone.neutral,
};

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
  const CategoryChip({super.key, required this.category, this.dense = true});
  final String category;
  final bool dense;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: category,
    icon: categoryIcon(category),
    tone: StatusChipTone.primary,
    dense: dense,
  );
}

/// Loads an attachment through the repository (bearer auth; `demo://`
/// photos from memory) and renders it, with the striped placeholder while
/// loading and a broken-image glyph on failure.
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

  /// Process-wide cache so grids and detail screens share bytes.
  static final Map<String, Uint8List> _cache = {};
  static void evict(String url) => _cache.remove(url);

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
    final bytes = await context.repositories.staff.photoBytes(widget.url);
    AuthedImage._cache[widget.url] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            width: widget.width,
            height: widget.height,
            color: cs.surfaceContainerHigh,
            alignment: Alignment.center,
            child: Icon(
              Symbols.broken_image_rounded,
              color: cs.onSurfaceVariant,
            ),
          );
        }
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
          errorBuilder: (_, _, _) => Container(
            width: widget.width,
            height: widget.height,
            color: cs.surfaceContainerHigh,
            alignment: Alignment.center,
            child: Icon(
              Symbols.broken_image_rounded,
              color: cs.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

/// 88px striped tile for a not-yet-uploaded draft photo (file or bytes).
class DraftPhotoTile extends StatelessWidget {
  const DraftPhotoTile({
    super.key,
    required this.photo,
    this.onTap,
    this.onRemove,
    this.size = 88,
  });

  final QuotePhotoDraft photo;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    Widget? image;
    if (photo.bytes != null) {
      image = Image.memory(
        photo.bytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else if (photo.path != null) {
      image = Image.file(
        File(photo.path!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhotoPlaceholder(
          size: size,
          caption: image == null ? photo.fileName : null,
          onTap: onTap,
          onRemove: onRemove,
          child: image == null
              ? null
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    if (photo.caption != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
                          color: Colors.black.withValues(alpha: 0.55),
                          child: Text(
                            photo.caption!,
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
        ),
        if (image == null && photo.caption != null)
          SizedBox(
            width: size,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                photo.caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SparklingTypography.labelMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Uploaded attachment tile (88px) rendered through [AuthedImage].
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    this.size = 88,
    this.onTap,
    this.onRemove,
  });

  final Attachment attachment;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final url = attachment.imageUrl;
    return PhotoPlaceholder(
      size: size,
      caption: url == null ? attachment.caption ?? 'Photo' : null,
      onTap: onTap,
      onRemove: onRemove,
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
}

/// Full-screen viewer for one attachment.
Future<void> showPhotoViewer(
  BuildContext context, {
  required Attachment attachment,
}) => showDialog<void>(
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
                  child: attachment.imageUrl == null
                      ? const PhotoPlaceholder(size: 240)
                      : AuthedImage(
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

/// Line-item row: label, optional description / service, amount.
class QuoteItemRow extends StatelessWidget {
  const QuoteItemRow({
    super.key,
    required this.label,
    required this.amountCents,
    this.category,
    this.description,
    this.serviceName,
    this.quantity = 1,
  });

  final String label;
  final int amountCents;
  final String? category;
  final String? description;
  final String? serviceName;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    // Skip the service name when it merely repeats the label.
    final service = serviceName;
    final meta = [
      if (service != null && service.toLowerCase() != label.toLowerCase())
        service,
      if (description != null && description!.trim().isNotEmpty) description!,
    ].join(' · ');
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
                    if (category != null) ...[
                      CategoryChip(category: category!),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        quantity == 1 ? label : '$label × $quantity',
                        style: SparklingTypography.bodyLarge.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
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
            Money.formatZar(amountCents * quantity),
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

/// "Total" row in 22px / 700 primary.
class QuoteTotalRow extends StatelessWidget {
  const QuoteTotalRow({super.key, required this.totalCents, this.label});
  final int totalCents;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label ?? 'Total',
            style: SparklingTypography.titleLarge.copyWith(
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
        ),
        Text(
          Money.formatZar(totalCents),
          style: SparklingTypography.headlineMedium.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

/// "Valid until 26 Sep · 14 days left" / "Expired 2 days ago".
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
  return 'Valid until $date · $days day${days == 1 ? '' : 's'} left';
}
