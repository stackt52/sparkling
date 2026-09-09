'use client';
import * as React from 'react';
import Box, { type BoxProps } from '@mui/material/Box';
import { shape, tk } from '@/theme/tokens';

interface TileProps extends BoxProps {
  tone?: 'default' | 'primary' | 'error' | 'warning' | 'success' | 'gold' | 'navy';
  interactive?: boolean;
}

const tones = {
  default: { bg: tk.surfaceContainer, fg: tk.onSurface },
  primary: { bg: tk.primaryContainer, fg: tk.onPrimaryContainer },
  error: { bg: tk.errorContainer, fg: tk.onErrorContainer },
  warning: { bg: tk.warningContainer, fg: tk.onWarningContainer },
  success: { bg: tk.successContainer, fg: tk.onSuccessContainer },
  gold: { bg: 'color-mix(in srgb, var(--mui-palette-gold-light) 28%, transparent)', fg: tk.onSurface },
  navy: { bg: tk.navy, fg: '#FFFFFF' },
};

/** Tonal list tile (18px radius) used for rows inside cards. */
export default function Tile({ tone = 'default', interactive, sx, children, ...rest }: TileProps) {
  const t = tones[tone];
  return (
    <Box
      sx={{
        bgcolor: t.bg,
        color: t.fg,
        borderRadius: `${shape.tile}px`,
        px: 2,
        py: 1.5,
        display: 'flex',
        alignItems: 'center',
        gap: 1.5,
        minHeight: 56,
        ...(interactive && {
          cursor: 'pointer',
          transition: 'filter 120ms',
          '&:hover': { filter: 'brightness(0.97)' },
          '&:focus-visible': { outline: `3px solid ${tk.primary}`, outlineOffset: 2 },
        }),
        ...sx,
      }}
      {...rest}
    >
      {children}
    </Box>
  );
}
