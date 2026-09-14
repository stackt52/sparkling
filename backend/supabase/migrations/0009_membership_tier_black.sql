-- 0009: membership plans need a fourth tier ("Black").
-- Kept in its own migration because a new enum value cannot be referenced in
-- the transaction that adds it.
alter type public.loyalty_tier add value if not exists 'black';
