import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// PDF417 licence-disc scanner (1d, CUS-012/013, BAR-*).
///
/// * Restricted to [BarcodeFormat.pdf417]; decoding is on-device.
/// * [ScanDebouncer] accepts one payload per scan session (BAR-007).
/// * Success = haptic + green flash, then a fade-through to the review
///   screen where nothing is committed silently.
/// * The controller is stopped on pause and disposed with the widget (BAR-009).
/// * Camera analysis runs at 1920×1080 (Android; iOS picks its own preset) and
///   a [MobileScanner.scanWindow] matching the viewfinder keeps the decoder on
///   the disc area — see `docs/PDF417.md` for why resolution matters.
/// * "Import photo" decodes a gallery image with
///   [MobileScannerController.analyzeImage] and runs the same parse → review
///   flow; unreadable photos get the BAR-006 failure sheet.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Android: request a full-HD analysis stream so a disc filling the
    // viewfinder is sampled at ≥ 3 px per PDF417 module. Ignored on iOS.
    cameraResolution: const Size(1920, 1080),
    autoStart: false,
  );
  final ScanDebouncer _debouncer = ScanDebouncer();
  final ImagePicker _picker = ImagePicker();

  bool _success = false;
  bool _flash = false;
  bool _handling = false;
  bool _importing = false;
  bool _cameraFailed = false;
  String? _parseError;
  String? _lastErrorHash;
  DateTime? _lastErrorAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.start();
    } on MobileScannerException {
      // Surfaced by MobileScanner.errorBuilder.
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // While the photo picker is up we own the camera lifecycle.
        if (!_success && !_importing) unawaited(_start());
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
    if (_handling || _success || _importing) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue ?? code.displayValue;
      if (raw == null || raw.isEmpty) continue;
      _handleRaw(raw);
      return;
    }
  }

  Future<void> _handleRaw(String raw) async {
    if (_debouncer.isDuplicate(raw) || _debouncer.hasResult) return;
    final DiscScanResult result;
    try {
      result = Pdf417DiscParser.parse(raw);
    } on DiscParseException catch (e) {
      // Throttle repeated identical failures while the user re-aims.
      final h = Pdf417DiscParser.hash(raw);
      final now = DateTime.now();
      if (_lastErrorHash == h &&
          _lastErrorAt != null &&
          now.difference(_lastErrorAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastErrorHash = h;
      _lastErrorAt = now;
      if (mounted) setState(() => _parseError = e.message);
      return;
    }
    if (!_debouncer.accept(raw)) return;
    _handling = true;
    AppHaptics.success(context);
    setState(() {
      _success = true;
      _flash = true;
      _parseError = null;
    });
    final reduced = SparklingMotion.reducedMotion(context);
    await Future<void>.delayed(
      reduced ? Duration.zero : const Duration(milliseconds: 380),
    );
    if (!mounted) return;
    setState(() => _flash = false);
    await _controller.stop();
    if (!mounted) return;
    await context.push(Routes.scanReview, extra: result);
    // Back from review (Rescan): reset and resume.
    if (!mounted) return;
    _debouncer.reset();
    _handling = false;
    setState(() => _success = false);
    unawaited(_start());
  }

  void _retry() {
    _debouncer.reset();
    _lastErrorHash = null;
    setState(() {
      _parseError = null;
      _success = false;
      _handling = false;
      _cameraFailed = false;
    });
    unawaited(_start());
  }

  void _useSample() => _handleRaw(Pdf417DiscParser.sampleDiscPayload());

  /// "Import photo": pick a gallery image, decode it on-device with the same
  /// PDF417-only decoder, then hand a valid payload to [_handleRaw].
  Future<void> _importPhoto() async {
    if (_importing || _success || _handling) return;
    _importing = true;
    // Release the camera while the system picker is presented; the lifecycle
    // observer skips its auto-restart while [_importing] is set.
    await _controller.stop();
    XFile? file;
    String? failure;
    try {
      file = await _picker.pickImage(source: ImageSource.gallery);
    } catch (_) {
      failure = 'Could not open your photo library. Check permissions.';
    }
    if (!mounted) return;
    if (file == null && failure == null) {
      // Cancelled — back to live scanning.
      _importing = false;
      unawaited(_start());
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
    _lastErrorHash = null;
    setState(() => _parseError = null);
    await _handleRaw(raw);
  }

  /// BAR-006 failure sheet for an unreadable photo.
  Future<void> _showImportFailed({String? detail}) async {
    final action = await showModalBottomSheet<_ImportAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ImportFailedSheet(detail: detail),
    );
    if (!mounted) return;
    switch (action) {
      case _ImportAction.manual:
        context.pushReplacement(Routes.vehicleAdd);
      case _ImportAction.retry:
      case null:
        _retry();
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.repos.demo;
    const scrim = SparklingColors.scrim;
    final hintText =
        _parseError ??
        (_success
            ? 'Disc decoded — opening review…'
            : 'Hold steady — decoding happens on your phone, even offline.');

    return Scaffold(
      backgroundColor: scrim,
      body: SafeArea(
        child: Theme(
          data: SparklingTheme.dark(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    IconTileButton(
                      icon: Symbols.close_rounded,
                      tone: IconTileTone.onDark,
                      tooltip: 'Close scanner',
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        'Scan licence disc',
                        textAlign: TextAlign.center,
                        style: SparklingTypography.headlineMedium.copyWith(
                          fontSize: 21,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
                        final available =
                            state.torchState != TorchState.unavailable &&
                            state.isRunning;
                        return IconTileButton(
                          icon: on
                              ? Symbols.flashlight_on_rounded
                              : Symbols.flashlight_off_rounded,
                          tone: IconTileTone.onDark,
                          selected: on,
                          fill: 1,
                          tooltip: on ? 'Torch off' : 'Torch on',
                          onPressed: available
                              ? () => _controller.toggleTorch()
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SparklingShapes.hero),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: const Color(0xFF111A2C)),
                          MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                            fit: BoxFit.cover,
                            // Only barcodes intersecting the viewfinder count,
                            // so a second barcode in frame (e.g. a parking
                            // ticket) never wins over the disc.
                            scanWindow: viewfinderRect(constraints.biggest),
                            scanWindowUpdateThreshold: 4,
                            placeholderBuilder: (context) =>
                                const SizedBox.shrink(),
                            errorBuilder: (context, error) {
                              // Drop the viewfinder scrim so the guidance and its
                              // Import / Try again buttons are readable.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && !_cameraFailed) {
                                  setState(() => _cameraFailed = true);
                                }
                              });
                              return _CameraError(
                                error: error,
                                onRetry: _retry,
                                onImport: _importPhoto,
                                onSample: demo ? _useSample : null,
                              );
                            },
                          ),
                          if (!_cameraFailed)
                            ScanFrameOverlay(
                              scanning: !_success && _parseError == null,
                              success: _success,
                              scrimOpacity: 0.72,
                              hint: Text(
                                'Align the PDF417 barcode on the licence disc inside the frame',
                                textAlign: TextAlign.center,
                                style: SparklingTypography.bodyLarge.copyWith(
                                  fontSize: 16,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _flash ? 1 : 0,
                              duration: SparklingMotion.durationFor(
                                context,
                                SparklingMotion.fast,
                              ),
                              child: ColoredBox(
                                color: SparklingColors.darkSuccess.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(
                  children: [
                    InfoBanner(
                      tone: _parseError != null
                          ? InfoTone.error
                          : InfoTone.azure,
                      icon: _parseError != null
                          ? Symbols.error_rounded
                          : Symbols.center_focus_weak_rounded,
                      text: hintText,
                    ),
                    if (_parseError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton.icon(
                          onPressed: _success ? null : _importPhoto,
                          icon: const Icon(
                            Symbols.photo_library_rounded,
                            size: 18,
                          ),
                          label: const Text('Import a photo instead'),
                        ),
                      ),
                    if (demo)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton.icon(
                          onPressed: _success ? null : _useSample,
                          icon: const Icon(Symbols.science_rounded, size: 18),
                          label: const Text('Demo: use sample disc'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: 'Enter manually',
                            variant: PillButtonVariant.outlined,
                            expand: true,
                            minHeight: 54,
                            onPressed: () =>
                                context.pushReplacement(Routes.vehicleAdd),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PillButton(
                            label: 'Retry scan',
                            variant: PillButtonVariant.tonal,
                            expand: true,
                            minHeight: 54,
                            onPressed: _retry,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Permission-denied / unavailable guidance shown inside the viewfinder card.
class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.error,
    required this.onRetry,
    required this.onImport,
    this.onSample,
  });

  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onImport;
  final VoidCallback? onSample;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = denied ? 'Camera access needed' : 'Camera unavailable';
    final body = denied
        ? 'Allow camera access in Settings to scan your licence disc, import a photo of it, or enter the details manually.'
        : 'This device has no usable camera (simulators do not). Import a photo of the disc or enter the vehicle manually.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied
                  ? Symbols.no_photography_rounded
                  : Symbols.videocam_off_rounded,
              size: 44,
              color: SparklingColors.darkPrimary,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SparklingTypography.titleLarge.copyWith(
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: SparklingTypography.bodyMedium.copyWith(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                PillButton(
                  label: 'Try again',
                  variant: PillButtonVariant.tonal,
                  dense: true,
                  onPressed: onRetry,
                ),
                PillButton(
                  label: 'Import photo',
                  variant: PillButtonVariant.outlined,
                  dense: true,
                  onPressed: onImport,
                ),
                if (onSample != null)
                  PillButton(
                    label: 'Use sample disc',
                    variant: PillButtonVariant.outlined,
                    dense: true,
                    onPressed: onSample,
                  ),
              ],
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
    final cs = Theme.of(context).colorScheme;
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
/// the user is aiming with. Exposed for tests.
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
