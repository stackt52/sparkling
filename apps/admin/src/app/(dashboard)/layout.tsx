'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import CircularProgress from '@mui/material/CircularProgress';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Paper from '@mui/material/Paper';
import AppShell from '@/components/layout/AppShell';
import IconTile from '@/components/ui/IconTile';
import { useAuth } from '@/lib/auth/AuthProvider';
import { roleLabel } from '@/lib/rbac';
import { tk } from '@/theme/tokens';

/** Authenticated group: redirects to /login when signed out; shows a friendly state for non-admin roles. */
export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { status, profile, signOut, error } = useAuth();
  const router = useRouter();

  React.useEffect(() => {
    if (status === 'signed_out') router.replace('/login');
  }, [status, router]);

  if (status === 'loading' || status === 'signed_out') {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', bgcolor: tk.surface }} aria-busy="true">
        <CircularProgress aria-label="Loading session" />
      </Box>
    );
  }

  if (status === 'unauthorised') {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', bgcolor: tk.surface, p: 3 }}>
        <Paper sx={{ p: 4, maxWidth: 460, textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }} role="alert">
          <IconTile icon="lock" tone="error" size={64} />
          <Typography variant="h2">Not authorised</Typography>
          <Typography color="text.secondary">
            {profile
              ? `${profile.full_name} is signed in as ${roleLabel[profile.role].toLowerCase()}. The admin dashboard is limited to managers, admins, finance and supervisors.`
              : error ?? 'We could not establish an admin session for this account.'}
          </Typography>
          <Button variant="contained" color="secondary" onClick={() => void signOut()}>Sign out</Button>
        </Paper>
      </Box>
    );
  }

  return <AppShell>{children}</AppShell>;
}
