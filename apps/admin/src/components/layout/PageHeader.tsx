'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import { spacing, tk } from '@/theme/tokens';
import useScrolled, { translucentSurface } from './useScrolled';

interface PageHeaderProps {
  title: string;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
}

/**
 * Screen header: title + subtitle (or live chip) on the left, filter pills on the right.
 * Sticks to the top of the scrolling main column so the title and filters stay visible
 * while the content scrolls beneath it (the nav rail is fixed by the AppShell).
 */
export default function PageHeader({ title, subtitle, actions }: PageHeaderProps) {
  const scrolled = useScrolled();
  return (
    <Box
      component="header"
      sx={{
        position: 'sticky',
        top: 0,
        zIndex: (t) => t.zIndex.appBar - 1,
        ...translucentSurface(tk.surface, scrolled),
        borderBottom: `1px solid ${scrolled ? tk.outlineVariant : 'transparent'}`,
        // Bleed into the main column's gutters so scrolling content never peeks past the edges.
        mx: { xs: -2, sm: `-${spacing.gutter}px` },
        px: { xs: 2, sm: `${spacing.gutter}px` },
        pt: { xs: 2, md: 3 },
        pb: 1.5,
        mb: -0.5,
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        gap: 2,
        flexWrap: 'wrap',
      }}
    >
      <Box sx={{ minWidth: 0 }}>
        <Typography variant="h1" component="h1" sx={{ fontSize: { xs: 26, md: 32 } }}>{title}</Typography>
        {subtitle && (
          <Typography component="div" variant="body1" color="text.secondary" sx={{ mt: 0.5, fontSize: 14.5 }}>{subtitle}</Typography>
        )}
      </Box>
      {actions && <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, flexWrap: 'wrap' }}>{actions}</Box>}
    </Box>
  );
}
