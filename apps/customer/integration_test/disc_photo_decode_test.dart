// On-device PDF417 decode test against the five real licence-disc photos in
// `fixtures/` (see docs/PDF417.md for the offline zxing experiment).
//
// Runs `MobileScannerController.analyzeImage` — Apple Vision on iOS, Google
// ML Kit on Android — on each photo and prints a summary table. Only the
// Renault Kwid photo (disc_2, KK10FCGP) is asserted to decode + parse; the
// rest are informational. It also asserts the BAR-005 invariant: decoded but
// corrupt text never yields a vehicle with a different VIN.
//
//   flutter test integration_test/disc_photo_decode_test.dart \
//     -d "iPhone 16" --dart-define-from-file=env/demo.json
//   flutter test integration_test/disc_photo_decode_test.dart \
//     -d emulator-5554 --dart-define-from-file=env/demo.json
//
// Note: mobile_scanner refuses `analyzeImage` on the iOS *Simulator*
// (MOBILE_SCANNER_UNSUPPORTED_OPERATION); the test reports that and skips
// instead of failing. A physical iPhone runs the real Vision decoder.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'fixtures/disc_fixtures.dart';

const String kwidRegistration = 'KK10FCGP';
const String kwidVin = 'MEEBBA00900798734';

class _Fixture {
  const _Fixture(this.name, this.vehicle, {this.registration, this.vin});
  final String name;
  final String vehicle;

  /// Known-good values (only for the Kwid, which decoded offline).
  final String? registration;
  final String? vin;
}

const List<_Fixture> _fixtures = [
  _Fixture('disc_1.jpeg', 'Mahindra (DKW501F)'),
  _Fixture(
    'disc_2.jpeg',
    'Renault Kwid',
    registration: kwidRegistration,
    vin: kwidVin,
  ),
  _Fixture('disc_3.jpeg', 'Ford station wagon'),
  _Fixture('disc_4.jpeg', 'Ford bakkie'),
  _Fixture('disc_5.jpeg', 'Toyota station wagon'),
];

class _Outcome {
  _Outcome(this.fixture);
  final _Fixture fixture;
  int? width;
  int? height;
  int barcodeCount = 0;
  String? raw;
  String? error;
  bool unsupported = false;
  DiscScanResult? parsed;

  bool get decoded => raw != null && raw!.isNotEmpty;
  bool get looksLikeDisc => decoded && Pdf417DiscParser.looksLikeDisc(raw!);

  String get status {
    if (unsupported) return 'UNSUPPORTED';
    if (!decoded) return 'no barcode';
    if (parsed == null) return 'decoded, REJECTED by parser';
    return 'decoded + parsed';
  }
}

String _decoderName() {
  if (Platform.isIOS) return 'Apple Vision (VNDetectBarcodesRequest)';
  if (Platform.isAndroid) return 'Google ML Kit barcode-scanning (bundled)';
  return Platform.operatingSystem;
}

Future<(int, int)?> _imageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

