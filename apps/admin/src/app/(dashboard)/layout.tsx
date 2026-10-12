'use client';
import * as React from 'react';
import { usePathname, useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import CircularProgress from '@mui/material/CircularProgress';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Paper from '@mui/material/Paper';
import NextLink from 'next/link';
import AppShell from '@/components/layout/AppShell';
import { NAV_ITEMS, isActive } from '@/components/layout/nav';
import IconTile from '@/components/ui/IconTile';
import { useAuth } from '@/lib/auth/AuthProvider';
import { can, roleLabel } from '@/lib/rbac';
import { tk } from '@/theme/tokens';

/**
 * Route guard: a page reachable from the rail needs its nav item's capability, so typing a URL (e.g. `/settings`
 * or `/staff` as finance) shows a "not available for your role" state instead of the page. Paths outside the rail
 * (customer detail, outlet catalogue …) inherit the matching nav item through `match`.
 */
function PageGuard({ children }: { children: React.ReactNode }) {
  const { role } = useAuth();
  const pathname = usePathname() ?? '/';
  const item = NAV_ITEMS.find((i) => isActive(i, pathname));
  if (!item || can(role, item.cap)) return <>{children}</>;
  return (
    <Box sx={{ minHeight: '60vh', display: 'grid', placeItems: 'center', p: 3 }}>
      <Paper sx={{ p: 4, maxWidth: 460, textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }} role="alert" data-testid="page-forbidden">
        <IconTile icon="lock" tone="error" size={64} />
        <Typography variant="h2">{item.label} is not available for your role</Typography>
        <Typography color="text.secondary">{role ? `${roleLabel[role]} accounts cannot open ${item.label}.` : ''} Staff and Config are limited to admins, directors and managers.</Typography>
        <Button variant="contained" color="secondary" component={NextLink} href="/">Back to Overview</Button>
      </Paper>
    </Box>
  );
}

/** Authenticated group: redirects to /login when signed out, to /change-password on a temporary password; shows a friendly state for non-admin roles. */
export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { status, profile, signOut, error } = useAuth();
  const router = useRouter();

  React.useEffect(() => {
    if (status === 'signed_out') router.replace('/login');
    else if (status === 'password_change') router.replace('/change-password');
  }, [status, router]);

  if (status === 'loading' || status === 'signed_out' || status === 'password_change') {
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
              ? `${profile.full_name} is signed in as ${roleLabel[profile.role].toLowerCase()}. The admin dashboard is limited to managers, admins, directors, finance and supervisors.`
              : error ?? 'We could not establish an admin session for this account.'}
          </Typography>
          <Button variant="contained" color="secondary" onClick={() => void signOut()}>Sign out</Button>
        </Paper>
      </Box>
    );
  }

  return <AppShell><PageGuard>{children}</PageGuard></AppShell>;
}
