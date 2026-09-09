'use client';
import * as React from 'react';
import type { User } from 'firebase/auth';
import { env, isDemo } from '../env';
import { ADMIN_ROLES, type Profile, type UserRole } from '../types';
import { HttpApi, type AdminApi } from '../api';
import { DemoApi } from '../demo/DemoApi';
import { DEMO_PROFILES } from '../demo/data';
import { useHydrated, useStorageValue, writeStorage } from '../hooks';

export type AuthStatus = 'loading' | 'signed_out' | 'unauthorised' | 'ready';

export interface AuthState {
  status: AuthStatus;
  profile: (Profile & { outlet_ids: string[] }) | null;
  role: UserRole | null;
  isDemo: boolean;
  api: AdminApi;
  error: string | null;
  /** Firebase user (null in demo mode). */
  user: User | null;
  getToken: () => Promise<string | null>;
  signInEmail(email: string, password: string): Promise<void>;
  signInGoogle(): Promise<void>;
  continueAsDemo(role?: UserRole): void;
  switchDemoRole(role: UserRole): void;
  signOut(): Promise<void>;
}

const AuthContext = React.createContext<AuthState | null>(null);
const DEMO_KEY = 'sparkling.admin.demoRole';

let demoSingleton: DemoApi | null = null;
function getDemoApi(): DemoApi {
  if (!demoSingleton) demoSingleton = new DemoApi();
  return demoSingleton;
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const demo = isDemo();
  const [user, setUser] = React.useState<User | null>(null);
  const [profile, setProfile] = React.useState<AuthState['profile']>(null);
  const [status, setStatus] = React.useState<AuthStatus>('loading');
  const [error, setError] = React.useState<string | null>(null);

  const getToken = React.useCallback(async () => {
    if (demo) return null;
    const { getIdToken } = await import('../firebase');
    return getIdToken();
  }, [demo]);

  const api = React.useMemo<AdminApi>(() => (demo ? getDemoApi() : new HttpApi(getToken)), [demo, getToken]);

  /* -------- demo session (role persisted in localStorage, read reactively) -------- */
  const hydrated = useHydrated();
  const demoRole = useStorageValue(DEMO_KEY) as UserRole | null;
  const demoProfile = React.useMemo(() => {
    if (!demo || !demoRole) return null;
    const p = DEMO_PROFILES.find((x) => x.role === demoRole) ?? DEMO_PROFILES[0];
    return { ...p, outlet_ids: p.outlet_ids };
  }, [demo, demoRole]);
  React.useEffect(() => {
    if (demoProfile) getDemoApi().setActor(demoProfile.id);
  }, [demoProfile]);
  const applyDemoRole = React.useCallback((role: UserRole) => writeStorage(DEMO_KEY, role), []);
  const demoStatus: AuthStatus = !hydrated ? 'loading' : !demoProfile ? 'signed_out' : ADMIN_ROLES.includes(demoProfile.role) ? 'ready' : 'unauthorised';

  /* -------- firebase session -------- */
  const establishSession = React.useCallback(
    async (u: User) => {
      try {
        const http = new HttpApi(() => u.getIdToken());
        const res = await http.session({ app: 'admin', full_name: u.displayName ?? undefined });
        if (res.claims_updated) await u.getIdToken(true);
        setProfile(res.profile);
        setStatus(ADMIN_ROLES.includes(res.profile.role) ? 'ready' : 'unauthorised');
      } catch (e) {
        setError((e as Error).message);
        setProfile(null);
        setStatus('unauthorised');
      }
    },
    [],
  );

  React.useEffect(() => {
    if (demo) return;
    let unsub = () => {};
    void (async () => {
      const { getFirebaseAuth } = await import('../firebase');
      const { onAuthStateChanged } = await import('firebase/auth');
      unsub = onAuthStateChanged(getFirebaseAuth(), (u) => {
        setUser(u);
        if (u) void establishSession(u);
        else {
          setProfile(null);
          setStatus('signed_out');
        }
      });
    })();
    return () => unsub();
  }, [demo, establishSession]);

  const effectiveStatus = demo ? demoStatus : status;
  const effectiveProfile = demo ? demoProfile : profile;

  const value = React.useMemo<AuthState>(
    () => ({
      status: effectiveStatus,
      profile: effectiveProfile,
      role: effectiveProfile?.role ?? null,
      isDemo: demo,
      api,
      error,
      user,
      getToken,
      async signInEmail(email, password) {
        setError(null);
        const { signInWithEmail } = await import('../firebase');
        await signInWithEmail(email, password);
      },
      async signInGoogle() {
        setError(null);
        const { signInWithGoogle } = await import('../firebase');
        await signInWithGoogle();
      },
      continueAsDemo(role = 'admin') {
        applyDemoRole(role);
      },
      switchDemoRole(role) {
        applyDemoRole(role);
      },
      async signOut() {
        if (demo) {
          writeStorage(DEMO_KEY, null);
          return;
        }
        const { signOutFirebase } = await import('../firebase');
        await signOutFirebase();
      },
    }),
    [effectiveStatus, effectiveProfile, demo, api, error, user, getToken, applyDemoRole],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = React.useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function useApi(): AdminApi {
  return useAuth().api;
}

export const apiBaseConfigured = () => Boolean(env.apiBaseUrl);
