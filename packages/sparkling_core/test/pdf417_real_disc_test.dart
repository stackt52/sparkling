import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

// Decoded with zxing-cpp from a photo of a real South African licence disc
// (Renault Kwid, expiry 2026-06-30). Confirms the documented `%` layout.
const realDisc =
    '%MVL1CC73%0146%4025M007%1%4025013HM0M8%KK10FCGP%DJJ697X%Hatch back / Luikrug%RENAULT%KWID%White / Wit%MEEBBA00900798734%B4DA404E217984%2026-06-30%';

void main() {
  test('real disc payload maps every field', () {
    expect(Pdf417DiscParser.looksLikeDisc(realDisc), isTrue);
    final r = Pdf417DiscParser.parse(realDisc);
    expect(r.registrationNo.replaceAll(' ', ''), 'KK10FCGP');
    expect(r.registrationNoFormatted, 'KK 10 FC GP');
    expect(r.vin, 'MEEBBA00900798734');
    expect(r.engineNo, 'B4DA404E217984');
    expect(r.make, 'Renault');
    expect(r.model, 'Kwid');
    expect(r.colour, 'White / Wit');
    expect(r.description, 'Hatch back / Luikrug');
    expect(r.licenceNo, '4025013HM0M8');
    expect(r.discExpiry, DateTime(2026, 6, 30));
    final v = r.toVehicleInput();
    expect(v.registrationNo, 'KK 10 FC GP');
    expect(v.vin, 'MEEBBA00900798734');
  });

  test('corrupt decode from a blurry photo is rejected', () {
    expect(Pdf417DiscParser.looksLikeDisc(corruptDecode), isFalse);
    expect(
      () => Pdf417DiscParser.parse(corruptDecode),
      throwsA(isA<DiscParseException>()),
    );
    expect(Pdf417DiscParser.tryParse(corruptDecode), isNull);
  });
}

// A corrupt decode from a blurry photo of a different disc: zxing reported it as
// a valid PDF417 symbol, but the payload is garbage. Structural validation
// (CUS-012 / BAR-006) must reject it rather than populate a vehicle.
const corruptDecode =
    'AAJYTMNO NVKYLZVDKW501F%Hhzi back / D-4\$56V<HT>0789<CR>*YONTUV300\$658|0/1T ?VPKZYALUIKRUGC,1/9*.0V=974%NWSFCFGABZPVCACGQGCCXZGAZZTVIHINDRAUvv  -133|1370.-^ xugexeue';
