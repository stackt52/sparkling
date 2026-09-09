'use client';
import * as React from 'react';
import Paper from '@mui/material/Paper';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import type { SxProps, Theme } from '@mui/material/styles';
import { spacing } from '@/theme/tokens';

interface SectionCardProps {
  title?: React.ReactNode;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
  children?: React.ReactNode;
  sx?: SxProps<Theme>;
  /** Removes inner padding (for tables). */
  flush?: boolean;
  component?: React.ElementType;
  id?: string;
}

/** Admin card: 24px radius, flat tonal surface, optional title row. */
export default function SectionCard({ title, subtitle, actions, children, sx, flush, component = 'section', id }: SectionCardProps) {
  return (
    <Paper component={component} id={id} sx={{ p: flush ? 0 : `${spacing.cardPadding}px`, display: 'flex', flexDirection: 'column', minWidth: 0, ...sx }}>
      {(title || actions) && (
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, px: flush ? `${spacing.cardPadding}px` : 0, pt: flush ? `${spacing.cardPadding}px` : 0, mb: 1.5, flexWrap: 'wrap' }}>
          <Box sx={{ minWidth: 0 }}>
            {typeof title === 'string' ? <Typography variant="h4" component="h2">{title}</Typography> : title}
            {subtitle && <Typography variant="body2" color="text.secondary">{subtitle}</Typography>}
          </Box>
          {actions && <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>{actions}</Box>}
        </Box>
      )}
      {children}
    </Paper>
  );
}
