'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import type { SxProps, Theme } from '@mui/material/styles';
import type { ResponsiveStyleValue } from '@mui/system';
import MSymbol from '@/components/MSymbol';
import { shape, tk } from '@/theme/tokens';

export interface RadioCardsProps<T> {
  /** Accessible name of the group. */
  label: string;
  items: T[];
  getKey: (item: T) => string;
  selected: string | null;
  onSelect: (item: T) => void;
  render: (item: T, selected: boolean) => React.ReactNode;
  /** Items that render but cannot be chosen (e.g. fully booked slots). */
  isDisabled?: (item: T) => boolean;
  /** Grid template; defaults to a single column. */
  columns?: ResponsiveStyleValue<string>;
  /** Compact chip-like cards (slots) instead of full tiles. */
  dense?: boolean;
  sx?: SxProps<Theme>;
}

/**
 * Keyboard-navigable card group with radio semantics (role="radiogroup" / role="radio",
 * roving tabindex, arrow keys move + select like native radios, Space/Enter select).
 */
export default function RadioCards<T>({ label, items, getKey, selected, onSelect, render, isDisabled, columns = '1fr', dense, sx }: RadioCardsProps<T>) {
  const refs = React.useRef<(HTMLDivElement | null)[]>([]);
  const enabled = items.map((it, i) => ({ it, i })).filter(({ it }) => !isDisabled?.(it));
  const selectedIndex = items.findIndex((it) => getKey(it) === selected);
  const firstEnabled = enabled[0]?.i ?? -1;
  const tabStop = selectedIndex >= 0 ? selectedIndex : firstEnabled;

  const move = (from: number, dir: 1 | -1) => {
    if (!enabled.length) return;
    const pos = enabled.findIndex(({ i }) => i === from);
    const next = enabled[(pos + dir + enabled.length) % enabled.length];
    onSelect(next.it);
    refs.current[next.i]?.focus();
  };

  return (
    <Box role="radiogroup" aria-label={label} sx={[{ display: 'grid', gridTemplateColumns: columns, gap: dense ? 1 : 1.25 }, ...(Array.isArray(sx) ? sx : [sx])]}>
      {items.map((item, i) => {
        const key = getKey(item);
        const isSel = key === selected;
        const disabled = Boolean(isDisabled?.(item));
        return (
          <Box
            key={key}
            ref={(el: HTMLDivElement | null) => { refs.current[i] = el; }}
            role="radio"
            aria-checked={isSel}
            aria-disabled={disabled || undefined}
            tabIndex={disabled ? -1 : i === tabStop ? 0 : -1}
            onClick={() => { if (!disabled) onSelect(item); }}
            onKeyDown={(e) => {
              if (disabled) return;
              if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); onSelect(item); }
              else if (e.key === 'ArrowDown' || e.key === 'ArrowRight') { e.preventDefault(); move(i, 1); }
              else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') { e.preventDefault(); move(i, -1); }
            }}
            sx={{
              position: 'relative',
              display: 'flex',
              alignItems: 'center',
              gap: 1.5,
              px: dense ? 1.5 : 2,
              py: dense ? 1 : 1.75,
              minHeight: dense ? 40 : 64,
              borderRadius: dense ? `${shape.pill}px` : `${shape.tile}px`,
              bgcolor: isSel ? tk.primaryContainer : tk.surfaceContainer,
              color: isSel ? tk.onPrimaryContainer : tk.onSurface,
              border: `2px solid ${isSel ? tk.primary : 'transparent'}`,
              cursor: disabled ? 'not-allowed' : 'pointer',
              opacity: disabled ? 0.55 : 1,
              textDecoration: disabled && dense ? 'line-through' : 'none',
              transition: 'background-color 120ms, border-color 120ms',
              userSelect: 'none',
              '&:hover': disabled ? undefined : { filter: 'brightness(0.97)' },
              '&:focus-visible': { outline: `3px solid ${tk.primary}`, outlineOffset: 2 },
            }}
          >
            {render(item, isSel)}
            {!dense && (
              <Box
                aria-hidden
                sx={{
                  ml: 'auto',
                  width: 26,
                  height: 26,
                  flexShrink: 0,
                  borderRadius: '50%',
                  display: 'grid',
                  placeItems: 'center',
                  bgcolor: isSel ? tk.primary : 'transparent',
                  color: tk.onPrimary,
                  border: `2px solid ${isSel ? tk.primary : tk.outline}`,
                }}
              >
                {isSel && <MSymbol name="check" size={16} weight={700} />}
              </Box>
            )}
          </Box>
        );
      })}
    </Box>
  );
}
