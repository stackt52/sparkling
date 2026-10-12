'use client';
import * as React from 'react';
import { isAdminRole, type Period } from './types';
import { useAuth } from './auth/AuthProvider';
import { useStorageValue, writeStorage } from './hooks';

/**
 * Global header filters: outlet scope + period (persisted per browser).
 *
 * Only admin-level roles (`admin`, `director`) may pick "All outlets" or any outlet. Every other dashboard role (manager, finance, supervisor)
 * is confined to the outlets linked to their account (`profile.outlet_ids`): `outletId` is always one of them
 * (the stored choice when it is linked, otherwise the first), `setOutletId` ignores anything else, and
 * `allowedOutletIds` lists what the header pill may offer. With a single linked outlet the pill is locked
 * (`outletLocked`); with several it switches between those outlets only. A non-admin with no linked outlet
 * gets `outletId: null` (the API scopes their data to their own outlets anyway).
 */
interface FiltersState {
  outletId: string | null;
  period: Period;
  /** True when the signed-in user cannot change the outlet scope (non-admin with at most one linked outlet). */
  outletLocked: boolean;
  /** Outlets the user may switch between; `null` means unrestricted (admin). */
  allowedOutletIds: string[] | null;
  setOutletId(id: string | null): void;
  setPeriod(p: Period): void;
}

const Ctx = React.createContext<FiltersState | null>(null);
const KEY = 'sparkling.admin.filters';
const PERIODS: Period[] = ['today', 'week', 'month'];

export function FiltersProvider({ children }: { children: React.ReactNode }) {
  const { role, profile } = useAuth();
  const raw = useStorageValue(KEY);
  // Outlet confinement for non-admin roles (recomputed when the session or its outlet links change).
  const linkedKey = (profile?.outlet_ids ?? []).join(',');
  const allowedOutletIds = React.useMemo(() => (role && !isAdminRole(role) ? (linkedKey ? linkedKey.split(',') : []) : null), [role, linkedKey]);
  const stored = React.useMemo(() => {
    try {
      const parsed = raw ? (JSON.parse(raw) as Partial<{ outletId: string | null; period: Period }>) : {};
      return { outletId: parsed.outletId ?? null, period: PERIODS.includes(parsed.period as Period) ? (parsed.period as Period) : 'today' };
    } catch {
      return { outletId: null, period: 'today' as Period };
    }
  }, [raw]);

  const value = React.useMemo<FiltersState>(() => {
    const confined = allowedOutletIds !== null;
    const outletId = !confined ? stored.outletId : stored.outletId && allowedOutletIds.includes(stored.outletId) ? stored.outletId : (allowedOutletIds[0] ?? null);
    return {
      outletId,
      period: stored.period,
      outletLocked: confined && allowedOutletIds.length <= 1,
      allowedOutletIds,
      setOutletId(id) {
        if (confined && (id === null || !allowedOutletIds.includes(id))) return;
        writeStorage(KEY, JSON.stringify({ outletId: id, period: stored.period }));
      },
      setPeriod(p) {
        writeStorage(KEY, JSON.stringify({ outletId: stored.outletId, period: p }));
      },
    };
  }, [stored, allowedOutletIds]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useFilters(): FiltersState {
  const ctx = React.useContext(Ctx);
  if (!ctx) throw new Error('useFilters must be used within FiltersProvider');
  return ctx;
}
