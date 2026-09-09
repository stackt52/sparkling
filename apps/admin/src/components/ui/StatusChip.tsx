'use client';
import Chip, { type ChipProps } from '@mui/material/Chip';
import { tk } from '@/theme/tokens';
import { statusLabel } from '@/lib/format';

export type Tone = 'primary' | 'secondary' | 'neutral' | 'success' | 'warning' | 'error' | 'errorSolid' | 'gold';

export const toneStyles: Record<Tone, { bg: string; fg: string }> = {
  primary: { bg: tk.primaryContainer, fg: tk.onPrimaryContainer },
  secondary: { bg: tk.secondaryContainer, fg: tk.onSecondaryContainer },
  neutral: { bg: tk.surfaceContainerHigh, fg: tk.onSurfaceVariant },
  success: { bg: tk.successContainer, fg: tk.onSuccessContainer },
  warning: { bg: tk.warningContainer, fg: tk.onWarningContainer },
  error: { bg: tk.errorContainer, fg: tk.onErrorContainer },
  errorSolid: { bg: tk.error, fg: 'var(--mui-palette-error-contrastText)' },
  gold: { bg: tk.goldLight, fg: tk.onGold },
};

export function toneForStatus(status: string): Tone {
  switch (status) {
    case 'in_service':
    case 'in_progress':
    case 'assigned':
      return 'primary';
    case 'confirmed':
    case 'accepted':
      return 'secondary';
    case 'completed':
    case 'verified':
    case 'successful':
    case 'converted':
    case 'published':
      return 'success';
    case 'quoted':
    case 'pending':
    case 'requested':
    case 'assessing':
    case 'draft':
      return 'warning';
    case 'blocked':
    case 'cancelled':
    case 'declined':
    case 'failed':
    case 'expired':
      return 'error';
    default:
      return 'neutral';
  }
}

interface StatusChipProps extends Omit<ChipProps, 'color'> {
  status?: string;
  tone?: Tone;
}

/** Pill chip tinted by status/tone (all status chips are pill-shaped — README). */
export default function StatusChip({ status, tone, label, sx, ...rest }: StatusChipProps) {
  const t = tone ?? toneForStatus(status ?? '');
  const s = toneStyles[t];
  return (
    <Chip
      size="small"
      label={label ?? (status ? statusLabel(status) : '')}
      sx={{ bgcolor: s.bg, color: s.fg, fontWeight: 600, ...sx }}
      {...rest}
    />
  );
}
