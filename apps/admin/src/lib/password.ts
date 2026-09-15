/** Password rules (mirrors the staff app): at least 10 characters with a letter and a digit. */
export const PASSWORD_RULES = [
  { key: 'length', label: 'At least 10 characters', test: (p: string) => p.length >= 10 },
  { key: 'letter', label: 'Contains a letter', test: (p: string) => /[A-Za-z]/.test(p) },
  { key: 'digit', label: 'Contains a digit', test: (p: string) => /\d/.test(p) },
] as const;

export const passwordValid = (p: string) => PASSWORD_RULES.every((r) => r.test(p));

/** 0–4 strength score: rules + length + symbol / mixed case; only a hint, the rules are the gate. */
export function passwordStrength(p: string): { score: number; label: string; tone: 'error' | 'warning' | 'success' } {
  if (!p) return { score: 0, label: '', tone: 'error' };
  let score = 0;
  if (p.length >= 10) score += 1;
  if (p.length >= 14) score += 1;
  if (/[A-Za-z]/.test(p) && /\d/.test(p)) score += 1;
  if (/[^A-Za-z0-9]/.test(p) || (/[a-z]/.test(p) && /[A-Z]/.test(p))) score += 1;
  if (score <= 1) return { score, label: 'Weak', tone: 'error' };
  if (score <= 2) return { score, label: 'Fair', tone: 'warning' };
  if (score === 3) return { score, label: 'Good', tone: 'success' };
  return { score, label: 'Strong', tone: 'success' };
}
