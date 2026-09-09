/**
 * Sparkling design tokens — single source of truth (SRS UX-001).
 * Every value comes from design_handoff_sparkling_apps/README.md.
 * Components never hard-code colours; they use `tk.*` (CSS variables emitted
 * by MUI from the palettes below) so the light/dark toggle has no FOUC.
 */

export interface SchemeTokens {
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  secondary: string;
  onSecondary: string;
  secondaryContainer: string;
  onSecondaryContainer: string;
  surface: string;
  surfaceCard: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  onSurface: string;
  onSurfaceVariant: string;
  outline: string;
  outlineVariant: string;
  error: string;
  errorContainer: string;
  onErrorContainer: string;
  success: string;
  successContainer: string;
  onSuccessContainer: string;
  warning: string;
  warningContainer: string;
  onWarningContainer: string;
  gold: string;
  goldLight: string;
  onGold: string;
  track: string;
  heroGradient: string;
}

export const lightTokens: SchemeTokens = {
  primary: '#006398',
  onPrimary: '#FFFFFF',
  primaryContainer: '#CBE6FF',
  onPrimaryContainer: '#001D31',
  secondary: '#203060',
  onSecondary: '#FFFFFF',
  secondaryContainer: '#D7E3F9',
  onSecondaryContainer: '#14243D',
  surface: '#F6FAFD',
  surfaceCard: '#FFFFFF',
  surfaceContainer: '#EBF1F7',
  surfaceContainerHigh: '#E1EAF2',
  onSurface: '#16212B',
  onSurfaceVariant: '#51606F',
  outline: '#C3CFDA',
  outlineVariant: '#E1EAF2',
  error: '#BA1A1A',
  errorContainer: '#FFDAD6',
  onErrorContainer: '#93000A',
  success: '#1D8A4E',
  successContainer: '#C9F0D8',
  onSuccessContainer: '#0D5C32',
  warning: '#7A5000',
  warningContainer: '#FFE6B8',
  onWarningContainer: '#7A5000',
  gold: '#E2BA5F',
  goldLight: '#F3DDA4',
  onGold: '#5C4200',
  track: '#E1EAF2',
  heroGradient: 'linear-gradient(130deg,#203060 30%,#0A5F96 80%,#00A0E0)',
};

export const darkTokens: SchemeTokens = {
  primary: '#8BD2FF',
  onPrimary: '#00344F',
  primaryContainer: '#0F3550',
  onPrimaryContainer: '#CBE8FF',
  secondary: '#8BD2FF',
  onSecondary: '#00344F',
  secondaryContainer: '#1B2942',
  onSecondaryContainer: '#E3E9F4',
  surface: '#0D1524',
  surfaceCard: '#151F33',
  surfaceContainer: '#151F33',
  surfaceContainerHigh: '#1B2942',
  onSurface: '#E3E9F4',
  onSurfaceVariant: '#98A6BB',
  outline: '#2B3C58',
  outlineVariant: '#1F2E48',
  error: '#FFB59F',
  errorContainer: '#4A1F1A',
  onErrorContainer: '#FFDAD6',
  success: '#6EE7A0',
  successContainer: '#123D28',
  onSuccessContainer: '#C9F0D8',
  warning: '#F3DDA4',
  warningContainer: '#3B2E12',
  onWarningContainer: '#F3DDA4',
  gold: '#E2BA5F',
  goldLight: '#F3DDA4',
  onGold: '#5C4200',
  track: '#2B3C58',
  heroGradient: 'linear-gradient(130deg,#1B2942 20%,#0A4F7D 75%,#0083C4)',
};

/** Brand constants that do not change between schemes. */
export const brand = {
  navy: '#203060',
  azure: '#00A0E0',
  azureGradient: 'linear-gradient(135deg,#00A0E0,#0074B8)',
  goldGradient: 'linear-gradient(135deg,#F3DDA4,#E2BA5F)',
  /** Chart series colours (README §3a). */
  chartCarWash: '#006398',
  chartAutoBody: '#8BD2FF',
} as const;

export const shape = {
  card: 24,
  frame: 20,
  tile: 18,
  pill: 999,
  field: 14,
  dialog: 28,
} as const;

export const spacing = {
  gutter: 26,
  cardPadding: 20,
  cardGap: 14,
} as const;

export const fonts = {
  sans: 'var(--font-outfit), "Outfit", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  mono: 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace',
} as const;

const v = (name: string) => `var(--mui-palette-${name})`;

/**
 * CSS-variable references for use in `sx`, `styled()` and plain CSS.
 * They resolve per colour scheme because MUI emits one set of variables for
 * `[data-mui-color-scheme="light"]` and one for `dark`.
 */
export const tk = {
  primary: v('primary-main'),
  onPrimary: v('primary-contrastText'),
  primaryContainer: v('container-primary'),
  onPrimaryContainer: v('container-onPrimary'),
  secondary: v('secondary-main'),
  onSecondary: v('secondary-contrastText'),
  secondaryContainer: v('container-secondary'),
  onSecondaryContainer: v('container-onSecondary'),
  surface: v('surface-main'),
  surfaceCard: v('surface-card'),
  surfaceContainer: v('surface-container'),
  surfaceContainerHigh: v('surface-containerHigh'),
  onSurface: v('surface-on'),
  onSurfaceVariant: v('surface-onVariant'),
  outline: v('surface-outline'),
  outlineVariant: v('surface-outlineVariant'),
  track: v('surface-track'),
  error: v('error-main'),
  errorContainer: v('container-error'),
  onErrorContainer: v('container-onError'),
  success: v('success-main'),
  successContainer: v('container-success'),
  onSuccessContainer: v('container-onSuccess'),
  warning: v('warning-main'),
  warningContainer: v('container-warning'),
  onWarningContainer: v('container-onWarning'),
  gold: v('gold-main'),
  goldLight: v('gold-light'),
  onGold: v('gold-contrastText'),
  heroGradient: v('brand-heroGradient'),
  navy: brand.navy,
  azure: brand.azure,
  azureGradient: brand.azureGradient,
  goldGradient: brand.goldGradient,
} as const;
