import { describe, expect, it } from 'vitest';
import { parseDisc } from '../src/lib/pdf417.js';

// Decoded with zxing-cpp from a photo of a real South African licence disc (Renault Kwid, 2026-06-30).
const REAL = '%MVL1CC73%0146%4025M007%1%4025013HM0M8%KK10FCGP%DJJ697X%Hatch back / Luikrug%RENAULT%KWID%White / Wit%MEEBBA00900798734%B4DA404E217984%2026-06-30%';

describe('parseDisc — real disc payload', () => {
  it('maps every documented field', () => {
    const r = parseDisc(REAL);
    expect(r.registration_no.replace(/\s/g, '')).toBe('KK10FCGP');
    expect(r.vin).toBe('MEEBBA00900798734');
    expect(r.engine_no).toBe('B4DA404E217984');
    expect(r.make).toBe('RENAULT');
    expect(r.model).toBe('KWID');
    expect(r.disc_expiry).toBe('2026-06-30');
    expect(r.licence_no).toBe('4025013HM0M8');
    expect(r.warnings).toEqual(['Licence disc has expired']); // disc expired 2026-06-30
  });

  it('rejects a corrupt decode that passed the barcode checksum', () => {
    const corrupt = 'AAJYTMNO NVKYLZVDKW501F%Hhzi back / D-4$56V<HT>0789<CR>*YONTUV300$658|0/1T ?VPKZYALUIKRUGC,1/9*.0V=974%NWSFCFGABZPVCACGQGCCXZGAZZTVIHINDRAUvv  -133|1370.-^ xugexeue';
    expect(() => parseDisc(corrupt)).toThrow();
  });
});
