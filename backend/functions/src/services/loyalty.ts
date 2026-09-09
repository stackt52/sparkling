/**
 * CUS-060..065: loyalty ledger (append-only, idempotent), redemption, tier upkeep.
 * Balance is always computed from the ledger sum — never from the cache.
 */
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { newRewardCode } from '../lib/refs.js';
import { ApiError } from '../middleware/errors.js';
import type { LedgerType, LoyaltyConfig, LoyaltyTier, RequestContext } from '../types.js';
import { applyMultiplier, getPublishedLoyaltyConfig, tierFor, tierForPoints } from './pricing.js';
import { notify } from './notifications.js';

export const TIER_ORDER: LoyaltyTier[] = ['silver', 'gold', 'platinum'];

export function tierRank(t: LoyaltyTier): number {
  return TIER_ORDER.indexOf(t);
}

export async function ledgerBalance(customerId: string): Promise<{ balance: number; lifetime: number }> {
  const db = getSupabase();
  const rows = unwrap<Array<{ delta: number }>>(await db.from('loyalty_ledger').select('delta').eq('customer_id', customerId), 'ledger');
  let balance = 0;
  let lifetime = 0;
  for (const r of rows) {
    balance += Number(r.delta);
    if (r.delta > 0) lifetime += Number(r.delta);
  }
  return { balance, lifetime };
}

export interface LedgerEntryInput {
  customerId: string;
  delta: number;
  type: LedgerType;
  idempotencyKey: string;
  sourceType?: string;
  sourceId?: string | null;
  reference?: string | null;
  description?: string | null;
  createdBy?: string | null;
  expiresAt?: string | null;
}

/** Inserts a ledger row; returns `{inserted:false}` when the key already exists. */
export async function postLedger(input: LedgerEntryInput): Promise<{ inserted: boolean; id: string | null }> {
  const db = getSupabase();
  const res = await db
    .from('loyalty_ledger')
    .insert({
      customer_id: input.customerId,
      delta: input.delta,
      type: input.type,
      source_type: input.sourceType ?? null,
      source_id: input.sourceId ?? null,
      reference: input.reference ?? null,
      description: input.description ?? null,
      idempotency_key: input.idempotencyKey,
      expires_at: input.expiresAt ?? null,
      created_by: input.createdBy ?? null,
    })
    .select('id')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const existing = await db.from('loyalty_ledger').select('id').eq('idempotency_key', input.idempotencyKey).maybeSingle();
      return { inserted: false, id: (existing.data as { id: string } | null)?.id ?? null };
    }
    throw new DatabaseError(res.error, 'ledger insert');
  }
  return { inserted: true, id: (res.data as { id: string }).id };
}

/** Recomputes the tier from lifetime points against the published config. */
export async function refreshTier(customerId: string, config?: LoyaltyConfig | null): Promise<LoyaltyTier> {
  const db = getSupabase();
  const cfg = config === undefined ? await getPublishedLoyaltyConfig() : config;
  const { lifetime } = await ledgerBalance(customerId);
  const target = tierForPoints(cfg, lifetime);
  const acct = unwrap<{ tier: LoyaltyTier } | null>(
    await db.from('loyalty_accounts').select('tier').eq('customer_id', customerId).maybeSingle(),
    'loyalty account',
  );
  const current = acct?.tier ?? 'silver';
  if (tierRank(target) > tierRank(current)) {
    await db.from('loyalty_accounts').update({ tier: target, tier_since: new Date().toISOString() }).eq('customer_id', customerId);
    return target;
  }
  return current;
}

