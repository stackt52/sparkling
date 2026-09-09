'use client';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';

export default function Toast({ toast, onClose }: { toast: { message: string; severity: 'success' | 'error' | 'info' } | null; onClose: () => void }) {
  return (
    <Snackbar open={Boolean(toast)} autoHideDuration={4000} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
      <Alert onClose={onClose} severity={toast?.severity ?? 'info'} variant="filled" sx={{ borderRadius: 999, fontWeight: 500 }}>
        {toast?.message}
      </Alert>
    </Snackbar>
  );
}
