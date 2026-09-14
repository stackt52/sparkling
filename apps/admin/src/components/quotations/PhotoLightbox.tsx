'use client';
import * as React from 'react';
import Dialog from '@mui/material/Dialog';
import Box from '@mui/material/Box';
import IconButton from '@mui/material/IconButton';
import Typography from '@mui/material/Typography';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';

export interface LightboxPhoto {
  id: string;
  /** Direct URL (public page) … */
  src?: string;
  /** … or a Blob fetched through the signed-in API (drawer) / a File not yet uploaded. */
  blob?: Blob;
  caption?: string | null;
}

/** Object URL for a blob, created once per blob and revoked when it changes or on unmount. */
export function useBlobUrl(blob: Blob | null | undefined): string | null {
  const url = React.useMemo(() => (blob ? URL.createObjectURL(blob) : null), [blob]);
  React.useEffect(() => () => { if (url) URL.revokeObjectURL(url); }, [url]);
  return url;
}

function LightboxImage({ photo }: { photo: LightboxPhoto }) {
  const blobUrl = useBlobUrl(photo.blob);
  const src = photo.src ?? blobUrl;
  if (!src) return null;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt={photo.caption ?? 'Damage photo'} style={{ maxWidth: '100%', maxHeight: '78vh', borderRadius: 20, objectFit: 'contain' }} />;
}

/** Full-screen photo viewer with prev / next (arrow keys) — used by the drawer and the public quote page. */
export default function PhotoLightbox({ photos, index, onClose, onIndex }: { photos: LightboxPhoto[]; index: number | null; onClose: () => void; onIndex: (i: number) => void }) {
  const open = index !== null && index >= 0 && index < photos.length;
  const photo = open ? photos[index] : null;
  const prev = () => onIndex(((index ?? 0) - 1 + photos.length) % photos.length);
  const next = () => onIndex(((index ?? 0) + 1) % photos.length);
  return (
    <Dialog
      open={open}
      onClose={onClose}
      fullScreen
      aria-label={photo?.caption ? `Photo: ${photo.caption}` : 'Photo'}
      onKeyDown={(e) => {
        if (e.key === 'ArrowLeft') prev();
        if (e.key === 'ArrowRight') next();
      }}
      slotProps={{ paper: { sx: { bgcolor: 'rgba(8, 14, 28, 0.96)', borderRadius: 0, color: '#FFFFFF' } } }}
    >
      <Box sx={{ position: 'absolute', top: 12, right: 12, zIndex: 1 }}>
        <IconButton aria-label="Close photo" onClick={onClose} sx={{ color: '#FFFFFF', bgcolor: 'rgba(255,255,255,0.12)' }}><MSymbol name="close" /></IconButton>
      </Box>
      {photo && (
        <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2, p: { xs: 2, sm: 4 } }}>
          <LightboxImage photo={photo} />
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            {photos.length > 1 && <IconButton aria-label="Previous photo" onClick={prev} sx={{ color: '#FFFFFF', bgcolor: 'rgba(255,255,255,0.12)' }}><MSymbol name="chevron_left" /></IconButton>}
            <Typography variant="body2" sx={{ color: 'rgba(255,255,255,0.85)', textAlign: 'center' }}>
              {photo.caption ?? 'Damage photo'}{photos.length > 1 ? ` · ${(index ?? 0) + 1} of ${photos.length}` : ''}
            </Typography>
            {photos.length > 1 && <IconButton aria-label="Next photo" onClick={next} sx={{ color: '#FFFFFF', bgcolor: 'rgba(255,255,255,0.12)' }}><MSymbol name="chevron_right" /></IconButton>}
          </Box>
        </Box>
      )}
      <Box sx={{ position: 'absolute', inset: 0, zIndex: -1, bgcolor: tk.navy, opacity: 0 }} aria-hidden />
    </Dialog>
  );
}
