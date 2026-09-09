'use client';
import Box from '@mui/material/Box';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';

type Tone = 'primary' | 'error' | 'warning' | 'success' | 'neutral' | 'gold' | 'azure';

const tones: Record<Tone, { bg: string; fg: string }> = {
  primary: { bg: tk.primaryContainer, fg: tk.primary },
  error: { bg: tk.errorContainer, fg: tk.onErrorContainer },
  warning: { bg: tk.warningContainer, fg: tk.onWarningContainer },
  success: { bg: tk.successContainer, fg: tk.onSuccessContainer },
  neutral: { bg: tk.surfaceContainerHigh, fg: tk.onSurfaceVariant },
  gold: { bg: tk.goldLight, fg: tk.onGold },
  azure: { bg: tk.azureGradient, fg: '#FFFFFF' },
};

/** 42px rounded icon tile (r14) per the README quick-action pattern. */
export default function IconTile({ icon, tone = 'primary', size = 42, filled = true }: { icon: string; tone?: Tone; size?: number; filled?: boolean }) {
  const t = tones[tone];
  return (
    <Box
      sx={{
        width: size,
        height: size,
        borderRadius: `${Math.round(size / 3)}px`,
        background: t.bg,
        color: t.fg,
        display: 'grid',
        placeItems: 'center',
        flexShrink: 0,
      }}
    >
      <MSymbol name={icon} filled={filled} size={Math.round(size * 0.52)} />
    </Box>
  );
}
