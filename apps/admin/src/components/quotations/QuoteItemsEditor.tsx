'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Chip from '@mui/material/Chip';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import { QUOTE_CATEGORY_META } from './quoteCategories';
import { rands } from '@/lib/format';
import { shape, tk } from '@/theme/tokens';
import { priceLabelFor } from '@/components/catalogue/pricing';
import { QUOTE_ITEM_CATEGORIES, VAT_RATE, type OutletServiceOffer, type QuoteLineItem } from '@/lib/types';

export const emptyQuoteItem = (): QuoteLineItem => ({ label: '', description: '', category: null, service_id: null, amount_cents: 0, quantity: 1 });

export const quoteItemsTotal = (items: QuoteLineItem[]) => items.reduce((s, i) => s + (i.amount_cents || 0) * (i.quantity ?? 1), 0);

/** Items with a label (what gets sent). */
export const cleanQuoteItems = (items: QuoteLineItem[]) => items.filter((i) => i.label.trim()).map((i) => ({ ...i, label: i.label.trim(), description: i.description?.trim() || null }));

/**
 * Per-attention-area editor mirroring the staff app: category chips (selected = navy filled + check),
 * label, description, optional auto-body service and amount. Shared by the drawer's QuoteForm and the
 * Raise-quote flow.
 */
export default function QuoteItemsEditor({ items, onChange, services, disabled, showTotal = true }: {
  items: QuoteLineItem[];
  onChange: (items: QuoteLineItem[]) => void;
  /** Auto-body services offered at the outlet (already filtered to `auto_body`). */
  services?: OutletServiceOffer[];
  disabled?: boolean;
  showTotal?: boolean;
}) {
  const update = (i: number, patch: Partial<QuoteLineItem>) => onChange(items.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const total = quoteItemsTotal(items);
  /** Picking an outlet offer prefills the amount incl. VAT (excl. price × 1.15) and the label when empty. */
  const pickService = (i: number, id: string) => {
    const s = services?.find((x) => (x.service_id ?? x.id) === id);
    const cents = s ? s.price_from_cents ?? s.price_cents ?? null : null;
    const it = items[i];
    update(i, {
      service_id: id || null,
      ...(s && cents !== null && cents !== undefined ? { amount_cents: Math.round(cents * (s.vat_mode === 'excl' ? 1 + VAT_RATE : 1)) } : {}),
      ...(s && !it.label.trim() ? { label: s.name } : {}),
    });
  };
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
      {items.map((it, i) => (
        <Box key={i} component="fieldset" sx={{ border: `1px solid ${tk.outlineVariant}`, borderRadius: `${shape.frame}px`, p: 2, m: 0, display: 'flex', flexDirection: 'column', gap: 1.5, bgcolor: tk.surfaceCard }}>
          <Box component="legend" sx={{ px: 0.75, fontSize: 12.5, fontWeight: 600, color: tk.onSurfaceVariant }}>Item {i + 1}</Box>
          <Box role="group" aria-label={`Item ${i + 1} category`} sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap' }}>
            {QUOTE_ITEM_CATEGORIES.map((c) => {
              const meta = QUOTE_CATEGORY_META[c];
              const selected = it.category === c;
              return (
                <Chip
                  key={c}
                  size="small"
                  clickable
                  disabled={disabled}
                  label={meta.label}
                  icon={<MSymbol name={selected ? 'check' : meta.icon} size={15} filled />}
                  onClick={() => update(i, { category: selected ? null : c })}
                  aria-pressed={selected}
                  sx={{ bgcolor: selected ? tk.secondary : tk.surfaceContainerHigh, color: selected ? tk.onSecondary : tk.onSurface, '& .MuiChip-icon': { color: 'inherit', ml: 1 } }}
                />
              );
            })}
          </Box>
          <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
            <TextField label="Item" placeholder="e.g. Bumper repair & respray" value={it.label} onChange={(e) => update(i, { label: e.target.value })} size="small" sx={{ flex: 1 }} required disabled={disabled} slotProps={{ htmlInput: { maxLength: 120 } }} />
            <TextField label="Amount (R)" type="number" value={it.amount_cents ? it.amount_cents / 100 : ''} onChange={(e) => update(i, { amount_cents: Math.round(Number(e.target.value) * 100) })} size="small" sx={{ width: 130, flexShrink: 0 }} disabled={disabled} slotProps={{ htmlInput: { min: 0, step: 1, inputMode: 'decimal' } }} />
            <IconButton aria-label={`Remove item ${i + 1}`} onClick={() => onChange(items.filter((_, j) => j !== i))} disabled={disabled || items.length === 1} sx={{ mt: 0.25 }}>
              <MSymbol name="delete" size={20} />
            </IconButton>
          </Box>
          <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: services?.length ? 'minmax(0, 1fr) 220px' : '1fr' }, gap: 1 }}>
            <TextField label="Description (shown to the customer)" placeholder="Where the damage is and what will be done" value={it.description ?? ''} onChange={(e) => update(i, { description: e.target.value })} size="small" multiline minRows={1} maxRows={4} disabled={disabled} slotProps={{ htmlInput: { maxLength: 500 } }} />
            {services && services.length > 0 && (
              <TextField select label="Auto-body service (optional)" value={it.service_id ?? ''} onChange={(e) => pickService(i, e.target.value)} size="small" disabled={disabled} helperText={it.service_id ? 'Amount prefilled incl. VAT (outlet price × 1.15)' : 'Prefills the amount from the outlet price'} slotProps={{ select: { renderValue: (v) => services.find((s) => (s.service_id ?? s.id) === v)?.name ?? '' } }}>
                <MenuItem value=""><em>None</em></MenuItem>
                {services.map((s) => (
                  <MenuItem key={s.service_id ?? s.id} value={s.service_id ?? s.id}>
                    <Box sx={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                      <span>{s.name}</span>
                      <Typography variant="caption" color="text.secondary">{priceLabelFor(s.pricing_mode, s.vat_mode, s.price_from_cents ?? s.price_cents ?? null, { vat: false })}{s.pricing_mode !== 'by_quote' && s.vat_mode === 'excl' ? ' (excl. VAT)' : ''}</Typography>
                    </Box>
                  </MenuItem>
                ))}
              </TextField>
            )}
          </Box>
        </Box>
      ))}
      <Button size="small" variant="text" onClick={() => onChange([...items, emptyQuoteItem()])} startIcon={<MSymbol name="add" size={18} />} sx={{ alignSelf: 'flex-start' }} disabled={disabled || items.length >= 20}>
        Add item
      </Button>
      {showTotal && (
        <Tile sx={{ justifyContent: 'space-between' }}>
          <Box>
            <Typography variant="h5" component="p">Total</Typography>
            <Typography variant="caption" color="text.secondary">{cleanQuoteItems(items).length} item{cleanQuoteItems(items).length === 1 ? '' : 's'} · incl. VAT</Typography>
          </Box>
          <Typography variant="h3" sx={{ color: tk.primary, fontSize: 22, fontWeight: 700 }}>{rands(total, { decimals: true })}</Typography>
        </Tile>
      )}
    </Box>
  );
}
