# Membership plans (monthly subscriptions)

Source: `Sparkling_Membership_Plans.docx` (copy in `backend/supabase/source/`). Schema: migrations
`0009_membership_tier_black` + `0010_membership_plans` (live). Demo data: `backend/supabase/seed_memberships.sql`
(run after `seed.sql` and `seed_catalogue.sql`).

**The loyalty tier is now the membership plan.** A customer without a live membership is `silver`
(free, earns points only). Subscribing to Gold / Platinum / Black sets `loyalty_accounts.tier` to the plan
tier (trigger `memberships_sync_tier`); cancelling/expiring drops it back to silver. Points earning,
the ledger and rewards are unchanged; `loyalty_configs.tiers[].discount_pct` is **0** for every tier —
all discounts come from the plan. `min_points`/`max_points` in the loyalty config are informational only
(no more points-based promotion; `refreshTier` must not upgrade tiers from points).

## Plans (as seeded)

| Plan | Tier | Fee / month | Entitlement groups | Discount |
|---|---|---|---|---|
| Gold | `gold` | R295 | **washes** (choose one): G1 = 4 × Sparkling Wash · G2 = 8 × Exterior Wash | 10 % on any **other** Sparkling service (`other_services`) |
| Platinum | `platinum` | R475 | **washes** (choose one): P1 = 8 × Sparkling Wash · P2 = 16 × Exterior Wash | 10 % on the **selected** plan services (`plan_services`) |
| Black | `black` | R850 | **washes** (choose one): B1 = 10 × Sparkling Wash · B2 = 20 × Exterior Wash<br>**detail** (choose one): B3 = 1 × Auto Detail Complete / month · B4 = 1 × Engine Steam Clean / month<br>**coating** (all): B5 = 1 × Ceramic coating / **year** | 10 % on the **selected** plan services (`plan_services`) |

Entitlement → services (`membership_entitlement_services`, any of them redeems the entitlement):
Sparkling Wash → `SPARKLING_WASH`; Exterior Wash → `EXT_WASH` (primary), `EXT_WASH_TYRE`, `WASH_GO`
(whichever the outlet sells); Auto Detail Complete → `AUTO_DETAIL_COMPLETE`; Engine Steam Clean →
`ENGINE_STEAM`; Ceramic coating → `CERAMIC_COATING` (a by-quote service: the entitlement covers the
**base** coating, the quotation is raised at R0 for that line).

Stable ids: plans `c1000000-…-00000000000{1,2,3}` (gold, platinum, black); groups `c2…0001–0005`;
entitlements `c3…0001–0009` (G1,G2,P1,P2,B1,B2,B3,B4,B5); demo memberships `c4…0001–0004`
(Thabo Gold/G1 1 of 4 used · Naledi Gold/G2 2 of 8, cash · Sipho Platinum/P1 3 of 8 · Zanele Black/B1+B3+B5,
2 washes + detail used, renewal due in 3 days); invoices `c5…0101–0104`; payments `60000000-…-0101–0104`.

## Tables (0010)

- `membership_plans(code, tier, name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, color, sort_order, is_active)`
- `membership_plan_groups(plan_id, code, name, selection: choose_one|all, sort_order)`
- `membership_plan_entitlements(group_id, code, label, quantity, period: month|year, sort_order)`
- `membership_entitlement_services(entitlement_id, service_id, is_primary)`
- `memberships(ref MEM-…, customer_id, plan_id, status: pending|active|past_due|cancelled|expired, started_at, current_period_start, current_period_end, cancel_at_period_end, cancelled_at, ended_at, next_plan_id, payment_method: card|cash|eft|sandbox, client_op_id, created_by)` — one live (pending/active/past_due) membership per customer (partial unique index).
- `membership_selections(membership_id, group_id, entitlement_id)` — the chosen option per `choose_one` group (`all` groups need no row).
- `membership_usage(membership_id, entitlement_id, booking_id, quantity ±, period_start, period_end, idempotency_key)` — **append-only**; +1 when a booking redeems, −1 release row when that booking is cancelled.
- `membership_invoices(ref MINV-…, membership_id, customer_id, period_start, period_end, amount_cents, status: pending|paid|failed|void, due_at, paid_at, payment_id, idempotency_key)`
- `payments.membership_invoice_id` (nullable; `booking_id` stays null for these) · `bookings.membership_id`, `bookings.entitlement_id`, `bookings.membership_benefit: included|discount`.
- Realtime: `memberships`, `membership_usage`, `membership_invoices` are in `supabase_realtime`.
- Templates: `membership_activated` (push+whatsapp), `membership_renewal_due` (push+whatsapp), `membership_renewed`, `membership_past_due`, `membership_cancelled` (push). Vars: `name, plan, amount, period_end, benefits`.

