'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Button from '@mui/material/Button';
import Snackbar from '@mui/material/Snackbar';
import Alert from '@mui/material/Alert';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/lib/auth/AuthProvider';
import { onForegroundPush, pushPermission, pushQueryKeys, pushTargetPath, registerWebPush, webPushSupported, type PushData } from '@/lib/push';

interface PushState {
  /** Browser + build can do web push (secure context, service worker, VAPID key). */
  supported: boolean;
  permission: NotificationPermission | 'unsupported';
  /** Asks the browser for permission (must run from a user gesture) and registers the token. */
  enable(): Promise<void>;
}

const Ctx = React.createContext<PushState>({ supported: false, permission: 'unsupported', enable: async () => {} });

/**
 * Browser push for the dashboard (INT-003): registers this browser's FCM token with the API once the session is
 * ready and permission is granted, shows foreground pushes as a snackbar with an **Open** action, and refreshes the
 * queries behind them. Background pushes are shown by `public/firebase-messaging-sw.js`.
 */
export function PushProvider({ children }: { children: React.ReactNode }) {
  const { status, isDemo, api } = useAuth();
  const router = useRouter();
  const qc = useQueryClient();
  const [supported, setSupported] = React.useState(false);
  const [permission, setPermission] = React.useState<NotificationPermission | 'unsupported'>('unsupported');
  const [message, setMessage] = React.useState<{ title: string | null; body: string | null; data: PushData } | null>(null);
  const active = status === 'ready' && !isDemo;

  React.useEffect(() => {
    if (!active) return;
    let cancelled = false;
    void webPushSupported().then((ok) => {
      if (cancelled) return;
      setSupported(ok);
      setPermission(pushPermission());
      if (ok && pushPermission() === 'granted') registerWebPush(api).catch((e) => console.warn('Web push registration failed', e));
    });
    return () => { cancelled = true; };
  }, [active, api]);

  React.useEffect(() => {
    if (!active || !supported) return;
    let unsubscribe: (() => void) | undefined;
    void onForegroundPush((msg) => {
      for (const key of pushQueryKeys(msg.data)) void qc.invalidateQueries({ queryKey: key.filter(Boolean) });
      setMessage(msg);
    }).then((off) => { unsubscribe = off; });
    return () => unsubscribe?.();
  }, [active, supported, qc]);

  const value = React.useMemo<PushState>(() => ({
    supported,
    permission,
    async enable() {
      if (!supported) return;
      const result = await Notification.requestPermission();
      setPermission(result);
      if (result === 'granted') await registerWebPush(api);
    },
  }), [supported, permission, api]);

  return (
    <Ctx.Provider value={value}>
      {children}
      <Snackbar open={Boolean(message)} onClose={() => setMessage(null)} autoHideDuration={8000} anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}>
        <Alert
          severity="info"
          variant="filled"
          onClose={() => setMessage(null)}
          action={<Button color="inherit" size="small" onClick={() => { const m = message; setMessage(null); if (m) router.push(pushTargetPath(m.data)); }}>Open</Button>}
          sx={{ alignItems: 'center' }}
          data-testid="push-snackbar"
        >
          {[message?.title, message?.body].filter(Boolean).join(' — ')}
        </Alert>
      </Snackbar>
    </Ctx.Provider>
  );
}

export function usePush(): PushState {
  return React.useContext(Ctx);
}
