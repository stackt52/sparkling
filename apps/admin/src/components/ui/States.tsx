'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Skeleton from '@mui/material/Skeleton';
import MSymbol from '@/components/MSymbol';
import IconTile from './IconTile';
import { ApiRequestError } from '@/lib/api';

export function EmptyState({ icon = 'inbox', title, description, action }: { icon?: string; title: string; description?: string; action?: React.ReactNode }) {
  return (
    <Box sx={{ py: 6, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 1.5 }}>
      <IconTile icon={icon} tone="neutral" size={56} filled={false} />
      <Typography variant="h5">{title}</Typography>
      {description && <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 420 }}>{description}</Typography>}
      {action}
    </Box>
  );
}

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const message = error instanceof ApiRequestError ? `${error.error.message}${error.error.correlation_id ? ` · ref ${error.error.correlation_id.slice(0, 8)}` : ''}` : error instanceof Error ? error.message : 'Something went wrong';
  const forbidden = error instanceof ApiRequestError && error.status === 403;
  return (
    <Box role="alert" sx={{ py: 5, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 1.5 }}>
      <IconTile icon={forbidden ? 'lock' : 'error'} tone="error" size={56} />
      <Typography variant="h5">{forbidden ? 'Not authorised' : 'Could not load'}</Typography>
      <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 460 }}>{message}</Typography>
      {onRetry && !forbidden && (
        <Button variant="outlined" size="small" onClick={onRetry} startIcon={<MSymbol name="refresh" size={18} />}>Retry</Button>
      )}
    </Box>
  );
}

export function LoadingRows({ rows = 4, height = 48 }: { rows?: number; height?: number }) {
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }} aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} variant="rounded" height={height} sx={{ borderRadius: '14px' }} />
      ))}
    </Box>
  );
}
