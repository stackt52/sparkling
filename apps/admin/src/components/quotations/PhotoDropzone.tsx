'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import CircularProgress from '@mui/material/CircularProgress';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';

export const PHOTO_MAX_BYTES = 10 * 1024 * 1024;
export const PHOTO_MAX_COUNT = 10;
const ACCEPT = 'image/jpeg,image/png,image/heic,image/heif,image/webp';

/** Splits a selection into accepted files and human-readable rejections (type / size / count). */
export function vetPhotos(files: File[], existing: number): { ok: File[]; rejected: string[] } {
  const ok: File[] = [];
  const rejected: string[] = [];
  for (const f of files) {
    if (!/^image\/(jpeg|png|heic|heif|webp)$/.test(f.type)) rejected.push(`${f.name}: only JPEG, PNG or HEIC`);
    else if (f.size > PHOTO_MAX_BYTES) rejected.push(`${f.name}: larger than 10 MB`);
    else if (existing + ok.length >= PHOTO_MAX_COUNT) rejected.push(`${f.name}: at most ${PHOTO_MAX_COUNT} photos per quotation`);
    else ok.push(f);
  }
  return { ok, rejected };
}

/** Dashed "add photo" tile (README 1j) that accepts drag-and-drop or a file picker (camera on phones). */
export default function PhotoDropzone({ onFiles, count, busy, disabled, compact }: { onFiles: (files: File[]) => void; count: number; busy?: boolean; disabled?: boolean; compact?: boolean }) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [over, setOver] = React.useState(false);
  const full = count >= PHOTO_MAX_COUNT;
  const inactive = disabled || busy || full;
  const pick = (list: FileList | null) => {
    if (!list?.length) return;
    onFiles(Array.from(list));
    if (inputRef.current) inputRef.current.value = '';
  };
  return (
    <Box
      role="button"
      tabIndex={inactive ? -1 : 0}
      aria-disabled={inactive}
      aria-label={full ? 'Photo limit reached' : 'Add damage photos'}
      onClick={() => !inactive && inputRef.current?.click()}
      onKeyDown={(e) => { if (!inactive && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); inputRef.current?.click(); } }}
      onDragOver={(e) => { e.preventDefault(); if (!inactive) setOver(true); }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => { e.preventDefault(); setOver(false); if (!inactive) pick(e.dataTransfer.files); }}
      sx={{
        border: `2px dashed ${over ? tk.primary : tk.outline}`,
        borderRadius: '14px',
        bgcolor: over ? tk.primaryContainer : tk.surfaceContainer,
        color: inactive ? tk.onSurfaceVariant : tk.primary,
        display: 'flex',
        flexDirection: compact ? 'column' : 'row',
        alignItems: 'center',
        justifyContent: 'center',
        gap: compact ? 0.5 : 1.5,
        minHeight: compact ? 88 : 72,
        width: compact ? 88 : '100%',
        px: compact ? 0.5 : 2,
        py: 1,
        cursor: inactive ? 'not-allowed' : 'pointer',
        opacity: inactive ? 0.7 : 1,
        textAlign: 'center',
        transition: 'background-color 120ms, border-color 120ms',
        '&:focus-visible': { outline: `3px solid ${tk.primary}`, outlineOffset: 2 },
      }}
    >
      {busy ? <CircularProgress size={22} aria-label="Uploading" /> : <MSymbol name={full ? 'block' : 'add_a_photo'} size={compact ? 26 : 24} />}
      {compact ? (
        <Typography variant="caption" sx={{ color: 'inherit', lineHeight: 1.2 }}>{full ? 'Limit' : 'Add'}</Typography>
      ) : (
        <Box>
          <Typography variant="body2" sx={{ color: 'inherit', fontWeight: 600 }}>{full ? `Maximum ${PHOTO_MAX_COUNT} photos` : busy ? 'Uploading…' : 'Add damage photos'}</Typography>
          <Typography variant="caption" sx={{ color: tk.onSurfaceVariant }}>Drop files here or tap · JPEG, PNG or HEIC up to 10 MB · {count}/{PHOTO_MAX_COUNT}</Typography>
        </Box>
      )}
      <input ref={inputRef} type="file" accept={ACCEPT} multiple hidden onChange={(e) => pick(e.target.files)} disabled={inactive} />
    </Box>
  );
}
