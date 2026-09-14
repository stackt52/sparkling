'use client';
import Chip, { type ChipProps } from '@mui/material/Chip';
import Box from '@mui/material/Box';
import { tk } from '@/theme/tokens';
import type { LoyaltyTier } from '@/lib/types';

export const TIER_NAME: Record<LoyaltyTier, string> = { silver: 'Silver', gold: 'Gold', platinum: 'Platinum', black: 'Black' };

/** Plan colours (docs/MEMBERSHIPS.md UI): gold gradient, platinum steel, black = navy/black gradient with gold text. */
export const tierStyle: Record<LoyaltyTier, { background: string; color: string; border?: string }> = {
  silver: { background: tk.surfaceContainerHigh, color: tk.onSurfaceVariant },
  gold: { background: tk.goldGradient, color: tk.onGold },
  platinum: { background: tk.platinumGradient, color: '#FFFFFF' },
  black: { background: tk.blackGradient, color: tk.onBlack },
};

interface TierChipProps extends Omit<ChipProps, 'color' | 'label'> {
  tier: LoyaltyTier;
  /** Defaults to the tier name; pass e.g. "Gold · 3 washes left". */
  label?: React.ReactNode;
}

/** Pill chip painted in the plan colour (tier = membership plan). */
export default function TierChip({ tier, label, sx, ...rest }: TierChipProps) {
  const s = tierStyle[tier];
  return <Chip size="small" label={label ?? TIER_NAME[tier]} sx={{ background: s.background, color: s.color, fontWeight: 700, '& .MuiChip-icon': { color: 'inherit' }, ...sx }} {...rest} />;
}

/** Small round swatch in the plan colour (plan cards, legends). */
export function TierDot({ tier, size = 22, ring }: { tier: LoyaltyTier; size?: number; ring?: boolean }) {
  const s = tierStyle[tier];
  return <Box component="span" aria-hidden sx={{ display: 'inline-block', width: size, height: size, borderRadius: '50%', background: s.background, flexShrink: 0, boxShadow: ring ? `0 0 0 3px color-mix(in srgb, ${tk.gold} 30%, transparent)` : 'none' }} />;
}
