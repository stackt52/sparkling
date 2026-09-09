'use client';
import { createClient, type RealtimeChannel, type SupabaseClient } from '@supabase/supabase-js';
import { env, hasSupabase } from './env';

let client: SupabaseClient | null = null;

/**
 * Supabase client authenticated with the Firebase ID token (Third-Party Auth).
 * RLS policies (migration 0001 §16) read `role` / `outlet_ids` from the token.
 */
export function getSupabase(getToken: () => Promise<string | null>): SupabaseClient | null {
  if (!hasSupabase()) return null;
  if (!client) {
    client = createClient(env.supabaseUrl, env.supabaseAnonKey, {
      accessToken: getToken,
      realtime: { params: { eventsPerSecond: 5 } },
    });
  }
  return client;
}

/** Admin realtime channels per docs/API.md (bookings, work_orders, payments, inventory_alerts, task_events). */
export const ADMIN_REALTIME_TABLES = ['bookings', 'work_orders', 'payments', 'inventory_alerts', 'task_events'] as const;

export function subscribeAdminChanges(
  sb: SupabaseClient,
  outletId: string | null,
  onChange: (table: string) => void,
): () => void {
  const channels: RealtimeChannel[] = [];
  for (const table of ADMIN_REALTIME_TABLES) {
    const filter = outletId && table !== 'task_events' ? `outlet_id=eq.${outletId}` : undefined;
    const ch = sb
      .channel(`admin:${table}:${outletId ?? 'all'}`)
      .on('postgres_changes', { event: '*', schema: 'public', table, ...(filter ? { filter } : {}) }, () =>
        onChange(table),
      )
      .subscribe();
    channels.push(ch);
  }
  return () => {
    channels.forEach((ch) => void sb.removeChannel(ch));
  };
}
