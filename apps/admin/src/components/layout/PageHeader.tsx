'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';

interface PageHeaderProps {
  title: string;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
}

/** Screen header: title + subtitle (or live chip) on the left, filter pills on the right. */
export default function PageHeader({ title, subtitle, actions }: PageHeaderProps) {
  return (
    <Box component="header" sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap', mb: 0.5 }}>
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
