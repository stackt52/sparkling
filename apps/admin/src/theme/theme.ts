'use client';
import { createTheme } from '@mui/material/styles';
import type { PaletteOptions } from '@mui/material/styles';
import { brand, darkTokens, fonts, lightTokens, shape, tk, type SchemeTokens } from './tokens';

/* ---------- palette augmentation (typed custom tokens) ---------- */
interface SurfaceTokens {
  main: string;
  card: string;
  container: string;
  containerHigh: string;
  on: string;
  onVariant: string;
  outline: string;
  outlineVariant: string;
  track: string;
}
interface ContainerTokens {
  primary: string;
  onPrimary: string;
  secondary: string;
  onSecondary: string;
  error: string;
  onError: string;
  success: string;
  onSuccess: string;
  warning: string;
  onWarning: string;
}
interface GoldTokens {
  main: string;
  light: string;
  contrastText: string;
}
interface BrandTokens {
  navy: string;
  azure: string;
  heroGradient: string;
}

declare module '@mui/material/styles' {
  interface Palette {
    surface: SurfaceTokens;
    container: ContainerTokens;
    gold: GoldTokens;
    brand: BrandTokens;
  }
  interface PaletteOptions {
    surface?: SurfaceTokens;
    container?: ContainerTokens;
    gold?: GoldTokens;
    brand?: BrandTokens;
  }
}

function paletteFrom(t: SchemeTokens, mode: 'light' | 'dark'): PaletteOptions {
  return {
    mode,
    primary: { main: t.primary, contrastText: t.onPrimary },
    secondary: { main: t.secondary, contrastText: t.onSecondary },
    error: { main: t.error, contrastText: mode === 'light' ? '#FFFFFF' : '#5C1900' },
    success: { main: t.success, contrastText: mode === 'light' ? '#FFFFFF' : '#00391B' },
    warning: { main: t.gold, contrastText: t.onGold },
    info: { main: brand.azure, contrastText: '#FFFFFF' },
    background: { default: t.surface, paper: t.surfaceCard },
    text: { primary: t.onSurface, secondary: t.onSurfaceVariant },
    divider: t.outlineVariant,
    surface: {
      main: t.surface,
      card: t.surfaceCard,
      container: t.surfaceContainer,
      containerHigh: t.surfaceContainerHigh,
      on: t.onSurface,
      onVariant: t.onSurfaceVariant,
      outline: t.outline,
      outlineVariant: t.outlineVariant,
      track: t.track,
    },
    container: {
      primary: t.primaryContainer,
      onPrimary: t.onPrimaryContainer,
      secondary: t.secondaryContainer,
      onSecondary: t.onSecondaryContainer,
      error: t.errorContainer,
      onError: t.onErrorContainer,
      success: t.successContainer,
      onSuccess: t.onSuccessContainer,
      warning: t.warningContainer,
      onWarning: t.onWarningContainer,
    },
    gold: { main: t.gold, light: t.goldLight, contrastText: t.onGold },
    brand: { navy: brand.navy, azure: brand.azure, heroGradient: t.heroGradient },
  };
}

