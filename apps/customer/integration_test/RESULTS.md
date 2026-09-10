# On-device PDF417 decode results — real licence-disc photos

Produced by `integration_test/disc_photo_decode_test.dart` on 9 Sep 2026
(Flutter 3.47, `mobile_scanner` 7.4.0). Each fixture is written to a temp
file on the device and passed to `MobileScannerController.analyzeImage(path,
formats: [BarcodeFormat.pdf417])`; the raw text then goes through
`Pdf417DiscParser.tryParse`. The five photos are the WhatsApp re-shares in
`fixtures/` (source order (5)…(9)).

```sh
cd apps/customer
flutter test integration_test/disc_photo_decode_test.dart -d emulator-5554 --dart-define-from-file=env/demo.json
flutter test integration_test/disc_photo_decode_test.dart -d "iPhone 16"  --dart-define-from-file=env/demo.json
```

## Photo resolution vs. what PDF417 needs

All five fixtures are **960 × 1280 px** (WhatsApp-compressed, ~140–200 KB
JPEG). The disc barcode spans roughly 400 px of width for ≈ 270 modules,
i.e. **< 2 px per module**, while a comfortable decode wants ≈ 3 px per module
or more (`docs/PDF417.md`). That is why the offline zxing-cpp experiment only
decoded 1 of 5 (and needed a 2× upscale for that one). An in-app upscale
before `analyzeImage` is not possible without an image library, so it was not
attempted; the decoders below work on the photos as-is.

## Android — Pixel_10 emulator (API 37 preview, `CP21.260330.012`)

Decoder: **Google ML Kit barcode-scanning 17.3.0** (bundled model, no
download needed). Test result: **All tests passed** — every photo decoded and
parsed, including the four that zxing-cpp could not read.

| Fixture | Vehicle (photo) | Size | Result | Registration | VIN | Make / model | Expiry |
|---|---|---|---|---|---|---|---|
| disc_1.jpeg | Mahindra | 960×1280 | decoded + parsed | `LHP858NW` | `MA1NY2NWPS2C14974` | Mahindra XUV300, Beige | 2026-09-30 |
| disc_2.jpeg | Renault Kwid (**asserted**) | 960×1280 | decoded + parsed | `KK10FCGP` | `MEEBBA00900798734` | Renault Kwid, White | 2026-06-30 |
| disc_3.jpeg | Ford station wagon | 960×1280 | decoded + parsed | `LJL416NW` | `LJXCU3BB0SHF82238` | Ford Territory, White | 2026-12-31 |
| disc_4.jpeg | Ford bakkie | 960×1280 | decoded + parsed | `KMM808NW` | `AFAPXXMJ2PMB08850` | Ford Ranger, White | 2026-12-31 |
| disc_5.jpeg | Toyota station wagon | 960×1280 | decoded + parsed | `KXR596NW` | `JTDPYGJ1S00924294` | Toyota Urban Cruiser, White | 2026-07-31 |

Raw payloads (as returned by ML Kit, `%`-delimited — field layout per
`docs/PDF417.md`):

```
disc_1  %MVL1CC10%0147%4044A0BW%1%4044003283LN%LHP858NW%DKW501F%Hatch back / Luikrug%MAHINDRA%XUV300%Beige / Beige%MA1NY2NWPS2C14974%NWSZC13771%2026-09-30%
disc_2  %MVL1CC73%0146%4025M007%1%4025013HM0M8%KK10FCGP%DJJ697X%Hatch back / Luikrug%RENAULT%KWID%White / Wit%MEEBBA00900798734%B4DA404E217984%2026-06-30%
disc_3  %MVL1CC77%0147%4044A0BW%1%404400328W00%LJL416NW%JBB503X%Station wagon / Stasiewa%FORD%TERRITORY%White / Wit%LJXCU3BB0SHF82238%S8G078371%2026-12-31%
disc_4  %MVL1CC20%0139%4522A001%1%404400328MD5%KMM808NW%CPX217X%Pick-up / Bakkie%FORD%RANGER%White / Wit%AFAPXXMJ2PMB08850%SA2LPMB08850%2026-12-31%
disc_5  %MVL1CC85%0156%4522A001%1%40260039VSYJ%KXR596NW%JLG973L%Station wagon / Stasiewa%TOYOTA%URBAN CRUISER%White / Wit%JTDPYGJ1S00924294%K15BN4249897%2026-07-31%
```