String _pad(String s, int w) => s.length >= w ? s : s.padRight(w);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MobileScannerController.analyzeImage on the five real disc photos',
    (tester) async {
      final controller = MobileScannerController(
        formats: const [BarcodeFormat.pdf417],
        autoStart: false,
      );
      final dir = await Directory.systemTemp.createTemp('disc_fixtures_');
      final outcomes = <_Outcome>[];

      try {
        for (final fixture in _fixtures) {
          final outcome = _Outcome(fixture);
          outcomes.add(outcome);
          final bytes = base64Decode(discFixturesBase64[fixture.name]!);
          final size = await _imageSize(bytes);
          outcome.width = size?.$1;
          outcome.height = size?.$2;
          final file = File('${dir.path}/${fixture.name}');
          await file.writeAsBytes(bytes, flush: true);

          try {
            final capture = await controller.analyzeImage(
              file.path,
              formats: const [BarcodeFormat.pdf417],
            );
            final barcodes = capture?.barcodes ?? const <Barcode>[];
            outcome.barcodeCount = barcodes.length;
            for (final code in barcodes) {
              final value = code.rawValue ?? code.displayValue;
              if (value != null && value.isNotEmpty) {
                outcome.raw = value;
                break;
              }
            }
          } on UnsupportedError catch (e) {
            outcome.unsupported = true;
            outcome.error = e.message;
          } on MobileScannerBarcodeException catch (e) {
            outcome.error = e.message ?? 'MobileScannerBarcodeException';
          } catch (e) {
            outcome.error = '$e';
          }

          if (outcome.decoded) {
            outcome.parsed = Pdf417DiscParser.tryParse(outcome.raw!);
          }
        }
      } finally {
        await controller.dispose();
        await dir.delete(recursive: true);
      }

      // ---- summary ---------------------------------------------------------
      final os =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      print('DISC-RESULT|=== DISC PHOTO DECODE SUMMARY ===');
      print('DISC-RESULT|platform: $os');
      print('DISC-RESULT|decoder: ${_decoderName()}');
      print(
        'DISC-RESULT|${_pad('fixture', 12)} ${_pad('vehicle', 22)} '
        '${_pad('size', 10)} ${_pad('status', 28)} raw / parsed',
      );
      for (final o in outcomes) {
        final size = o.width == null ? '?' : '${o.width}x${o.height}';
        final detail = o.unsupported
            ? (o.error ?? 'unsupported')
            : !o.decoded
            ? (o.error ?? 'barcodes=${o.barcodeCount}')
            : o.parsed == null
            ? 'raw=${jsonEncode(o.raw)}'
            : 'raw=${jsonEncode(o.raw)} parsed=${jsonEncode(o.parsed!.toJson())}';
        print(
          'DISC-RESULT|${_pad(o.fixture.name, 12)} '
          '${_pad(o.fixture.vehicle, 22)} ${_pad(size, 10)} '
          '${_pad(o.status, 28)} $detail',
        );
      }
      print('DISC-RESULT|=== END SUMMARY ===');

      // ---- platform cannot run the decoder at all -------------------------
      if (outcomes.every((o) => o.unsupported)) {
        final reason =
            'analyzeImage is unsupported here: ${outcomes.first.error}';
        print('DISC-RESULT|SKIPPED: $reason');
        markTestSkipped(reason);
        return;
      }

      // ---- BAR-005: corrupt text never yields a foreign VIN ---------------
      for (final o in outcomes) {
        if (!o.decoded) continue;
        if (o.parsed == null) {
          // Rejected — nothing else to check; the parser refused it.
          continue;
        }
        expect(
          o.looksLikeDisc,
          isTrue,
          reason: '${o.fixture.name}: parsed but looksLikeDisc is false',
        );
        final vin = o.parsed!.vin;
        if (vin != null) {
          expect(
            RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin),
            isTrue,
            reason: '${o.fixture.name}: invalid VIN accepted: $vin',
          );
        }
        if (o.fixture.vin != null) {
          expect(
            vin,
            o.fixture.vin,
            reason: '${o.fixture.name}: VIN differs from the known disc',
          );
        } else {
          expect(
            vin,
            isNot(kwidVin),
            reason:
                '${o.fixture.name}: yielded the Kwid VIN — corrupt text '
                'leaked through the parser',
          );
        }
      }

      // ---- the one hard assertion: the Kwid photo ------------------------
      final kwid = outcomes.firstWhere((o) => o.fixture.name == 'disc_2.jpeg');
      expect(
        kwid.decoded,
        isTrue,
        reason: 'disc_2 (Renault Kwid) did not decode: ${kwid.error}',
      );
      expect(
        kwid.parsed,
        isNotNull,
        reason: 'disc_2 decoded but failed to parse',
      );
      expect(kwid.parsed!.registrationNo, kwidRegistration);
      expect(kwid.parsed!.vin, kwidVin);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
