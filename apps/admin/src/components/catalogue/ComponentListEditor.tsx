'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import IconButton from '@mui/material/IconButton';
import Autocomplete from '@mui/material/Autocomplete';
import Chip from '@mui/material/Chip';
import Alert from '@mui/material/Alert';
import MSymbol from '@/components/MSymbol';
import { fonts, shape, tk } from '@/theme/tokens';
import type { ServiceComponent } from '@/lib/types';

export interface ComponentOption {
  id: string;
  code: string;
  name: string;
  /** Secondary line (group, outlet wording…). */
  hint?: string;
}

/**
 * "This service includes …" editor shared by the service drawer (global set) and the outlet
 * composition dialog: Autocomplete multi-select, ordered chips with up/down + quantity, and a
 * cycle warning (`cycleFor` returns the offending path for a candidate child, or null).
 */
export default function ComponentListEditor({ value, onChange, options, cycleFor, disabled, label = 'This service includes', emptyHint = 'No components — this is a stand-alone service.' }: {
  value: ServiceComponent[];
  onChange: (next: ServiceComponent[]) => void;
  options: ComponentOption[];
  cycleFor?: (childId: string) => string | null;
  disabled?: boolean;
  label?: string;
  emptyHint?: string;
}) {
  const byId = React.useMemo(() => new Map(options.map((o) => [o.id, o])), [options]);
  const ordered = React.useMemo(() => [...value].sort((a, b) => a.sort_order - b.sort_order), [value]);
  const selected = ordered.map((c) => byId.get(c.child_service_id)).filter((o): o is ComponentOption => Boolean(o));
  const normalise = (rows: ServiceComponent[]) => rows.map((c, i) => ({ ...c, sort_order: (i + 1) * 10 }));
  const cycles = ordered.map((c) => ({ id: c.child_service_id, path: cycleFor?.(c.child_service_id) ?? null })).filter((x) => x.path);

  const setSelection = (next: ComponentOption[]) => {
    const kept = ordered.filter((c) => next.some((o) => o.id === c.child_service_id));
    const added = next.filter((o) => !ordered.some((c) => c.child_service_id === o.id)).map((o) => ({ child_service_id: o.id, quantity: 1, sort_order: 0 }));
    onChange(normalise([...kept, ...added]));
  };
  const move = (i: number, dir: -1 | 1) => {
    const rows = [...ordered];
    const j = i + dir;
    if (j < 0 || j >= rows.length) return;
    [rows[i], rows[j]] = [rows[j], rows[i]];
    onChange(normalise(rows));
  };
  const setQty = (i: number, q: number) => onChange(normalise(ordered.map((c, k) => (k === i ? { ...c, quantity: Math.max(1, Math.round(q) || 1) } : c))));
  const remove = (i: number) => onChange(normalise(ordered.filter((_, k) => k !== i)));

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
      <Autocomplete
        multiple
        disabled={disabled}
        options={options}
        value={selected}
        onChange={(_e, next) => setSelection(next)}
        getOptionLabel={(o) => o.name}
        isOptionEqualToValue={(a, b) => a.id === b.id}
        getOptionDisabled={(o) => Boolean(cycleFor?.(o.id))}
        renderValue={() => null}
        renderOption={(props, o) => {
          const { key, ...rest } = props as React.HTMLAttributes<HTMLLIElement> & { key: string };
          const cycle = cycleFor?.(o.id);
          return (
            <li key={key} {...rest}>
              <Box sx={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>{o.name}</Typography>
                <Typography variant="caption" color="text.secondary" sx={{ fontFamily: fonts.mono }}>{o.code}{o.hint ? ` · ${o.hint}` : ''}{cycle ? ` · would create a cycle (${cycle})` : ''}</Typography>
              </Box>
            </li>
          );
        }}
        renderInput={(params) => <TextField {...params} label={label} placeholder={selected.length ? 'Add another…' : 'Search services…'} size="small" />}
      />
      {ordered.length === 0 ? (
        <Typography variant="body2" color="text.secondary">{emptyHint}</Typography>
      ) : (
        <Box component="ol" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 0.75 }} aria-label="Included services in order">
          {ordered.map((c, i) => {
            const o = byId.get(c.child_service_id);
            const cycle = cycleFor?.(c.child_service_id);
            return (
              <Box component="li" key={c.child_service_id} sx={{ display: 'flex', alignItems: 'center', gap: 1, px: 1.25, py: 0.75, borderRadius: `${shape.field}px`, bgcolor: cycle ? tk.errorContainer : tk.surfaceContainer, border: `1px solid ${cycle ? tk.error : 'transparent'}` }}>
                <Typography variant="caption" sx={{ width: 18, textAlign: 'right', color: tk.onSurfaceVariant, fontVariantNumeric: 'tabular-nums' }}>{i + 1}.</Typography>
                <Chip size="small" label={o?.name ?? c.child_service_id} sx={{ bgcolor: tk.surfaceCard, color: tk.onSurface, fontWeight: 600, maxWidth: 260 }} />
                <Typography variant="caption" color="text.secondary" sx={{ fontFamily: fonts.mono, flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{o?.code ?? ''}</Typography>
                <TextField type="number" size="small" value={c.quantity} onChange={(e) => setQty(i, Number(e.target.value))} disabled={disabled} sx={{ width: 74 }} slotProps={{ htmlInput: { min: 1, 'aria-label': `Quantity of ${o?.name ?? 'component'}`, style: { paddingTop: 6, paddingBottom: 6 } }, input: { startAdornment: <Typography variant="caption" color="text.secondary" sx={{ mr: 0.5 }}>×</Typography> } }} />
                <IconButton size="small" aria-label="Move up" disabled={disabled || i === 0} onClick={() => move(i, -1)}><MSymbol name="arrow_upward" size={18} /></IconButton>
                <IconButton size="small" aria-label="Move down" disabled={disabled || i === ordered.length - 1} onClick={() => move(i, 1)}><MSymbol name="arrow_downward" size={18} /></IconButton>
                <IconButton size="small" aria-label={`Remove ${o?.name ?? 'component'}`} disabled={disabled} onClick={() => remove(i)}><MSymbol name="close" size={18} /></IconButton>
              </Box>
            );
          })}
        </Box>
      )}
      {cycles.length > 0 && (
        <Alert severity="error" icon={<MSymbol name="sync_problem" size={20} />} sx={{ borderRadius: `${shape.field}px` }}>
          Circular composition: {cycles.map((c) => c.path).join('; ')}. Remove the loop before saving.
        </Alert>
      )}
    </Box>
  );
}

/**
 * Builds a cycle checker over a composition graph (`edges`: parent id → child ids). Returns the
 * code path that would loop back to `parentId` if `childId` were added, else null.
 */
export function makeCycleFor(parentId: string, edges: Map<string, string[]>, codeOf: (id: string) => string): (childId: string) => string | null {
  return (childId) => {
    if (childId === parentId) return `${codeOf(parentId)} → ${codeOf(parentId)}`;
    const seen = new Set<string>();
    const stack: { id: string; path: string[] }[] = [{ id: childId, path: [parentId, childId] }];
    while (stack.length) {
      const { id, path } = stack.pop()!;
      if (seen.has(id)) continue;
      seen.add(id);
      for (const next of edges.get(id) ?? []) {
        if (next === parentId) return [...path, next].map(codeOf).join(' → ');
        stack.push({ id: next, path: [...path, next] });
      }
    }
    return null;
  };
}
