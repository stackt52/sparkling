/** Public runtime configuration (all values are safe for the browser bundle). */
export const env = {
  apiBaseUrl: (process.env.NEXT_PUBLIC_API_BASE_URL ?? '').replace(/\/$/, ''),
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? 'https://uicqczgpiqkczwyssdft.supabase.co',
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
  /** Demo mode is the default so the dashboard runs without a backend. */
  demoMode: (process.env.NEXT_PUBLIC_DEMO_MODE ?? 'true').toLowerCase() !== 'false',
  clientVersion: '1.0.0+1',
  /** Firebase Cloud Messaging web push certificate (VAPID public key); empty → browser push is disabled. */
  vapidKey: process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY ?? '',
} as const;

export const isDemo = () => env.demoMode;
export const hasSupabase = () => Boolean(env.supabaseUrl && env.supabaseAnonKey) && !env.demoMode;