const theme = createTheme({
  cssVariables: { colorSchemeSelector: 'data', cssVarPrefix: 'mui' },
  colorSchemes: {
    light: { palette: paletteFrom(lightTokens, 'light') },
    dark: { palette: paletteFrom(darkTokens, 'dark') },
  },
  shape: { borderRadius: shape.frame },
  typography: {
    fontFamily: fonts.sans,
    h1: { fontWeight: 700, fontSize: 34, lineHeight: 1.1, letterSpacing: '-0.01em' },
    h2: { fontWeight: 600, fontSize: 22, lineHeight: 1.2 },
    h3: { fontWeight: 600, fontSize: 19, lineHeight: 1.25 },
    h4: { fontWeight: 600, fontSize: 16, lineHeight: 1.3 },
    h5: { fontWeight: 600, fontSize: 14.5, lineHeight: 1.35 },
    h6: { fontWeight: 600, fontSize: 13.5, lineHeight: 1.4 },
    subtitle1: { fontWeight: 500, fontSize: 14, lineHeight: 1.45 },
    subtitle2: { fontWeight: 600, fontSize: 12.5, lineHeight: 1.45 },
    body1: { fontWeight: 400, fontSize: 13.5, lineHeight: 1.55 },
    body2: { fontWeight: 400, fontSize: 12.5, lineHeight: 1.55 },
    caption: { fontWeight: 500, fontSize: 11.5, lineHeight: 1.4 },
    overline: {
      fontWeight: 600,
      fontSize: 10.5,
      lineHeight: 1.4,
      letterSpacing: '0.06em',
      textTransform: 'uppercase',
    },
    button: { fontWeight: 600, fontSize: 14, textTransform: 'none', letterSpacing: 0 },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        html: { height: '100%' },
        body: {
          minHeight: '100%',
          backgroundColor: tk.surface,
          color: tk.onSurface,
          WebkitFontSmoothing: 'antialiased',
          MozOsxFontSmoothing: 'grayscale',
        },
        '*:focus-visible': {
          outline: `3px solid ${tk.primary}`,
          outlineOffset: 2,
          borderRadius: 8,
        },
        '.mono': { fontFamily: fonts.mono, fontVariantNumeric: 'tabular-nums' },
        '@media (prefers-reduced-motion: reduce)': {
          '*, *::before, *::after': {
            animationDuration: '0.001ms !important',
            animationIterationCount: '1 !important',
            transitionDuration: '0.001ms !important',
            scrollBehavior: 'auto !important',
          },
        },
      },
    },
    MuiPaper: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: {
          backgroundImage: 'none',
          backgroundColor: tk.surfaceCard,
          borderRadius: shape.card,
          border: `1px solid ${tk.outlineVariant}`,
        },
      },
    },
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: {
          borderRadius: shape.pill,
          fontWeight: 600,
          padding: '9px 20px',
          minHeight: 44,
          '&.MuiButton-sizeSmall': { minHeight: 36, padding: '5px 14px', fontSize: 13 },
        },
        outlined: { borderColor: tk.outline },
      },
    },
    MuiIconButton: {
      styleOverrides: { root: { borderRadius: shape.pill } },
    },
    MuiChip: {
      styleOverrides: {
        root: { borderRadius: shape.pill, fontWeight: 600, fontSize: 12.5, height: 30 },
        sizeSmall: { height: 26, fontSize: 12 },
        label: { paddingLeft: 12, paddingRight: 12 },
      },
    },
    MuiOutlinedInput: {
      styleOverrides: {
        root: {
          borderRadius: shape.field,
          backgroundColor: tk.surfaceContainer,
          '& .MuiOutlinedInput-notchedOutline': { borderColor: 'transparent' },
          '&:hover .MuiOutlinedInput-notchedOutline': { borderColor: tk.outline },
          '&.Mui-focused .MuiOutlinedInput-notchedOutline': { borderColor: tk.primary, borderWidth: 2 },
        },
      },
    },
    MuiDialog: {
      styleOverrides: { paper: { borderRadius: shape.dialog, border: 'none' } },
    },
    MuiDrawer: {
      styleOverrides: { paper: { borderRadius: 0, border: 'none', backgroundColor: tk.surfaceCard } },
    },
    MuiMenu: {
      styleOverrides: { paper: { borderRadius: 16, marginTop: 6, minWidth: 200 } },
    },
    MuiMenuItem: {
      styleOverrides: { root: { borderRadius: 12, margin: '2px 6px', fontSize: 13.5 } },
    },
    MuiTooltip: {
      styleOverrides: { tooltip: { borderRadius: 10, fontSize: 12 } },
    },
    MuiTableCell: {
      styleOverrides: {
        root: { borderBottomColor: tk.outlineVariant, fontSize: 13.5, padding: '12px 14px' },
        head: {
          fontWeight: 600,
          fontSize: 11.5,
          letterSpacing: '0.06em',
          textTransform: 'uppercase',
          color: tk.onSurfaceVariant,
        },
      },
    },
    MuiTab: {
      styleOverrides: { root: { textTransform: 'none', fontWeight: 600, minHeight: 44 } },
    },
    MuiTabs: { styleOverrides: { root: { minHeight: 44 } } },
    MuiLinearProgress: {
      styleOverrides: { root: { borderRadius: shape.pill, backgroundColor: tk.track } },
    },
    MuiAlert: { styleOverrides: { root: { borderRadius: 16 } } },
    MuiSnackbarContent: { styleOverrides: { root: { borderRadius: 16 } } },
  },
});

export default theme;
