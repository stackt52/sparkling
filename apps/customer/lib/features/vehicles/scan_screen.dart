import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );
  final ScanDebouncer _debouncer = ScanDebouncer();

  bool _success = false;
  bool _flash = false;
  bool _handling = false;
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
        if (!_success) unawaited(_start());
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
    if (_handling || _success) return;
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
    });
    unawaited(_start());
  }

  void _useSample() => _handleRaw(Pdf417DiscParser.sampleDiscPayload());

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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: const Color(0xFF111A2C)),
                        MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          fit: BoxFit.cover,
                          placeholderBuilder: (context) =>
                              const SizedBox.shrink(),
                          errorBuilder: (context, error) => _CameraError(
                            error: error,
                            onRetry: _retry,
                            onSample: demo ? _useSample : null,
                          ),
                        ),
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
    this.onSample,
  });

  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback? onSample;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = denied ? 'Camera access needed' : 'Camera unavailable';
    final body = denied
        ? 'Allow camera access in Settings to scan your licence disc, or enter the details manually.'
        : 'This device has no usable camera (simulators do not). Enter the vehicle manually instead.';
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