## Periods & allowances

- Monthly period = `[current_period_start, current_period_end)` = start + 1 calendar month. Annual entitlements
  (`period = 'year'`) use the membership year: `[anniversary, anniversary + 1 year)` where anniversary =
  `started_at` advanced by whole years to cover "now".
- `remaining = quantity − Σ usage.quantity` for rows whose `period_start` equals the current period start of
  that entitlement's period. Unused allowance does **not** roll over.
- Benefits apply only while `status = 'active'`. `past_due` keeps the tier label but pauses benefits
  (pricing treats the customer as having no plan) until the open invoice is paid.

## Pricing rules (`priceService` — backend and both demo stores must agree)

Inputs: outlet, service, vehicle size, add-ons, customer's live membership (+ plan, selections, usage).

1. No active membership → existing rules (base + add-ons, tier discount = 0 now, VAT on excl).
2. Service is one of the member's **selected** entitlements' services (or an `all`-group entitlement) and
   `remaining > 0` for the current period → `membership_benefit = 'included'`:
   `discount_cents = base_cents` (the base for that vehicle size — larger vehicles are still covered),
   add-ons still charged, `discount_label = "Included in Gold · 2 of 4 left"` (count **after** this booking),
   `total = addons (+ VAT on addons if excl)`, `points_pending` from the total as usual.
3. Otherwise the plan discount, by scope:
   - `plan_services`: service ∈ selected entitlement services (allowance used up) → `discount_pct` off base + add-ons, label `"Platinum −10%"`.
   - `other_services`: service ∉ **any** entitlement service of the plan (selected or not) → `discount_pct` off, label `"Gold −10%"`.
   - `all_services` / `none` as named.
   - Everything else: no discount.
4. `by_quote` services still 409 `{reason:'by_quote'}` — except that quotation lines for a covered
   service (Black ceramic coating with allowance) are recorded at R0 with `membership_benefit`.
5. Response adds `membership: { plan_code, plan_name, benefit: 'included'|'discount'|null, entitlement_code, remaining_after, period_end } | null`.

Booking lifecycle: a booking whose total is R 0 is created `confirmed` (nothing to pay; the payment-intent route answers 409 `nothing_to_pay`). On create with `benefit = 'included'` → insert usage `+1`
(key `booking:<id>:membership`), store `membership_id/entitlement_id/membership_benefit` on the booking.
On cancel → usage `−1` (key `booking:<id>:membership_release`). Both idempotent. Walk-in (`booking.create_walk_in`)
and sync-batch bookings go through the same code path.

## API (v1)

Customer (`requireRole('customer')`):
- `GET /memberships/plans` → `{ data: Plan[] , current_plan_code }` where `Plan = { id, code, tier, name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, color, groups: [{ id, code, name, selection, entitlements: [{ id, code, label, quantity, period, services: [{ id, code, name, is_primary }] }] }] }`.
- `GET /memberships/me` → `{ membership: Membership | null, plan: Plan | null, selections: { [group_code]: entitlement_code }, allowances: [{ entitlement_id, entitlement_code, group_code, label, quantity, used, remaining, period, period_start, period_end }], open_invoice: Invoice | null, invoices: Invoice[] (last 12), next_renewal_at, benefits_summary: string }`.
- `POST /memberships` `{ plan_code, selections: { [group_code]: entitlement_code }, payment_method: 'card', client_op_id }` → 201 `{ membership (status pending), invoice, payment: { id, client_secret } }` — the first invoice is paid through the existing sandbox flow (`POST /payments/:id/confirm` / provider webhook). When that payment turns `successful` (`payments.membership_invoice_id` set) → invoice `paid`, membership `active`, period = now → +1 month, `membership_activated` notification. 409 `conflict` if a live membership exists.
- `POST /memberships/me/invoices/:id/pay` → creates the sandbox payment intent for a pending renewal invoice (same activation on success; rolls the period, `membership_renewed`).
- `PUT /memberships/me/selections` `{ selections }` → allowed only when nothing has been used this period, else 409.
- `POST /memberships/me/change-plan` `{ plan_code, selections }` → upgrade (higher fee) applies **now**: new invoice for the full fee, new period starts on payment; downgrade sets `next_plan_id` (+ selections stored for the switch) and applies at renewal.
- `POST /memberships/me/cancel` `{ at_period_end: true }` → `cancel_at_period_end` (default) or immediate `cancelled` (benefits stop, tier → silver). `membership_cancelled`.
- `GET /loyalty/account` adds `membership: { plan_code, plan_name, status, period_end, allowances: [...] } | null`; `GET /me` adds the same `membership` summary.

