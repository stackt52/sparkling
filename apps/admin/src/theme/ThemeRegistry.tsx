'use client';
import * as React from 'react';
import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import theme from './theme';

/**
 * Client boundary for MUI theming. The colour scheme itself is handled by
 * MUI's `colorSchemes` + `InitColorSchemeScript` (root layout), which persists
 * the choice in localStorage and follows `prefers-color-scheme` by default.
 */
export default function ThemeRegistry({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider theme={theme} defaultMode="system" noSsr={false}>
      <CssBaseline />
      {children}
    </ThemeProvider>
  );
}
