'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import IconButton from '@mui/material/IconButton';
import Skeleton from '@mui/material/Skeleton';
import Tooltip from '@mui/material/Tooltip';
import Typography from '@mui/material/Typography';
import { useQueries } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import PhotoLightbox, { useBlobUrl, type LightboxPhoto } from './PhotoLightbox';
import { useApi } from '@/lib/auth/AuthProvider';
import { tk } from '@/theme/tokens';
import type { QuotationAttachment } from '@/lib/types';

/** A photo not yet uploaded (Raise-quote flow) — previewed straight from the File. */
export interface PendingPhoto {
  id: string;
  file: File;
  caption?: string | null;
}

interface TileModel {
  key: string;
  blob?: Blob;
  caption: string | null;
  loading: boolean;
  error: boolean;
  remove?: () => void;
  busy: boolean;
  pendingBadge: boolean;
}

function Thumb({ t, size, onOpen }: { t: TileModel; size: number; onOpen: () => void }) {
  const src = useBlobUrl(t.blob);
  return (
    <Box role="listitem" sx={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      {t.loading ? (
        <Skeleton variant="rounded" width={size} height={size} sx={{ borderRadius: '14px' }} />
      ) : t.error || !src ? (
        <Tooltip title="Photo unavailable">
          <Box sx={{ width: size, height: size, borderRadius: '14px', background: `repeating-linear-gradient(45deg, ${tk.surfaceContainerHigh} 0 8px, ${tk.surfaceContainer} 8px 16px)`, display: 'grid', placeItems: 'center', color: tk.onSurfaceVariant }} aria-label="Photo unavailable">
            <MSymbol name="broken_image" size={26} />
          </Box>
        </Tooltip>
      ) : (
        <Box component="button" type="button" onClick={onOpen} aria-label={`Open photo${t.caption ? `: ${t.caption}` : ''}`} sx={{ p: 0, width: size, height: size, border: `1px solid ${tk.outlineVariant}`, borderRadius: '14px', overflow: 'hidden', bgcolor: tk.surfaceContainer, cursor: 'pointer', display: 'block', opacity: t.busy ? 0.5 : 1 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={src} alt={t.caption ?? 'Damage photo'} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        </Box>
      )}
      {t.pendingBadge && (
        <Typography variant="caption" sx={{ position: 'absolute', left: 6, bottom: 6, px: 0.75, borderRadius: 999, bgcolor: tk.goldLight, color: tk.onGold, fontSize: 10, fontWeight: 700 }}>New</Typography>
      )}
      {t.remove && (
        <IconButton size="small" aria-label={`Remove photo${t.caption ? ` ${t.caption}` : ''}`} onClick={t.remove} disabled={t.busy} sx={{ position: 'absolute', top: -6, right: -6, width: 24, height: 24, bgcolor: tk.error, color: 'var(--mui-palette-error-contrastText)', '&:hover': { bgcolor: tk.onErrorContainer }, border: `2px solid ${tk.surfaceCard}` }}>
          <MSymbol name="close" size={14} weight={700} />
        </IconButton>
      )}
    </Box>
  );
}

/**
 * Thumbnails (88 px, r14) for a quotation's damage photos. Uploaded photos are fetched through the
 * API with the bearer token (`GET /quotations/:id/photos/:attachmentId`) and shown via object URLs —
 * never a raw bucket URL. Click → lightbox; optional remove badge (before the customer decides).
 */
export default function QuotationPhotoGrid({ quotationId, attachments, pending = [], onRemove, onRemovePending, removing, size = 88, children }: {
  quotationId: string | null;
  attachments: QuotationAttachment[];
  pending?: PendingPhoto[];
  onRemove?: (att: QuotationAttachment) => void;
  onRemovePending?: (p: PendingPhoto) => void;
  removing?: string | null;
  size?: number;
  /** Trailing tile, e.g. the compact dropzone. */
  children?: React.ReactNode;
}) {
  const api = useApi();
  const [index, setIndex] = React.useState<number | null>(null);
  const queries = useQueries({
    queries: attachments.map((a) => ({
      queryKey: ['quotation-photo', quotationId, a.id],
      queryFn: () => api.fetchQuotationPhoto(quotationId!, a.id),
      enabled: Boolean(quotationId),
      staleTime: 60 * 60 * 1000,
      gcTime: 60 * 60 * 1000,
    })),
  });
  const tiles: TileModel[] = [
    ...attachments.map((a, i) => ({ key: a.id, blob: queries[i]?.data, caption: a.caption ?? null, loading: queries[i]?.isPending ?? false, error: queries[i]?.isError ?? false, remove: onRemove ? () => onRemove(a) : undefined, busy: removing === a.id, pendingBadge: false })),
    ...pending.map((p) => ({ key: p.id, blob: p.file, caption: p.caption ?? p.file.name, loading: false, error: false, remove: onRemovePending ? () => onRemovePending(p) : undefined, busy: false, pendingBadge: true })),
  ];
  const photos: LightboxPhoto[] = tiles.filter((t) => t.blob).map((t) => ({ id: t.key, blob: t.blob, caption: t.caption }));

  if (!tiles.length && !children) return null;
  return (
    <>
      <Box role="list" aria-label="Damage photos" sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
        {tiles.map((t) => (
          <Thumb key={t.key} t={t} size={size} onOpen={() => setIndex(photos.findIndex((p) => p.id === t.key))} />
        ))}
        {children}
      </Box>
      <PhotoLightbox photos={photos} index={index} onClose={() => setIndex(null)} onIndex={setIndex} />
    </>
  );
}
