'use client';
import * as React from 'react';
import Button from '@mui/material/Button';
import CircularProgress from '@mui/material/CircularProgress';
import MSymbol from '@/components/MSymbol';
import { useApi } from '@/lib/auth/AuthProvider';
import { downloadBlob } from '@/lib/csv';
import type { Quotation } from '@/lib/types';

/** Signed-in "Download PDF" (`GET /quotations/:id/pdf` with the bearer token → `<ref>.pdf`). */
export default function DownloadPdfButton({ q, onToast, size = 'medium', variant = 'outlined' }: { q: Quotation; onToast: (kind: 'success' | 'error' | 'info', message: string | Error) => void; size?: 'small' | 'medium'; variant?: 'outlined' | 'text' }) {
  const api = useApi();
  const [busy, setBusy] = React.useState(false);
  return (
    <Button
      size={size}
      variant={variant}
      disabled={busy}
      onClick={async () => {
        setBusy(true);
        try {
          downloadBlob(`${q.ref}.pdf`, await api.fetchQuotationPdf(q.id));
        } catch (e) {
          onToast('error', e instanceof Error ? e : new Error(String(e)));
        } finally {
          setBusy(false);
        }
      }}
      startIcon={busy ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="picture_as_pdf" size={20} />}
    >
      Download PDF
    </Button>
  );
}
