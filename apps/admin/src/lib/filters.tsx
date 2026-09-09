'use client';
import * as React from 'react';
import type { Period } from './types';
import { useStorageValue, writeStorage } from './hooks';

/** Global header filters: outlet scope + period (persisted per browser). */
interface FiltersState {
  outletId: string | null;
  period: Period;
  setOutletId(id: string | null): void;
  setPeriod(p: Period): void;
}

const Ctx = React.createContext<FiltersState | null>(null);
const KEY = 'sparkling.admin.filters';
const PERIODS: Period[] = ['today', 'week', 'month'];

export function FiltersProvider({ children }: { children: React.ReactNode }) {
  const raw = useStorageValue(KEY);
  const stored = React.useMemo(() => {
    try {
      const parsed = raw ? (JSON.parse(raw) as Partial<{ outletId: string | null; period: Period }>) : {};
      return { outletId: parsed.outletId ?? null, period: PERIODS.includes(parsed.period as Period) ? (parsed.period as Period) : 'today' };
    } catch {
      return { outletId: null, period: 'today' as Period };
    }
  }, [raw]);

  const value = React.useMemo<FiltersState>(
    () => ({
      outletId: stored.outletId,
      period: stored.period,
      setOutletId(id) {
        writeStorage(KEY, JSON.stringify({ outletId: id, period: stored.period }));
      },
      setPeriod(p) {
        writeStorage(KEY, JSON.stringify({ outletId: stored.outletId, period: p }));
      },
    }),
    [stored],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useFilters(): FiltersState {
  const ctx = React.useContext(Ctx);
  if (!ctx) throw new Error('useFilters must be used within FiltersProvider');
  return ctx;
}