/** Earn on booking completion: idempotency key `booking:<id>:earn`. */
export async function earnForBooking(
  ctx: RequestContext,
  booking: { id: string; ref: string; customer_id: string; points_pending: number; total_cents: number },
  serviceName: string,
): Promise<{ points: number; inserted: boolean }> {
  const cfg = await getPublishedLoyaltyConfig();
  const db = getSupabase();
  const acct = unwrap<{ tier: LoyaltyTier } | null>(
    await db.from('loyalty_accounts').select('tier').eq('customer_id', booking.customer_id).maybeSingle(),
    'loyalty account',
  );
  const tier = acct?.tier ?? 'silver';
  const mult = tierFor(cfg, tier)?.earn_multiplier ?? 1;
  const points = applyMultiplier(booking.points_pending, mult);
  if (points <= 0) return { points: 0, inserted: false };
  const expiryMonths = cfg?.rules?.expiry_months;
  const expiresAt = expiryMonths ? new Date(Date.now() + expiryMonths * 30 * 86400_000).toISOString() : null;
  const res = await postLedger({
    customerId: booking.customer_id,
    delta: points,
    type: 'earn',
    idempotencyKey: `booking:${booking.id}:earn`,
    sourceType: 'booking',
    sourceId: booking.id,
    reference: booking.ref,
    description: serviceName,
    createdBy: ctx.auth.uid,
    expiresAt,
  });
  if (res.inserted) {
    const { balance } = await ledgerBalance(booking.customer_id);
    await refreshTier(booking.customer_id, cfg);
    await notify({
      recipientId: booking.customer_id,
      templateKey: 'points_posted',
      vars: { points, balance },
      dedupeKey: `points_posted:booking:${booking.id}`,
      payload: { type: 'loyalty', booking_id: booking.id },
    });
  }
  return { points, inserted: res.inserted };
}

export interface RedeemResult {
  ledger_id: string;
  redemption: { id: string; code: string; status: string; reward_id: string; created_at: string };
  balance_after: number;
}

export async function redeemReward(ctx: RequestContext, rewardId: string, idempotencyKey: string): Promise<RedeemResult> {
  const db = getSupabase();
  const uid = ctx.auth.uid;
  const reward = unwrap<{ id: string; name: string; points_cost: number; min_tier: LoyaltyTier; is_active: boolean } | null>(
    await db.from('rewards').select('*').eq('id', rewardId).maybeSingle(),
    'reward',
  );
  if (!reward || !reward.is_active) throw ApiError.notFound('Reward');

  const key = `reward:${uid}:${idempotencyKey}`;
  // Replay: return the existing redemption for this key.
  const prior = await db.from('loyalty_ledger').select('id').eq('idempotency_key', key).maybeSingle();
  if (prior.data) {
    const red = unwrap<RedeemResult['redemption'] | null>(
      await db.from('reward_redemptions').select('id, code, status, reward_id, created_at').eq('ledger_id', (prior.data as { id: string }).id).maybeSingle(),
      'redemption',
    );
    const { balance } = await ledgerBalance(uid);
    return { ledger_id: (prior.data as { id: string }).id, redemption: red!, balance_after: balance };
  }

  const acct = unwrap<{ tier: LoyaltyTier } | null>(await db.from('loyalty_accounts').select('tier').eq('customer_id', uid).maybeSingle(), 'account');
  const tier = acct?.tier ?? 'silver';
  if (tierRank(tier) < tierRank(reward.min_tier)) {
    throw ApiError.forbidden(`Reward requires ${reward.min_tier} tier`);
  }
  const { balance } = await ledgerBalance(uid);
  if (balance < reward.points_cost) {
    throw ApiError.conflict('Insufficient points', { balance, points_cost: reward.points_cost });
  }
  const code = newRewardCode();
  const ledger = await postLedger({
    customerId: uid,
    delta: -reward.points_cost,
    type: 'redeem',
    idempotencyKey: key,
    sourceType: 'reward',
    sourceId: reward.id,
    reference: code,
    description: reward.name,
    createdBy: uid,
  });
  if (!ledger.id) throw ApiError.internal('Ledger write failed');
  let redemption: RedeemResult['redemption'] | null = null;
  for (let attempt = 0; attempt < 5 && !redemption; attempt++) {
    const res = await db
      .from('reward_redemptions')
      .insert({ customer_id: uid, reward_id: reward.id, ledger_id: ledger.id, code: attempt === 0 ? code : newRewardCode() })
      .select('id, code, status, reward_id, created_at')
      .single();
    if (res.error) {
      if (res.error.code === PG_UNIQUE_VIOLATION) continue;
      throw new DatabaseError(res.error, 'redemption');
    }
    redemption = res.data as RedeemResult['redemption'];
  }
  if (!redemption) throw ApiError.internal('Could not allocate reward code');
  return { ledger_id: ledger.id, redemption, balance_after: balance - reward.points_cost };
}
