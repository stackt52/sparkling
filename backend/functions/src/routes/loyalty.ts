/** Loyalty (CUS-060..065). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { extractIdempotencyKey } from '../middleware/idempotency.js';
import { pagination, parseQuery, uuid } from '../lib/validate.js';
import { requireProfile, requireRole } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { ledgerBalance, redeemReward, tierRank } from '../services/loyalty.js';
import { getPublishedLoyaltyConfig, tierFor } from '../services/pricing.js';
import type { LoyaltyTier } from '../types.js';

export const loyaltyRouter = Router();
loyaltyRouter.use('/loyalty', requireProfile, requireRole('customer'));

loyaltyRouter.get(
  '/loyalty/account',
  asyncHandler(async (req, res) => {
    const db = getSupabase();
    const uid = req.auth!.uid;
    const [acctRes, cfg, sums] = await Promise.all([
      db.from('loyalty_accounts').select('*').eq('customer_id', uid).maybeSingle(),
      getPublishedLoyaltyConfig(),
      ledgerBalance(uid),
    ]);
    const acct = unwrap<Record<string, unknown> | null>(acctRes, 'account') ?? { customer_id: uid, tier: 'silver', tier_since: null };
    const tier = (acct.tier as LoyaltyTier) ?? 'silver';
    const account = { ...acct, balance_points: sums.balance, lifetime_points: sums.lifetime };
    const tierConfig = tierFor(cfg, tier);
    const sorted = [...(cfg?.tiers ?? [])].sort((a, b) => a.min_points - b.min_points);
    const next = sorted.find((t) => tierRank(t.tier) > tierRank(tier));
    res.json({
      account,
      tier_config: tierConfig,
      tiers: sorted,
      next_tier: next ? { tier: next.tier, name: next.name, points_needed: Math.max(0, next.min_points - sums.lifetime) } : null,
      published_version: cfg?.version ?? null,
      rules: cfg?.rules ?? null,
    });
  }),
);

loyaltyRouter.get(
  '/loyalty/ledger',
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination, req.query);
    const offset = decodeCursor(q.cursor);
    const db = getSupabase();
    const rows = unwrap<unknown[]>(
      await db.from('loyalty_ledger').select('*').eq('customer_id', req.auth!.uid).order('created_at', { ascending: false }).range(offset, offset + q.limit),
      'ledger',
    );
    res.json(pageResult(rows, q.limit, offset));
  }),
);

loyaltyRouter.get(
  '/loyalty/rewards',
  asyncHandler(async (req, res) => {
    const db = getSupabase();
    const uid = req.auth!.uid;
    const [rewards, acct, sums] = await Promise.all([
      db.from('rewards').select('*').eq('is_active', true).order('sort_order'),
      db.from('loyalty_accounts').select('tier').eq('customer_id', uid).maybeSingle(),
      ledgerBalance(uid),
    ]);
    const tier = ((acct.data as { tier: LoyaltyTier } | null)?.tier ?? 'silver') as LoyaltyTier;
    const data = unwrap<Array<Record<string, unknown> & { min_tier: LoyaltyTier; points_cost: number }>>(rewards, 'rewards').map((r) => ({
      ...r,
      eligible: tierRank(tier) >= tierRank(r.min_tier),
      affordable: sums.balance >= r.points_cost,
    }));
    res.json({ data, balance_points: sums.balance, tier });
  }),
);

loyaltyRouter.post(
  '/loyalty/rewards/:id/redeem',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const key = extractIdempotencyKey(req) ?? z.string().parse(req.body?.idempotency_key ?? '');
    if (!key) throw ApiError.validation('Idempotency-Key header (or client_op_id) is required for redemption');
    const result = await redeemReward(req.ctx, id, key);
    res.status(201).json(result);
  }),
);
