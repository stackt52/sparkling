/** NFR-013 feature flags with a short in-process cache. */
import { getSupabase } from '../lib/supabase.js';

const TTL_MS = 15_000;
let cache: { at: number; flags: Record<string, boolean> } | null = null;

export async function getFlags(force = false): Promise<Record<string, boolean>> {
  if (!force && cache && Date.now() - cache.at < TTL_MS) return cache.flags;
  const db = getSupabase();
  const { data, error } = await db.from('feature_flags').select('key, enabled');
  if (error) return cache?.flags ?? {};
  const flags: Record<string, boolean> = {};
  for (const row of (data ?? []) as Array<{ key: string; enabled: boolean }>) flags[row.key] = !!row.enabled;
  cache = { at: Date.now(), flags };
  return flags;
}

export async function flagEnabled(key: string): Promise<boolean> {
  const flags = await getFlags();
  return flags[key] === true;
}

export function invalidateFlags(): void {
  cache = null;
}
