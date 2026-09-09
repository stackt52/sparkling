'use client';
import * as React from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from './auth/AuthProvider';
import { useFilters } from './filters';
import { hasSupabase } from './env';
import { downloadCsv } from './csv';
import type { ReportKind } from './types';

/**
 * Live updates (ARC-003): Supabase realtime when configured, otherwise the
 * demo tick / 30 s polling. Returns the last data-update timestamp for the
 * "Live · updated hh:mm:ss" chip.
 */
export function useLive(queryKeys: string[]) {
  const { api, getToken } = useAuth();
  const { outletId } = useFilters();
  const qc = useQueryClient();
  const [updatedAt, setUpdatedAt] = React.useState<Date | null>(null);
  const keysRef = React.useRef(queryKeys);
  React.useEffect(() => {
    keysRef.current = queryKeys;
  });

  const bump = React.useCallback(() => {
    setUpdatedAt(new Date());
    keysRef.current.forEach((k) => void qc.invalidateQueries({ queryKey: [k] }));
  }, [qc]);

  // First "updated" stamp after hydration (deferred so server and client markup match).
  React.useEffect(() => {
    const t = setTimeout(() => setUpdatedAt(new Date()), 0);
    return () => clearTimeout(t);
  }, []);

  // Demo tick or nothing (http)
  React.useEffect(() => api.subscribe(() => bump()), [api, bump]);

  // Supabase realtime
  const realtime = hasSupabase();
  React.useEffect(() => {
    if (!realtime) return;
    let dispose = () => {};
    void (async () => {
      const { getSupabase, subscribeAdminChanges } = await import('./supabase');
      const sb = getSupabase(getToken);
      if (sb) dispose = subscribeAdminChanges(sb, outletId, () => bump());
    })();
    return () => dispose();
  }, [realtime, getToken, outletId, bump]);

  // Polling fallback
  React.useEffect(() => {
    if (realtime) return;
    const t = setInterval(bump, 30_000);
    return () => clearInterval(t);
  }, [realtime, bump]);

  const mode: 'realtime' | 'polling' | 'demo' = api.mode === 'demo' ? 'demo' : realtime ? 'realtime' : 'polling';
  return { updatedAt, mode, refresh: bump };
}

/** CSV export (ADM-012/063): server route when live, client-side generation in demo (same header). */
export function useExport() {
  const { api } = useAuth();
  const { outletId } = useFilters();
  const [busy, setBusy] = React.useState<ReportKind | null>(null);
  const run = React.useCallback(
    async (report: ReportKind, filters: Record<string, string | undefined> = {}) => {
      setBusy(report);
      try {
        const csv = await api.exportCsv(report, { outlet_id: outletId ?? undefined, ...filters });
        downloadCsv(`sparkling-${report}-${new Date().toISOString().slice(0, 10)}.csv`, csv);
      } finally {
        setBusy(null);
      }
    },
    [api, outletId],
  );
  return { exportCsv: run, busy };
}

/** Coarse wall-clock (default 30 s resolution) that is safe to read during render. */
const nowListeners = new Set<() => void>();
let nowTimer: ReturnType<typeof setInterval> | null = null;
function subscribeNow(cb: () => void) {
  nowListeners.add(cb);
  if (!nowTimer) nowTimer = setInterval(() => nowListeners.forEach((l) => l()), 30_000);
  return () => {
    nowListeners.delete(cb);
    if (nowListeners.size === 0 && nowTimer) {
      clearInterval(nowTimer);
      nowTimer = null;
    }
  };
}
export function useNow(resolutionMs = 30_000): number {
  return React.useSyncExternalStore(
    subscribeNow,
    () => Math.floor(Date.now() / resolutionMs) * resolutionMs,
    () => 0,
  );
}

/** Reactive localStorage value (null on the server / before hydration). */
const storageListeners = new Set<() => void>();
function subscribeStorage(cb: () => void) {
  storageListeners.add(cb);
  const onStorage = () => cb();
  window.addEventListener('storage', onStorage);
  return () => {
    storageListeners.delete(cb);
    window.removeEventListener('storage', onStorage);
  };
}
export function readStorage(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
export function writeStorage(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    /* ignore */
  }
  storageListeners.forEach((l) => l());
}
export function useStorageValue(key: string): string | null {
  return React.useSyncExternalStore(subscribeStorage, () => readStorage(key), () => null);
}

/** True while the tab is hidden (animations would never paint; charts skip them). */
function subscribeVisibility(cb: () => void) {
  document.addEventListener('visibilitychange', cb);
  return () => document.removeEventListener('visibilitychange', cb);
}
export function useDocumentHidden(): boolean {
  return React.useSyncExternalStore(subscribeVisibility, () => document.hidden, () => false);
}

/** False during SSR and the hydration render, true afterwards. */
export function useHydrated(): boolean {
  return React.useSyncExternalStore(() => () => {}, () => true, () => false);
}

export function useReducedMotion(): boolean {
  const [reduced, setReduced] = React.useState(false);
  React.useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    const on = () => setReduced(mq.matches);
    on();
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return reduced;
}

export function useToast() {
  const [toast, setToast] = React.useState<{ message: string; severity: 'success' | 'error' | 'info' } | null>(null);
  return {
    toast,
    close: () => setToast(null),
    success: (message: string) => setToast({ message, severity: 'success' }),
    error: (e: unknown) => setToast({ message: e instanceof Error ? e.message : String(e), severity: 'error' }),
    info: (message: string) => setToast({ message, severity: 'info' }),
  };
}
