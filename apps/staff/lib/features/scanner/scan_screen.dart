import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/feedback.dart';
import 'scan_review_screen.dart';

/// PDF417 licence-disc scanner (STF-010..013, BAR-*): `mobile_scanner`
/// restricted to `BarcodeFormat.pdf417`, azure viewfinder overlay, torch,
/// on-device parsing, one result per scan session, retry / manual entry.
///
/// Camera analysis runs at 1920×1080 on Android with a `scanWindow` matching
/// the viewfinder; "Import photo" decodes a gallery image through
/// [MobileScannerController.analyzeImage] and reuses the parse → review flow
/// (unreadable photos get the BAR-006 failure sheet). See `docs/PDF417.md`.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Android: full-HD analysis stream so the disc is sampled at ≥ 3 px per
    // PDF417 module. Ignored on iOS.
    cameraResolution: const Size(1920, 1080),
    autoStart: true,
  );
  final ScanDebouncer _debouncer = ScanDebouncer();
  final ImagePicker _picker = ImagePicker();
  String? _error;
  bool _success = false;
  bool _cameraFailed = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraFailed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // While the photo picker is up we own the camera lifecycle.
        if (!_importing) unawaited(_controller.start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_success || _importing) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (barcode.format != BarcodeFormat.pdf417 &&
          barcode.format != BarcodeFormat.unknown) {
        continue;
      }
      if (_debouncer.isDuplicate(raw) || _debouncer.hasResult) continue;
      _handleRaw(raw);
      return;
    }
  }

  void _handleRaw(String raw) {
    try {
      final result = Pdf417DiscParser.parse(raw);
      _debouncer.accept(raw);
      _accept(result, manual: false);
    } on DiscParseException catch (e) {
      _debouncer.accept(raw); // one message per payload until retry
      setState(() => _error = e.message);
      StaffHaptics.error(context);
    }
  }

  Future<void> _accept(DiscScanResult result, {required bool manual}) async {
    setState(() {
      _success = true;
      _error = null;
    });
    StaffHaptics.success(context);
    // Green flash, then container-transform to the review screen.
    await Future<void>.delayed(
      SparklingMotion.durationFor(context, SparklingMotion.medium),
    );
    if (!mounted) return;
    unawaited(_controller.stop());
    await context.push(
      Routes.scanReview,
      extra: ScanReviewArgs(result: result, manual: manual),
    );
    if (!mounted) return;
    _retry();
  }

  void _retry() {
    _debouncer.reset();
    setState(() {
      _success = false;
      _error = null;
      _cameraFailed = false;
    });
    unawaited(_controller.start());
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final reg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter registration'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: SparklingTypography.mono(fontSize: 20, letterSpacing: 2),
          decoration: const InputDecoration(hintText: 'KL 45 MN GP'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleaned = (reg ?? '').toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9 ]'),
      '',
    );
    if (cleaned.trim().length < 2 || !mounted) return;
    unawaited(
      _accept(
        DiscScanResult(
          registrationNo: cleaned.trim(),
          rawHash: Pdf417DiscParser.hash('manual:$cleaned'),
        ),
        manual: true,
      ),
    );
  }

  void _useSample() => _handleRaw(Pdf417DiscParser.sampleDiscPayload());

  /// "Import photo": pick a gallery image, decode it on-device with the same
  /// PDF417-only decoder, then hand a valid payload to [_handleRaw].
  Future<void> _importPhoto() async {
    if (_importing || _success) return;
    _importing = true;
    // Release the camera while the picker is presented; the lifecycle
    // observer skips its auto-restart while [_importing] is set.
    await _controller.stop();
    XFile? file;
    String? failure;
    try {
      file = await _picker.pickImage(source: ImageSource.gallery);
    } catch (_) {
      failure = 'Could not open the photo library. Check permissions.';
    }
    if (!mounted) return;
    if (file == null && failure == null) {
      _importing = false;
      if (!_cameraFailed) unawaited(_controller.start());
      return;
    }

    String? raw;
    if (file != null) {
      try {
        final capture = await _controller.analyzeImage(
          file.path,
          formats: const [BarcodeFormat.pdf417],
        );
        for (final code in capture?.barcodes ?? const <Barcode>[]) {
          final value = code.rawValue ?? code.displayValue;
          if (value != null && value.isNotEmpty) {
            raw = value;
            break;
          }
        }
      } on UnsupportedError {
        failure = 'Importing photos is not supported on this device.';
      } on MobileScannerBarcodeException catch (e) {
        failure = e.message;
      } catch (_) {
        failure = null;
      }
    }
    if (!mounted) return;
    _importing = false;

    if (raw == null || !Pdf417DiscParser.looksLikeDisc(raw)) {
      await _showImportFailed(detail: failure);
      return;
    }
    try {
      Pdf417DiscParser.parse(raw);
    } on DiscParseException catch (e) {
      // Structurally plausible but corrupt (BAR-005): never populate a vehicle.
      await _showImportFailed(detail: e.message);
      return;
    }
    _debouncer.reset();
    setState(() => _error = null);
    _handleRaw(raw);
  }

  /// BAR-006 failure sheet for an unreadable photo.
  Future<void> _showImportFailed({String? detail}) async {
    StaffHaptics.error(context);
    final action = await showModalBottomSheet<_ImportAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ImportFailedSheet(detail: detail),
    );
    if (!mounted) return;
    switch (action) {
      case _ImportAction.manual:
        _retry();
        unawaited(_manualEntry());
      case _ImportAction.retry:
      case null:
        _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final demo = context.session.demo;
    return Scaffold(
      backgroundColor: SparklingColors.scrim,
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              fit: BoxFit.cover,
              // Only barcodes intersecting the viewfinder count, so a second
              // barcode in frame never wins over the disc. The overlay below
              // receives the same constraints, so the rects coincide.
              scanWindow: viewfinderRect(constraints.biggest),
              scanWindowUpdateThreshold: 4,
              errorBuilder: (context, error) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraFailed) {
                    setState(() => _cameraFailed = true);
                  }
                });
                return ColoredBox(
                  color: SparklingColors.scrim,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            error.errorCode ==
                                    MobileScannerErrorCode.permissionDenied
                                ? 'Camera permission is needed to scan licence '
                                      'discs. Allow it in Settings, import a '
                                      'photo, or enter the plate manually.'
                                : 'Camera unavailable — import a photo of the '
                                      'disc or enter the plate manually.',
                            textAlign: TextAlign.center,
                            style: SparklingTypography.bodyLarge.copyWith(
                              color: SparklingColors.darkOnSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          PillButton(
                            label: 'Import photo',
                            icon: Symbols.photo_library_rounded,
                            variant: PillButtonVariant.tonal,
                            dense: true,
                            onPressed: _importPhoto,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!_cameraFailed)
              ScanFrameOverlay(
                scanning: !_success,
                success: _success,
                torch: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTileButton(
                      icon: Symbols.photo_library_rounded,
                      tone: IconTileTone.onDark,
                      tooltip: 'Import photo',
                      onPressed: _success ? null : _importPhoto,
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) {
                        final on = state.torchState == TorchState.on;
                        return IconTileButton(
                          icon: on
                              ? Symbols.flashlight_on_rounded
                              : Symbols.flashlight_off_rounded,
                          tone: IconTileTone.onDark,
                          selected: on,
                          tooltip: on ? 'Torch off' : 'Torch on',
                          onPressed: state.torchState == TorchState.unavailable
                              ? null
                              : () => _controller.toggleTorch(),
                        );
                      },
                    ),
                  ],
                ),
                hint: _error != null
                    ? InfoBanner(
                        tone: InfoTone.error,
                        icon: Symbols.error_rounded,
                        text: _error!,
                        bordered: true,
                      )
                    : const InfoBanner(
                        tone: InfoTone.azure,
                        text:
                            'Hold the windscreen disc inside the frame — decoding '
                            'happens on your phone, even offline.',
                      ),
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Scan licence disc',
                            style: SparklingTypography.headlineMedium.copyWith(
                              color: SparklingColors.darkOnSurface,
                            ),
                          ),
                        ),
                        StatusChip(
                          label: _success ? 'Disc read' : 'PDF417 only',
                          tone: _success
                              ? StatusChipTone.success
                              : StatusChipTone.onDark,
                          icon: _success ? Symbols.check_rounded : null,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null || _cameraFailed) ...[
                          TextButton.icon(
                            onPressed: _success ? null : _importPhoto,
                            icon: const Icon(
                              Symbols.photo_library_rounded,
                              size: 18,
                            ),
                            label: const Text('Import a photo instead'),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (demo) ...[
                          PillButton(
                            label: 'Use sample disc (demo)',
                            icon: Symbols.qr_code_scanner_rounded,
                            variant: PillButtonVariant.whiteOnNavy,
                            expand: true,
                            onPressed: _success ? null : _useSample,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Enter manually',
                                icon: Symbols.keyboard_rounded,
                                variant: PillButtonVariant.outlined,
                                expand: true,
                                minHeight: 52,
                                onPressed: _success ? null : _manualEntry,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PillButton(
                                label: 'Retry scan',
                                icon: Symbols.refresh_rounded,
                                variant: PillButtonVariant.tonal,
                                expand: true,
                                minHeight: 52,
                                onPressed: _retry,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The raw barcode is never stored — only a hash (BAR-004).',
                          textAlign: TextAlign.center,
                          style: SparklingTypography.bodySmall.copyWith(
                            color: cs.brightness == Brightness.dark
                                ? cs.onSurfaceVariant
                                : SparklingColors.darkOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ImportAction { retry, manual }

/// BAR-006: the imported photo had no readable licence disc.
class _ImportFailedSheet extends StatelessWidget {
  const _ImportFailedSheet({this.detail});

  /// Optional decoder / parser reason shown under the main message.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.broken_image_rounded, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Couldn't read that photo",
                    style: SparklingTypography.titleLarge.copyWith(
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Couldn't read the disc from that photo. Compressed or blurry "
              'images often fail — try a sharper photo, scan live, or enter '
              'details manually.',
              style: SparklingTypography.bodyMedium,
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                style: SparklingTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Enter manually',
                    icon: Symbols.keyboard_rounded,
                    variant: PillButtonVariant.outlined,
                    expand: true,
                    onPressed: () =>
                        Navigator.of(context).pop(_ImportAction.manual),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: 'Retry',
                    icon: Symbols.refresh_rounded,
                    expand: true,
                    onPressed: () =>
                        Navigator.of(context).pop(_ImportAction.retry),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors [ScanFrameOverlay]'s viewfinder geometry (24 px inset, 2.4:1,
/// centred at 42 % height) so [MobileScanner.scanWindow] matches the frame
/// the user is aiming with.
Rect viewfinderRect(
  Size size, {
  double horizontalInset = 24,
  double aspectRatio = 2.4,
}) {
  final width = (size.width - horizontalInset * 2).clamp(0.0, size.width);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.42),
    width: width,
    height: width / aspectRatio,
  );
}
