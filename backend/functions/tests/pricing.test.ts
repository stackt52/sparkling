import { describe, expect, it } from 'vitest';
import { applyMultiplier, computePrice, effectivePrice, estimatePoints, tierForPoints } from '../src/services/pricing.js';
import type { LoyaltyConfig, LoyaltyTierConfig } from '../src/types.js';

const gold: LoyaltyTierConfig = { tier: 'gold', name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 10 };
const silver: LoyaltyTierConfig = { tier: 'silver', name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1, discount_pct: 0 };
const platinum: LoyaltyTierConfig = { tier: 'platinum', name: 'Platinum', min_points: 2000, max_points: null, earn_multiplier: 1.5, discount_pct: 15 };

describe('pricing (CUS-020 / CUS-060..062)', () => {
  it('Gold −10% on R220 → 19800 total, 20 points pending at 0.10/R', () => {
    const q = computePrice({ basePriceCents: 22000, tier: 'gold', tierConfig: gold, pointsPerRand: 0.1 });
    expect(q.price_cents).toBe(22000);
    expect(q.discount_cents).toBe(2200);
    expect(q.total_cents).toBe(19800);
    expect(q.discount_label).toBe('Gold −10%');
    // Documented rule: points_pending = round(total_rand × points_per_rand) = round(198 × 0.10) = round(19.8) = 20.
    expect(q.points_pending).toBe(20);
    // The tier multiplier (×1.25) is applied when the earn entry is posted on verification: round(20 × 1.25) = 25.
    expect(applyMultiplier(q.points_pending, q.earn_multiplier)).toBe(25);
  });

  it('outlet price overrides base price (Sandton Full Valet R240)', () => {
    expect(effectivePrice(22000, 24000)).toBe(24000);
    expect(effectivePrice(22000, null)).toBe(22000);
    const q = computePrice({ basePriceCents: 22000, outletPriceCents: 24000, tier: 'gold', tierConfig: gold, pointsPerRand: 0.1 });
    expect(q.total_cents).toBe(21600);
    expect(q.points_pending).toBe(22);
  });

  it('Silver has no discount and no label; Platinum −15%', () => {
    const s = computePrice({ basePriceCents: 12000, tier: 'silver', tierConfig: silver, pointsPerRand: 0.1 });
    expect(s.discount_cents).toBe(0);
    expect(s.discount_label).toBeNull();
    expect(s.points_pending).toBe(12);
    const p = computePrice({ basePriceCents: 45000, tier: 'platinum', tierConfig: platinum, pointsPerRand: 0.1 });
    expect(p.discount_cents).toBe(6750);
    expect(p.total_cents).toBe(38250);
  });

  it('rounds half-up and never returns negative points', () => {
    expect(estimatePoints(10850, 0.1)).toBe(11); // 10.85 → 11
    expect(estimatePoints(10840, 0.1)).toBe(11); // 10.84 → 11
    expect(estimatePoints(10500, 0.1)).toBe(11); // 10.5 → 11 (half-up)
    expect(estimatePoints(-500, 0.1)).toBe(0);
    expect(applyMultiplier(19, 1.25)).toBe(24); // 23.75 → 24
  });

  it('maps lifetime points to tiers', () => {
    const cfg = { tiers: [silver, gold, platinum] } as LoyaltyConfig;
    expect(tierForPoints(cfg, 0)).toBe('silver');
    expect(tierForPoints(cfg, 499)).toBe('silver');
    expect(tierForPoints(cfg, 500)).toBe('gold');
    expect(tierForPoints(cfg, 2500)).toBe('platinum');
    expect(tierForPoints(null, 9999)).toBe('silver');
  });
});
