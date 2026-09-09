'use client';
import Box from '@mui/material/Box';
import { tk } from '@/theme/tokens';

interface LevelBarProps {
  value: number;
  max: number;
  tone?: 'success' | 'warning' | 'error' | 'azure' | 'primary';
  height?: number;
  label?: string;
}

const fills = {
  success: tk.success,
  warning: 'color-mix(in srgb, var(--mui-palette-gold-main) 85%, #B36B00)',
  error: tk.error,
  azure: tk.azureGradient,
  primary: tk.primary,
};

/** Pill progress/level bar on a tonal track (animates on value change; respects reduced motion via theme). */
export default function LevelBar({ value, max, tone = 'success', height = 12, label }: LevelBarProps) {
  const pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  return (
    <Box
      role="progressbar"
      aria-valuenow={Math.round(value)}
      aria-valuemin={0}
      aria-valuemax={Math.round(max)}
      aria-label={label}
      sx={{ width: '100%', height, borderRadius: 999, bgcolor: tone === 'warning' ? 'color-mix(in srgb, var(--mui-palette-container-warning) 80%, transparent)' : tone === 'error' ? tk.errorContainer : tk.track, overflow: 'hidden' }}
    >
      <Box sx={{ width: `${pct}%`, height: '100%', borderRadius: 999, background: fills[tone], transition: 'width 450ms cubic-bezier(.2,.8,.2,1)' }} />
    </Box>
  );
}