Parsed fields (from `DiscScanResult.toJson()`), per fixture:

| Fixture | licence_no | vehicle_register_no | description | colour | engine_no | raw_hash (sha256) |
|---|---|---|---|---|---|---|
| disc_1 | 4044003283LN | DKW501F | Hatch back / Luikrug | Beige / Beige | NWSZC13771 | b3bb7ffd…fce4451b6b |
| disc_2 | 4025013HM0M8 | DJJ697X | Hatch back / Luikrug | White / Wit | B4DA404E217984 | 2ced32d9…a8998230380d |
| disc_3 | 404400328W00 | JBB503X | Station wagon / Stasiewa | White / Wit | S8G078371 | 1e42e532…0c3740c5d3ef |
| disc_4 | 404400328MD5 | CPX217X | Pick-up / Bakkie | White / Wit | SA2LPMB08850 | 4d574729…8cd112dc09 |
| disc_5 | 40260039VSYJ | JLG973L | Station wagon / Stasiewa | White / Wit | K15BN4249897 | 2523782d…04b600f6210e |

Observations:

* ML Kit's PDF417 decoder is considerably more tolerant than zxing-cpp at
  < 2 px/module: 5/5 vs 1/5, with no pre-processing.
* The Mahindra photo that zxing decoded to garbage (checksum-valid but
  corrupt) decodes correctly here; the BAR-005 check (no foreign VIN, valid
  17-char VIN, `looksLikeDisc` true for every accepted payload) passed for all
  five. Note `docs/PDF417.md` lists the Mahindra as "DKW501F" — that is its
  *vehicle register number* (index 7); the plate is `LHP858NW`.
* Every disc except the Kwid is still in date; the Kwid (expiry 2026-06-30)
  is flagged `isExpired` by the parser, as in the offline experiment.
* Cosmetic: the parser's title-casing renders `XUV300` as `Xuv300`
  (`packages/sparkling_core`, out of scope here).

## iOS — iPhone 16 simulator (reports iOS 18.3.1, build 22D8075)

Decoder: Apple Vision (`VNDetectBarcodesRequest`) — **could not run on the
simulator**. `mobile_scanner` 7.4.0 guards `analyzeImage` with
`#if os(iOS) && targetEnvironment(simulator)` and returns
`MOBILE_SCANNER_UNSUPPORTED_OPERATION` ("Analyzing an image from a file is not
supported on the iOS Simulator."), which the Dart side surfaces as
`UnsupportedError`. The test detects this, prints the table below and calls
`markTestSkipped`, so the suite reports as skipped rather than failed.

Test output (`flutter test … -d "iPhone 16"` → `All tests skipped`):

| Fixture | Vehicle (photo) | Size | Result |
|---|---|---|---|
| disc_1.jpeg | Mahindra | 960×1280 | UNSUPPORTED — "Analyzing an image from a file is not supported on the iOS Simulator." |
| disc_2.jpeg | Renault Kwid | 960×1280 | UNSUPPORTED — same |
| disc_3.jpeg | Ford station wagon | 960×1280 | UNSUPPORTED — same |
| disc_4.jpeg | Ford bakkie | 960×1280 | UNSUPPORTED — same |
| disc_5.jpeg | Toyota station wagon | 960×1280 | UNSUPPORTED — same |

Live camera scanning on iOS is unaffected (that path uses
`AVCaptureMetadataOutput`/Vision on device), and `analyzeImage` works on a
physical iPhone — re-run the same command with a device id to fill in the
Vision results.
