import { describe, expect, it } from 'vitest';
import { formatRegistration, parseDisc } from '../src/lib/pdf417.js';

const RAW = '%MVL1CC48%0148%4022M0CS%1%4022027U1BF%KL45MNGP%AAA123%Sedan (closed top)%TOYOTA%COROLLA CROSS%Celestite Grey%AHTFB3CB301234567%2ZR1234567%2027-03-31%';

describe('SA licence disc parser (BAR-00x)', () => {
  it('parses the positional layout and hashes the raw payload', () => {
    const p = parseDisc(RAW);
    expect(p.registration_no).toBe('KL 45 MN GP');
    expect(p.licence_no).toBe('4022027U1BF');
    expect(p.make).toBe('TOYOTA');
    expect(p.model).toBe('COROLLA CROSS');
    expect(p.colour).toBe('Celestite Grey');
    expect(p.vin).toBe('AHTFB3CB301234567');
    expect(p.engine_no).toBe('2ZR1234567');
    expect(p.disc_expiry).toBe('2027-03-31');
    expect(p.disc_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(p.warnings).toEqual([]);
  });
  it('warns on bad VIN / expired disc and rejects junk', () => {
    const p = parseDisc(RAW.replace('AHTFB3CB301234567', 'BADVIN').replace('2027-03-31', '2020-01-01'));
    expect(p.warnings).toContain('VIN failed format validation');
    expect(p.warnings).toContain('Licence disc has expired');
    expect(() => parseDisc('hello')).toThrow();
    expect(() => parseDisc('%a%b%c%d%e%%g%h%i%j%k%l%m%n%o%')).toThrow(/Registration/);
  });
  it('formats registrations', () => {
    expect(formatRegistration('kl45mngp')).toBe('KL 45 MN GP');
    expect(formatRegistration('CA123456')).toBe('CA 123456');
    expect(formatRegistration('XYZ 999')).toBe('XYZ999');
  });
});
