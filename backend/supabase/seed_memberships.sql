-- Membership demo data + entitlement→service mapping.
-- Run AFTER seed.sql and seed_catalogue.sql (seed.sql truncates profiles and
-- services with CASCADE, which empties memberships and the service mapping).
-- Plans, groups and entitlements themselves live in migration 0010.
begin;

-- ---------- Entitlement → service mapping (idempotent) -----------------------
with map(ent, code, is_primary) as (values
  ('c3000000-0000-4000-8000-000000000001'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000003'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000005'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000002'::uuid,'EXT_WASH',true), ('c3000000-0000-4000-8000-000000000002'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000002'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000004'::uuid,'EXT_WASH',true), ('c3000000-0000-4000-8000-000000000004'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000004'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000006'::uuid,'EXT_WASH',true), ('c3000000-0000-4000-8000-000000000006'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000006'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000007'::uuid,'AUTO_DETAIL_COMPLETE',true),
  ('c3000000-0000-4000-8000-000000000008'::uuid,'ENGINE_STEAM',true),
  ('c3000000-0000-4000-8000-000000000009'::uuid,'CERAMIC_COATING',true)
)
insert into public.membership_entitlement_services (entitlement_id, service_id, is_primary)
select m.ent, s.id, m.is_primary from map m join public.services s on s.code = m.code
on conflict (entitlement_id, service_id) do update set is_primary = excluded.is_primary;

-- ---------- Demo memberships --------------------------------------------------
-- Thabo  → Gold     (G1: 4 × Sparkling Wash), 1 used this month, card
-- Naledi → Gold     (G2: 8 × Exterior Wash), 2 used, cash at the counter
-- Sipho  → Platinum (P1: 8 × Sparkling Wash), 3 used, card
-- Zanele → Black    (B1 washes + B3 detail, B5 coating), 2 washes + detail used, card; renewal due in 3 days
-- membership_usage is append-only, so this file upserts instead of deleting.

insert into public.memberships (id, ref, customer_id, plan_id, status, started_at, current_period_start, current_period_end, payment_method, client_op_id, created_by, created_at) values
 ('c4000000-0000-4000-8000-000000000001','MEM-2026-0001','seed_thabo', 'c1000000-0000-4000-8000-000000000001','active', now() - interval '95 days',  now() - interval '5 days',  now() - interval '5 days'  + interval '1 month', 'card', 'seed-mem-thabo',  'seed_thabo',  now() - interval '95 days'),
 ('c4000000-0000-4000-8000-000000000002','MEM-2026-0002','seed_naledi','c1000000-0000-4000-8000-000000000001','active', now() - interval '60 days',  now() - interval '12 days', now() - interval '12 days' + interval '1 month', 'cash', 'seed-mem-naledi', 'seed_johan',  now() - interval '60 days'),
 ('c4000000-0000-4000-8000-000000000003','MEM-2026-0003','seed_sipho', 'c1000000-0000-4000-8000-000000000002','active', now() - interval '150 days', now() - interval '20 days', now() - interval '20 days' + interval '1 month', 'card', 'seed-mem-sipho',  'seed_sipho',  now() - interval '150 days'),
 ('c4000000-0000-4000-8000-000000000004','MEM-2026-0004','seed_zanele','c1000000-0000-4000-8000-000000000003','active', now() - interval '27 days', now() - interval '27 days', now() + interval '3 days', 'card', 'seed-mem-zanele', 'seed_zanele', now() - interval '27 days')
on conflict (id) do update set plan_id = excluded.plan_id, status = excluded.status, current_period_start = excluded.current_period_start, current_period_end = excluded.current_period_end;

insert into public.membership_selections (membership_id, group_id, entitlement_id) values
 ('c4000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000001'),
 ('c4000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002'),
 ('c4000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000002','c3000000-0000-4000-8000-000000000003'),
 ('c4000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000003','c3000000-0000-4000-8000-000000000005'),
 ('c4000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000004','c3000000-0000-4000-8000-000000000007')
on conflict (membership_id, group_id) do update set entitlement_id = excluded.entitlement_id;

insert into public.membership_usage (membership_id, entitlement_id, booking_id, quantity, period_start, period_end, idempotency_key, created_by, created_at)
select m.id, u.ent, null, 1, m.current_period_start, m.current_period_end, u.key, m.customer_id, m.current_period_start + u.offset_days * interval '1 day'
from (values
  ('c4000000-0000-4000-8000-000000000001'::uuid,'c3000000-0000-4000-8000-000000000001'::uuid,'seed-use-thabo-1',  2),
  ('c4000000-0000-4000-8000-000000000002'::uuid,'c3000000-0000-4000-8000-000000000002'::uuid,'seed-use-naledi-1', 3),
  ('c4000000-0000-4000-8000-000000000002'::uuid,'c3000000-0000-4000-8000-000000000002'::uuid,'seed-use-naledi-2', 9),
  ('c4000000-0000-4000-8000-000000000003'::uuid,'c3000000-0000-4000-8000-000000000003'::uuid,'seed-use-sipho-1',  4),
  ('c4000000-0000-4000-8000-000000000003'::uuid,'c3000000-0000-4000-8000-000000000003'::uuid,'seed-use-sipho-2', 11),
  ('c4000000-0000-4000-8000-000000000003'::uuid,'c3000000-0000-4000-8000-000000000003'::uuid,'seed-use-sipho-3', 17),
  ('c4000000-0000-4000-8000-000000000004'::uuid,'c3000000-0000-4000-8000-000000000005'::uuid,'seed-use-zanele-1', 6),
  ('c4000000-0000-4000-8000-000000000004'::uuid,'c3000000-0000-4000-8000-000000000005'::uuid,'seed-use-zanele-2',20),
  ('c4000000-0000-4000-8000-000000000004'::uuid,'c3000000-0000-4000-8000-000000000007'::uuid,'seed-use-zanele-3',14)
) as u(mid, ent, key, offset_days)
join public.memberships m on m.id = u.mid
on conflict (idempotency_key) do nothing;

-- Current-period invoices, all paid (Zanele's next one is created by the renewal job 3 days before period end).
insert into public.membership_invoices (id, ref, membership_id, customer_id, period_start, period_end, amount_cents, status, due_at, paid_at, idempotency_key, created_at)
select i.id, i.ref, m.id, m.customer_id, m.current_period_start, m.current_period_end, p.monthly_fee_cents, 'paid', m.current_period_start, m.current_period_start, i.key, m.current_period_start
from (values
  ('c5000000-0000-4000-8000-000000000001'::uuid,'MINV-2026-0101','c4000000-0000-4000-8000-000000000001'::uuid,'seed-minv-thabo-cur'),
  ('c5000000-0000-4000-8000-000000000002'::uuid,'MINV-2026-0102','c4000000-0000-4000-8000-000000000002'::uuid,'seed-minv-naledi-cur'),
  ('c5000000-0000-4000-8000-000000000003'::uuid,'MINV-2026-0103','c4000000-0000-4000-8000-000000000003'::uuid,'seed-minv-sipho-cur'),
  ('c5000000-0000-4000-8000-000000000004'::uuid,'MINV-2026-0104','c4000000-0000-4000-8000-000000000004'::uuid,'seed-minv-zanele-cur')
) as i(id, ref, mid, key)
join public.memberships m on m.id = i.mid
join public.membership_plans p on p.id = m.plan_id
on conflict (idempotency_key) do nothing;

insert into public.payments (id, membership_invoice_id, customer_id, provider, provider_ref, amount_cents, status, receipt_no, idempotency_key, method, recorded_by, verified_at, created_at)
select p.id, i.id, i.customer_id, case when m.payment_method = 'card' then 'sandbox' else 'pos' end, p.pref, i.amount_cents, 'successful', p.rcpt, p.key,
       case when m.payment_method = 'card' then 'card' else 'cash' end, case when m.payment_method = 'card' then null else 'seed_johan' end, i.paid_at, i.paid_at
from (values
  ('60000000-0000-4000-8000-000000000101'::uuid,'c5000000-0000-4000-8000-000000000001'::uuid,'pi_sbx_mem_0101','RCP-70101','pay-seed-mem-0101'),
  ('60000000-0000-4000-8000-000000000102'::uuid,'c5000000-0000-4000-8000-000000000002'::uuid,'pos_mem_0102',    'RCP-70102','pay-seed-mem-0102'),
  ('60000000-0000-4000-8000-000000000103'::uuid,'c5000000-0000-4000-8000-000000000003'::uuid,'pi_sbx_mem_0103','RCP-70103','pay-seed-mem-0103'),
  ('60000000-0000-4000-8000-000000000104'::uuid,'c5000000-0000-4000-8000-000000000004'::uuid,'pi_sbx_mem_0104','RCP-70104','pay-seed-mem-0104')
) as p(id, inv, pref, rcpt, key)
join public.membership_invoices i on i.id = p.inv
join public.memberships m on m.id = i.membership_id
on conflict (idempotency_key) do nothing;

update public.membership_invoices i set payment_id = p.id from public.payments p where p.membership_invoice_id = i.id and i.payment_id is null;

-- ---------- Loyalty config: tiers are plan-driven, discounts live on the plan --------
update public.loyalty_configs
   set tiers = (select jsonb_agg(t || jsonb_build_object('discount_pct', 0)) from jsonb_array_elements(tiers) t)
                || case when tiers @> '[{"tier":"black"}]' then '[]'::jsonb
                        else '[{"tier":"black","name":"Black","min_points":5000,"max_points":null,"earn_multiplier":1.75,"discount_pct":0}]'::jsonb end
 where status in ('published','draft');

-- ---------- Membership notification templates (also in migration 0010) ----------
insert into public.notification_templates (key, channel, title, body, is_promotional) values
 ('membership_activated','push','Welcome to Sparkling {{plan}}','Your {{plan}} membership is active until {{period_end}}. {{benefits}}',false),
 ('membership_activated','whatsapp',null,'Hi {{name}}, your Sparkling {{plan}} membership is active. {{benefits}} Renews on {{period_end}}.',false),
 ('membership_renewal_due','push','{{plan}} membership renewal','Your {{plan}} membership renews on {{period_end}} ({{amount}}).',false),
 ('membership_renewal_due','whatsapp',null,'Hi {{name}}, your Sparkling {{plan}} membership ({{amount}}/month) is due on {{period_end}}. Pay in the app or at any outlet to keep your benefits.',false),
 ('membership_renewed','push','{{plan}} membership renewed','Paid {{amount}}. Your washes have been reset for the month.',false),
 ('membership_past_due','push','Membership payment due','Your {{plan}} benefits are paused until {{amount}} is paid.',false),
 ('membership_cancelled','push','Membership cancelled','Your {{plan}} membership ends on {{period_end}}. You can rejoin any time.',false)
on conflict (key, channel) do update set title = excluded.title, body = excluded.body, is_promotional = excluded.is_promotional;

commit;
