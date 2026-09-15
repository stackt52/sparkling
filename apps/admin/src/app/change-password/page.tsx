'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Alert from '@mui/material/Alert';
import IconButton from '@mui/material/IconButton';
import InputAdornment from '@mui/material/InputAdornment';
import LinearProgress from '@mui/material/LinearProgress';
import CircularProgress from '@mui/material/CircularProgress';
import Link from '@mui/material/Link';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import { Logo } from '@/components/layout/NavRail';
import { ReauthRequiredError, useAuth } from '@/lib/auth/AuthProvider';
import { ApiRequestError } from '@/lib/api';
import { useToast } from '@/lib/hooks';
import { tk } from '@/theme/tokens';
import { PASSWORD_RULES, passwordStrength, passwordValid } from '@/lib/password';

/**
 * First-sign-in gate (ADM-010): shown when the session carries `must_change_password`.
 * In demo mode the page is a preview — the demo session never carries the flag and "Set password" just returns to the dashboard.
 */
export default function ChangePasswordPage() {
  const { status, profile, isDemo, changePassword, signOut } = useAuth();
  const router = useRouter();
  const toast = useToast();
  const [password, setPassword] = React.useState('');
  const [confirm, setConfirm] = React.useState('');
  const [current, setCurrent] = React.useState('');
  const [needsCurrent, setNeedsCurrent] = React.useState(false);
  const [show, setShow] = React.useState(false);
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const gated = status === 'password_change';
  React.useEffect(() => {
    if (status === 'signed_out') router.replace('/login');
    else if (!isDemo && (status === 'ready' || status === 'unauthorised')) router.replace('/');
  }, [status, isDemo, router]);

  const strength = passwordStrength(password);
  const valid = passwordValid(password) && confirm === password && (!needsCurrent || current.length > 0);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(null);
    try {
      await changePassword(password, needsCurrent ? current : undefined);
      toast.success(isDemo ? 'Demo mode — nothing to change, back to the dashboard' : 'Password updated');
      router.replace('/');
    } catch (err) {
      if (err instanceof ReauthRequiredError) {
        setNeedsCurrent(true);
        setError(err.message);
      } else setError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  if (status === 'loading' || (!gated && !isDemo)) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', bgcolor: tk.surface }} aria-busy="true">
        <CircularProgress aria-label="Loading session" />
      </Box>
    );
  }

  return (
    <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', bgcolor: tk.surface, p: { xs: 2, md: 4 } }}>
      <Paper component="section" aria-labelledby="change-password-title" sx={{ width: '100%', maxWidth: 460, p: { xs: 3, md: 4 } }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 3 }}>
          <Logo height={30} />
          <IconTile icon="password" tone="primary" size={44} />
        </Box>
        <Typography id="change-password-title" variant="h2">Set a new password</Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 3 }}>
          {profile ? `Hi ${profile.full_name.split(' ')[0]}, you` : 'You'} signed in with a temporary password. Choose a new one to continue — it works in the Sparkling Staff app and this dashboard.
        </Typography>

        {error && <Alert severity={needsCurrent && !current ? 'info' : 'error'} sx={{ mb: 2 }}>{error}</Alert>}

        <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexDirection: 'column', gap: 1.75 }}>
          {needsCurrent && (
            <TextField label="Current (temporary) password" type={show ? 'text' : 'password'} autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} required fullWidth autoFocus />
          )}
          <TextField
            label="New password"
            type={show ? 'text' : 'password'}
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            fullWidth
            autoFocus={!needsCurrent}
            slotProps={{
              input: {
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton aria-label={show ? 'Hide password' : 'Show password'} onClick={() => setShow((v) => !v)} edge="end" size="small">
                      <MSymbol name={show ? 'visibility_off' : 'visibility'} size={20} />
                    </IconButton>
                  </InputAdornment>
                ),
              },
            }}
          />
          {password && (
            <Box aria-live="polite">
              <LinearProgress variant="determinate" value={(strength.score / 4) * 100} color={strength.tone} sx={{ height: 6, borderRadius: 999 }} />
              <Typography variant="caption" sx={{ display: 'block', mt: 0.5, color: strength.tone === 'error' ? tk.error : strength.tone === 'warning' ? tk.onWarningContainer : tk.success, fontWeight: 600 }}>
                {strength.label}
              </Typography>
            </Box>
          )}
          <Box component="ul" aria-label="Password rules" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 0.5 }}>
            {PASSWORD_RULES.map((r) => {
              const ok = r.test(password);
              return (
                <Box component="li" key={r.key} sx={{ display: 'flex', alignItems: 'center', gap: 0.75, color: ok ? tk.success : tk.onSurfaceVariant, fontSize: 13 }}>
                  <MSymbol name={ok ? 'check_circle' : 'radio_button_unchecked'} filled={ok} size={18} />
                  {r.label}
                </Box>
              );
            })}
          </Box>
          <TextField
            label="Confirm new password"
            type={show ? 'text' : 'password'}
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            required
            fullWidth
            error={confirm.length > 0 && confirm !== password}
            helperText={confirm.length > 0 && confirm !== password ? 'Passwords do not match' : ' '}
          />
          <Button type="submit" variant="contained" color="secondary" disabled={busy || !valid} startIcon={<MSymbol name="lock_reset" size={20} />}>
            Set password
          </Button>
        </Box>
        <Typography variant="body2" color="text.secondary" sx={{ mt: 2.5, textAlign: 'center' }}>
          Not you?{' '}
          <Link component="button" type="button" onClick={() => void signOut().then(() => router.replace('/login'))} sx={{ fontWeight: 600 }}>
            Sign out
          </Link>
        </Typography>
      </Paper>
      <Toast toast={toast.toast} onClose={toast.close} />
    </Box>
  );
}

function friendly(err: unknown): string {
  if (err instanceof ApiRequestError && err.status === 409) return 'Your session is older than 15 minutes. Sign out, sign in with the new password and try again.';
  const code = (err as { code?: string })?.code ?? '';
  if (code.includes('weak-password')) return 'Firebase rejected that password as too weak — try a longer one.';
  if (code.includes('invalid-credential') || code.includes('wrong-password')) return 'The current password is incorrect.';
  if (code.includes('network')) return 'Network error — check your connection.';
  return err instanceof Error ? err.message : 'Could not update the password';
}
