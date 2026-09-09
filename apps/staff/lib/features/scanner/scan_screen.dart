import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
  );
  final ScanDebouncer _debouncer = ScanDebouncer();
  String? _error;
  bool _success = false;
  bool _cameraFailed = false;

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
        unawaited(_controller.start());
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
    if (_success) return;
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
    });
    if (!_cameraFailed) unawaited(_controller.start());
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

  void _useSample() =>
      _handleRaw(Pdf417DiscParser.sampleDiscPayload());

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final demo = context.session.demo;
    return Scaffold(
      backgroundColor: SparklingColors.scrim,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            fit: BoxFit.cover,
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
                    child: Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera permission is needed to scan licence discs. '
                                'Allow it in Settings, or enter the plate manually.'
                          : 'Camera unavailable — enter the plate manually.',
                      textAlign: TextAlign.center,
                      style: SparklingTypography.bodyLarge.copyWith(
                        color: SparklingColors.darkOnSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          ScanFrameOverlay(
            scanning: !_success && !_cameraFailed,
            success: _success,
            torch: ValueListenableBuilder<MobileScannerState>(
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
    );
  }
}