Staff (`requireRole staff`, outlet-scoped like the walk-in routes):
- `GET /staff/customers/:id/membership` → same shape as `/memberships/me` for that customer.
- `POST /staff/customers/:id/membership` `{ plan_code, selections, payment_method: 'cash'|'card_terminal'|'eft', client_op_id }` → enrol at the counter: membership `active` immediately, invoice `paid`, payment row `provider = 'pos'`, `method`, `recorded_by` (same as `payment.record`). Sync-batch kind `membership.enrol` with the same payload.
- `POST /staff/memberships/:id/invoices/:invoiceId/record-payment` `{ method, client_op_id }` → pays a pending renewal at the counter (rolls the period).
- `GET /staff/customers?...` / customer summary: `loyalty` gains `plan_code`, `plan_name`, `included_remaining` (sum of remaining monthly washes) so the walk-in customer step can show "Gold · 3 washes left".

Admin (`managerPlus`; audit every write):
- `GET /admin/memberships/plans` → plans incl. `member_count`, `mrr_cents`.
- `PUT /admin/memberships/plans/:code` → `{ name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, is_active, groups: [{ code, name, selection, entitlements: [{ code, label, quantity, period, service_codes: string[] }] }] }` — full replace of groups/entitlements by code (keep ids when the code already exists so usage rows stay valid; refuse to delete an entitlement that has usage — set it inactive by removing it from new memberships only). Fee changes apply from the next invoice.
- `GET /admin/memberships?status&plan_code&q&limit&cursor` → members with plan, status, period, allowances used/remaining, open invoice.
- `GET /admin/customers/:id` adds `membership` (same as `/memberships/me`).
- `POST /admin/customers/:id/membership` (enrol, like staff), `POST /admin/memberships/:id/cancel`, `POST /admin/memberships/:id/invoices/:invoiceId/record-payment`.
- Dashboard KPIs (`GET /admin/kpis`) add `active_members`, `membership_mrr_cents`; reports add `memberships` kind (CSV: ref, customer, plan, status, period, fee, used/remaining).

Scheduled function `membershipRenewals` (daily 02:00 Africa/Johannesburg, exported from `index.ts`):
1. `cancel_at_period_end` and period ended → `expired`/`cancelled` (ended_at), tier → silver.
2. Active with `current_period_end <= now + 3 days` and no pending invoice for the next period → create the
   next invoice (`idempotency_key = renewal:<membership_id>:<period_start ISO date>`), notify `membership_renewal_due`.
3. Period ended and invoice unpaid → `past_due`, `membership_past_due`.
4. `payment_method = 'card'` in sandbox → auto-charge succeeds (creates a `successful` payment) so demo renewals roll over.
Expose the same logic as `POST /admin/memberships/run-renewals` for tests/manual runs.

## UI

Admin (`/loyalty` becomes **Membership plans**, nav label "Memberships"): plan cards (fee, entitlement groups
with OR/AND, discount rule, members, MRR) with an editor drawer (fee, discount pct/scope/note, groups → options
→ service picker from the catalogue), a **Members** tab (grid: member, plan, status chip, period, washes used /
remaining, open invoice, actions: record payment, cancel), enrol from the customer drawer, and the earn rules
section kept (points per R1, expiry, referral) minus the per-tier "Booking discount"/"Qualify" rows (replaced by
"Tier = plan"). Walk-in flow shows the customer's plan badge, "Included in Gold · 3 of 4 left" on covered
services and the plan discount on others.

Customer app: the Loyalty tab becomes **Membership** — current plan card (plan colour: gold gradient,
platinum steel, black = navy/black gradient with gold text), allowance rings/progress per entitlement
("3 of 4 Sparkling Washes left · resets 5 Oct"), renewal date + invoice state, "Pay now" for past_due,
change selection / change plan / cancel; non-members see the three plan cards with the option picker →
sandbox payment → activated. Points balance + rewards stay below as a secondary section. Booking flow: covered
services show "Included in your plan" and R 0, others the plan discount; home shows the plan pill.

Staff app: walk-in customer step shows the plan pill and remaining washes; the service step marks covered
services; **Enrol in a plan** action (plan + options + cash/card at the counter) from the customer step and
from a new "Membership" sheet; record a renewal payment when the customer is past_due.

`packages/sparkling_ui`: add `LoyaltyTierKind.black` to `TierPill` (navy `#0B1220` → `#203060` gradient, gold
text) and the matching tokens; admin `tk` gets `blackGradient`.
