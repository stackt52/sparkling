'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import { useApi } from '@/lib/auth/AuthProvider';
import { ApiRequestError } from '@/lib/api';
import { copyText } from '@/lib/clipboard';
import { fmtDate } from '@/lib/format';
import { useNow } from '@/lib/hooks';
import { fonts, tk } from '@/theme/tokens';
import type { Quotation } from '@/lib/types';

const SHARE_COOLDOWN_MS = 60_000;
/** Cooldown survives closing / reopening the drawer (the API rate-limits 1/min per quotation). */
const cooldowns = new Map<string, number>();

export function useShareCooldown(quotationId: string) {
  const now = useNow(1_000);
  const until = cooldowns.get(quotationId) ?? 0;
  const remaining = now === 0 ? 0 : Math.min(SHARE_COOLDOWN_MS / 1000, Math.max(0, Math.ceil((until - now) / 1000)));
  return { remaining, start: (ms = SHARE_COOLDOWN_MS) => cooldowns.set(quotationId, Date.now() + ms) };
}

/**
 * "Public link" row: the `/q/<token>` URL the customer received, with Copy · Open · Resend WhatsApp
 * (`POST /quotations/:id/share`, 60 s cooldown). Read-only roles get Copy / Open only.
 */
export default function PublicLinkRow({ q, canShare, onToast }: { q: Quotation; canShare: boolean; onToast: (kind: 'success' | 'error' | 'info', message: string | Error) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  // A fresh share result wins until the quotation query refetches with the same link.
  const [shared, setShared] = React.useState<{ id: string; url: string; expires_at: string } | null>(null);
  const link = shared && shared.id === q.id && shared.url !== q.public_url ? { url: shared.url, expires_at: shared.expires_at } : { url: q.public_url ?? null, expires_at: q.public_token_expires_at ?? null };
  const { remaining, start } = useShareCooldown(q.id);

  const share = useMutation({
    mutationFn: () => api.shareQuotation(q.id),
    onSuccess: (res) => {
      setShared({ id: q.id, url: res.public_url, expires_at: res.expires_at });
      start();
      onToast('success', `${link.url ? 'Re-sent' : 'Sent'} to ${q.customer_name.split(' ')[0]} on WhatsApp`);
      void qc.invalidateQueries({ queryKey: ['quotation', q.id] });
    },
    onError: (e) => {
      if (e instanceof ApiRequestError && e.status === 429) {
        const secs = Number(/(\d+)\s*s/.exec(e.error.message)?.[1]) || 60;
        start(secs * 1000);
      }
      onToast('error', e instanceof Error ? e : new Error(String(e)));
    },
  });

  const copy = async () => {
    if (!link.url) return;
    if (await copyText(link.url)) onToast('success', 'Public link copied');
    else onToast('error', new Error('Could not copy the link — select it and copy manually'));
  };

  const shareLabel = share.isPending ? 'Sending…' : remaining > 0 ? `Resend in ${remaining} s` : link.url ? 'Resend WhatsApp' : 'Send link';
  return (
    <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
        <Typography variant="h6" component="p" sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
          <MSymbol name="link" size={18} />Public link
        </Typography>
        {link.expires_at && <Typography variant="caption" color="text.secondary">Expires {fmtDate(link.expires_at, 'd MMM yyyy')}</Typography>}
      </Box>
      {link.url ? (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          <Typography component="code" sx={{ fontFamily: fonts.mono, fontSize: 12.5, flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: tk.primary }} title={link.url}>{link.url}</Typography>
          <Tooltip title="Copy link"><IconButton size="small" aria-label="Copy public link" onClick={copy}><MSymbol name="content_copy" size={18} /></IconButton></Tooltip>
          <Tooltip title="Open in new tab"><IconButton size="small" aria-label="Open public link" component="a" href={link.url} target="_blank" rel="noopener"><MSymbol name="open_in_new" size={18} /></IconButton></Tooltip>
        </Box>
      ) : (
        <Typography variant="body2" color="text.secondary">Not shared yet — send the link to the customer on WhatsApp.</Typography>
      )}
      {canShare && (
        <Button size="small" variant={link.url ? 'outlined' : 'contained'} color="secondary" onClick={() => share.mutate()} disabled={share.isPending || remaining > 0} startIcon={share.isPending ? <CircularProgress size={14} color="inherit" /> : <MSymbol name="send" size={18} />} sx={{ alignSelf: 'flex-start' }}>
          {shareLabel}
        </Button>
      )}
    </Tile>
  );
}
