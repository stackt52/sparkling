'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import Alert from '@mui/material/Alert';
import Chip from '@mui/material/Chip';
import MSymbol from '@/components/MSymbol';
import { Logo } from '@/components/layout/NavRail';
import { useAuth } from '@/lib/auth/AuthProvider';
import { tk } from '@/theme/tokens';
import { ADMIN_ROLES } from '@/lib/types';
import { roleLabel } from '@/lib/rbac';

export default function LoginPage() {
  const { status, signInEmail, signInGoogle, continueAsDemo, isDemo, error } = useAuth();
  const router = useRouter();
  const [email, setEmail] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const [localError, setLocalError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (status === 'ready' || status === 'unauthorised') router.replace('/');
  }, [status, router]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setLocalError(null);
    try {
      await signInEmail(email, password);
    } catch (err) {
      setLocalError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  const google = async () => {
    setBusy(true);
    setLocalError(null);
    try {
      await signInGoogle();
    } catch (err) {
      setLocalError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Box sx={{ minHeight: '100vh', display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1.1fr 1fr' }, bgcolor: tk.surface }}>
      <Box sx={{ display: { xs: 'none', md: 'flex' }, flexDirection: 'column', justifyContent: 'space-between', p: 5, m: 2, borderRadius: '28px', background: tk.heroGradient, color: '#FFFFFF' }}>
        <Box sx={{ filter: 'brightness(0) invert(1)' }}><Logo height={36} /></Box>
        <Box>
          <Typography variant="overline" sx={{ opacity: 0.8 }}>Admin dashboard</Typography>
          <Typography variant="h1" sx={{ fontSize: 40, mt: 1, maxWidth: 520 }}>Every outlet, every bay, live.</Typography>
          <Typography sx={{ mt: 2, opacity: 0.85, maxWidth: 460, fontSize: 15 }}>
            Operations, quotes, loyalty configuration and stock alerts for Sparkling Sandton, Rosebank and Centurion — audited, versioned and updated in real time.
          </Typography>
          <Box sx={{ display: 'flex', gap: 1, mt: 3, flexWrap: 'wrap' }}>
            {['Realtime ops', 'Versioned loyalty', 'Stock alerts', 'CSV exports'].map((t) => (
              <Chip key={t} label={t} sx={{ bgcolor: 'rgba(255,255,255,0.14)', color: '#fff' }} />
            ))}
          </Box>
        </Box>
        <Typography variant="caption" sx={{ opacity: 0.7 }}>SRS v1.0 · ADM-001 · SEC-003</Typography>
      </Box>

      <Box sx={{ display: 'grid', placeItems: 'center', p: { xs: 2, md: 4 } }}>
        <Paper component="section" aria-labelledby="login-title" sx={{ width: '100%', maxWidth: 440, p: { xs: 3, md: 4 } }}>
          <Box sx={{ display: { xs: 'block', md: 'none' }, mb: 2 }}><Logo height={30} /></Box>
          <Typography id="login-title" variant="h2">Sign in</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 3 }}>
            Managers, admins, finance and supervisors only.
          </Typography>

          {(localError || error) && <Alert severity="error" sx={{ mb: 2 }}>{localError ?? error}</Alert>}

          {isDemo && (
            <Box sx={{ mb: 3, p: 2, borderRadius: '18px', bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer }}>
              <Typography variant="subtitle2" sx={{ mb: 1 }}>Demo mode is on — no backend required.</Typography>
              <Button fullWidth variant="contained" onClick={() => continueAsDemo('admin')} startIcon={<MSymbol name="rocket_launch" size={20} />}>
                Continue with demo admin
              </Button>
              <Box sx={{ display: 'flex', gap: 0.75, mt: 1.25, flexWrap: 'wrap' }}>
                {ADMIN_ROLES.filter((r) => r !== 'admin').map((r) => (
                  <Chip key={r} label={`as ${roleLabel[r]}`} size="small" clickable onClick={() => continueAsDemo(r)} sx={{ bgcolor: 'rgba(255,255,255,0.55)', color: tk.onPrimaryContainer }} />
                ))}
              </Box>
            </Box>
          )}

          <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
            <TextField label="E-mail" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} required fullWidth />
            <TextField label="Password" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required fullWidth />
            <Button type="submit" variant="contained" color="secondary" disabled={busy} startIcon={<MSymbol name="login" size={20} />}>
              Sign in
            </Button>
          </Box>
          <Divider sx={{ my: 2.5 }}>or</Divider>
          <Button fullWidth variant="outlined" onClick={google} disabled={busy} startIcon={<MSymbol name="account_circle" size={20} />}>
            Continue with Google
          </Button>
          <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 2.5 }}>
            After sign-in we call <code>POST /v1/auth/session</code> to claim your profile and mint role claims. Accounts without an admin role are shown a friendly “not authorised” state.
          </Typography>
        </Paper>
      </Box>
    </Box>
  );
}

function friendly(err: unknown): string {
  const code = (err as { code?: string })?.code ?? '';
  if (code.includes('invalid-credential') || code.includes('wrong-password') || code.includes('user-not-found')) return 'Incorrect e-mail or password.';
  if (code.includes('popup-closed')) return 'The Google sign-in window was closed.';
  if (code.includes('network')) return 'Network error — check your connection.';
  return err instanceof Error ? err.message : 'Sign-in failed';
}
