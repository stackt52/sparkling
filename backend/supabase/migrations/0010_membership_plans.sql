-- 0010: Membership plans (monthly subscriptions) — source: Sparkling_Membership_Plans.docx
--
-- A plan (Gold / Platinum / Black) is a monthly subscription. It grants:
--   * entitlement groups — each group is either "choose_one" (the member picks
--     one option at enrolment, e.g. 4 × Sparkling Wash OR 8 × Exterior Wash) or
--     "all" (every option applies, e.g. Black's annual ceramic coating);
--   * an entitlement = quantity × period (month | year) of a set of services
--     (an "Exterior Wash" is whichever exterior-wash service the outlet offers);
--   * a discount rule: pct + scope ('plan_services' = the member's selected
--     services once the allowance is used up; 'other_services' = every service
--     that is not a plan service; 'all_services'; 'none').
-- The customer's loyalty tier is now driven by the active membership (trigger
-- below); loyalty_configs.tiers keeps earn multipliers only.

-- ---------------------------------------------------------------- plans -----
create table if not exists public.membership_plans (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,                         -- 'gold' | 'platinum' | 'black'
  tier              public.loyalty_tier not null unique,
  name              text not null,
  tagline           text,
  monthly_fee_cents int  not null check (monthly_fee_cents > 0),
  discount_pct      numeric(5,2) not null default 0 check (discount_pct >= 0 and discount_pct <= 100),
  discount_scope    text not null default 'plan_services'
                    check (discount_scope in ('plan_services','other_services','all_services','none')),
  discount_note     text,                                         -- wording from the plan sheet
  color             text,                                         -- UI hint: 'gold' | 'platinum' | 'black'
  sort_order        int  not null default 100,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table if not exists public.membership_plan_groups (
  id          uuid primary key default gen_random_uuid(),
  plan_id     uuid not null references public.membership_plans(id) on delete cascade,
  code        text not null,                                      -- 'washes' | 'detail' | 'coating'
  name        text not null,
  selection   text not null default 'choose_one' check (selection in ('choose_one','all')),
  sort_order  int  not null default 100,
  unique (plan_id, code)
);

create table if not exists public.membership_plan_entitlements (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.membership_plan_groups(id) on delete cascade,
  code        text not null,                                      -- 'G1', 'P2', 'B5' …
  label       text not null,                                      -- '4 × Sparkling Wash'
  quantity    int  not null check (quantity > 0),
  period      text not null default 'month' check (period in ('month','year')),
  sort_order  int  not null default 100,
  unique (group_id, code)
);

-- Services an entitlement can be redeemed against (any of them counts).
create table if not exists public.membership_entitlement_services (
  entitlement_id uuid not null references public.membership_plan_entitlements(id) on delete cascade,
  service_id     uuid not null references public.services(id) on delete cascade,
  is_primary     boolean not null default false,                  -- the one to show in copy
  primary key (entitlement_id, service_id)
);

-- ---------------------------------------------------------- memberships -----
create sequence if not exists public.membership_ref_seq;
create sequence if not exists public.membership_invoice_ref_seq;

create table if not exists public.memberships (
  id                    uuid primary key default gen_random_uuid(),
  ref                   text not null unique default app.next_ref('MEM', 'public.membership_ref_seq'),
  customer_id           text not null references public.profiles(id) on update cascade on delete cascade,
  plan_id               uuid not null references public.membership_plans(id),
  status                text not null default 'pending'
                        check (status in ('pending','active','past_due','cancelled','expired')),
  started_at            timestamptz,
  current_period_start  timestamptz,
  current_period_end    timestamptz,
  cancel_at_period_end  boolean not null default false,
  cancelled_at          timestamptz,
  ended_at              timestamptz,
  next_plan_id          uuid references public.membership_plans(id),   -- downgrade/upgrade applied at renewal
  payment_method        text not null default 'card' check (payment_method in ('card','cash','eft','sandbox')),
  client_op_id          text unique,
  created_by            text references public.profiles(id) on update cascade,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create unique index if not exists memberships_one_live_per_customer
  on public.memberships(customer_id) where status in ('pending','active','past_due');
create index if not exists memberships_status_idx on public.memberships(status, current_period_end);

-- The option picked per choose_one group (one row per group; "all" groups need no row).
create table if not exists public.membership_selections (
  membership_id   uuid not null references public.memberships(id) on delete cascade,
  group_id        uuid not null references public.membership_plan_groups(id),
  entitlement_id  uuid not null references public.membership_plan_entitlements(id),
  primary key (membership_id, group_id)
);

-- Append-only consumption ledger. +quantity when a booking redeems an
-- entitlement, −quantity when that booking is cancelled (a release row).
create table if not exists public.membership_usage (
  id               uuid primary key default gen_random_uuid(),
  membership_id    uuid not null references public.memberships(id) on delete cascade,
  entitlement_id   uuid not null references public.membership_plan_entitlements(id),
  booking_id       uuid references public.bookings(id),
  quantity         int  not null check (quantity <> 0),
  period_start     timestamptz not null,
  period_end       timestamptz not null,
  idempotency_key  text not null unique,
  created_by       text references public.profiles(id) on update cascade,
  created_at       timestamptz not null default now()
);
create index if not exists membership_usage_period_idx on public.membership_usage(membership_id, entitlement_id, period_start);

-- Monthly invoices; paid through the normal payments table (payments.membership_invoice_id).
create table if not exists public.membership_invoices (
  id               uuid primary key default gen_random_uuid(),
  ref              text not null unique default app.next_ref('MINV', 'public.membership_invoice_ref_seq'),
  membership_id    uuid not null references public.memberships(id) on delete cascade,
  customer_id      text not null references public.profiles(id) on update cascade,
  period_start     timestamptz not null,
  period_end       timestamptz not null,
  amount_cents     int  not null check (amount_cents >= 0),
  status           text not null default 'pending' check (status in ('pending','paid','failed','void')),
  due_at           timestamptz not null default now(),
  paid_at          timestamptz,
  payment_id       uuid,                                          -- fk added below
  idempotency_key  text not null unique,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists membership_invoices_membership_idx on public.membership_invoices(membership_id, period_start desc);

alter table public.payments add column if not exists membership_invoice_id uuid references public.membership_invoices(id);
alter table public.membership_invoices
  add constraint membership_invoices_payment_fk foreign key (payment_id) references public.payments(id);

-- Bookings remember which benefit applied.
alter table public.bookings
  add column if not exists membership_id      uuid references public.memberships(id),
  add column if not exists entitlement_id     uuid references public.membership_plan_entitlements(id),
  add column if not exists membership_benefit text check (membership_benefit in ('included','discount'));

-- ------------------------------------------------------------ triggers -----
do $$
declare t text;
begin
  foreach t in array array['membership_plans','memberships','membership_invoices']
  loop
    if not exists (select 1 from pg_trigger where tgname = t || '_set_updated_at') then
      execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function app.set_updated_at()', t, t);
    end if;
  end loop;
end $$;

drop trigger if exists membership_usage_immutable on public.membership_usage;
create trigger membership_usage_immutable before update or delete on public.membership_usage
  for each row execute function app.deny_change();

-- Tier follows the live membership: active/past_due → plan tier; anything else → silver.
create or replace function app.sync_membership_tier() returns trigger
language plpgsql security definer set search_path = public, app as $$
declare v_tier public.loyalty_tier := 'silver';
begin
  select p.tier into v_tier
    from public.memberships m join public.membership_plans p on p.id = m.plan_id
   where m.customer_id = new.customer_id and m.status in ('active','past_due')
   order by m.updated_at desc limit 1;
  insert into public.loyalty_accounts (customer_id, tier, tier_since)
       values (new.customer_id, coalesce(v_tier, 'silver'), now())
  on conflict (customer_id) do update
        set tier = excluded.tier,
            tier_since = case when public.loyalty_accounts.tier = excluded.tier then public.loyalty_accounts.tier_since else now() end;
  return new;
end $$;
drop trigger if exists memberships_sync_tier on public.memberships;
create trigger memberships_sync_tier after insert or update of status, plan_id on public.memberships
  for each row execute function app.sync_membership_tier();

-- ----------------------------------------------------------------- RLS -----
alter table public.membership_plans                enable row level security;
alter table public.membership_plan_groups          enable row level security;
alter table public.membership_plan_entitlements    enable row level security;
alter table public.membership_entitlement_services enable row level security;
alter table public.memberships                     enable row level security;
alter table public.membership_selections           enable row level security;
alter table public.membership_usage                enable row level security;
alter table public.membership_invoices             enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'membership_plans_read') then
    create policy membership_plans_read on public.membership_plans for select using (is_active or app.is_manager());
    create policy membership_plan_groups_read on public.membership_plan_groups for select using (true);
    create policy membership_plan_entitlements_read on public.membership_plan_entitlements for select using (true);
    create policy membership_entitlement_services_read on public.membership_entitlement_services for select using (true);
    create policy memberships_owner on public.memberships for select using (customer_id = app.uid() or app.is_staff());
    create policy membership_selections_owner on public.membership_selections for select
      using (exists (select 1 from public.memberships m where m.id = membership_id and (m.customer_id = app.uid() or app.is_staff())));
    create policy membership_usage_owner on public.membership_usage for select
      using (exists (select 1 from public.memberships m where m.id = membership_id and (m.customer_id = app.uid() or app.is_staff())));
    create policy membership_invoices_owner on public.membership_invoices for select using (customer_id = app.uid() or app.is_staff());
  end if;
end $$;

grant select on public.membership_plans, public.membership_plan_groups, public.membership_plan_entitlements,
                public.membership_entitlement_services, public.memberships, public.membership_selections,
                public.membership_usage, public.membership_invoices to authenticated;
grant all on public.membership_plans, public.membership_plan_groups, public.membership_plan_entitlements,
             public.membership_entitlement_services, public.memberships, public.membership_selections,
             public.membership_usage, public.membership_invoices to service_role;
grant usage, select on public.membership_ref_seq, public.membership_invoice_ref_seq to service_role;

alter publication supabase_realtime add table public.memberships, public.membership_usage, public.membership_invoices;

-- ------------------------------------------------- notification templates -----
insert into public.notification_templates (key, channel, title, body, is_promotional) values
 ('membership_activated','push','Welcome to Sparkling {{plan}}','Your {{plan}} membership is active until {{period_end}}. {{benefits}}',false),
 ('membership_activated','whatsapp',null,'Hi {{name}}, your Sparkling {{plan}} membership is active. {{benefits}} Renews on {{period_end}}.',false),
 ('membership_renewal_due','push','{{plan}} membership renewal','Your {{plan}} membership renews on {{period_end}} ({{amount}}).',false),
 ('membership_renewal_due','whatsapp',null,'Hi {{name}}, your Sparkling {{plan}} membership ({{amount}}/month) is due on {{period_end}}. Pay in the app or at any outlet to keep your benefits.',false),
 ('membership_renewed','push','{{plan}} membership renewed','Paid {{amount}}. Your washes have been reset for the month.',false),
 ('membership_past_due','push','Membership payment due','Your {{plan}} benefits are paused until {{amount}} is paid.',false),
 ('membership_cancelled','push','Membership cancelled','Your {{plan}} membership ends on {{period_end}}. You can rejoin any time.',false)
on conflict (key, channel) do update set title = excluded.title, body = excluded.body, is_promotional = excluded.is_promotional;

-- ------------------------------------------------------ plans (reference) -----
insert into public.membership_plans (id, code, tier, name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, color, sort_order) values
 ('c1000000-0000-4000-8000-000000000001','gold',    'gold',    'Gold',    '4 Sparkling Washes or 8 Exterior Washes a month',              29500, 10, 'other_services', '10% discount on any other Sparkling service', 'gold',     10),
 ('c1000000-0000-4000-8000-000000000002','platinum','platinum','Platinum','8 Sparkling Washes or 16 Exterior Washes a month',             47500, 10, 'plan_services',  '10% discount on the above selected services',  'platinum', 20),
 ('c1000000-0000-4000-8000-000000000003','black',   'black',   'Black',   'Washes, a monthly detail or steam clean and an annual ceramic coating', 85000, 10, 'plan_services', '10% discount on the above selected services', 'black', 30)
on conflict (code) do update set
  tier = excluded.tier, name = excluded.name, tagline = excluded.tagline, monthly_fee_cents = excluded.monthly_fee_cents,
  discount_pct = excluded.discount_pct, discount_scope = excluded.discount_scope, discount_note = excluded.discount_note,
  color = excluded.color, sort_order = excluded.sort_order;

insert into public.membership_plan_groups (id, plan_id, code, name, selection, sort_order) values
 ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','washes', 'Monthly washes',        'choose_one', 10),
 ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','washes', 'Monthly washes',        'choose_one', 10),
 ('c2000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','washes', 'Monthly washes',        'choose_one', 10),
 ('c2000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000003','detail', 'Monthly detail',        'choose_one', 20),
 ('c2000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000003','coating','Annual ceramic coating','all',        30)
on conflict (plan_id, code) do update set name = excluded.name, selection = excluded.selection, sort_order = excluded.sort_order;

insert into public.membership_plan_entitlements (id, group_id, code, label, quantity, period, sort_order) values
 ('c3000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','G1','4 × Sparkling Wash',            4,'month',10),
 ('c3000000-0000-4000-8000-000000000002','c2000000-0000-4000-8000-000000000001','G2','8 × Exterior Wash',             8,'month',20),
 ('c3000000-0000-4000-8000-000000000003','c2000000-0000-4000-8000-000000000002','P1','8 × Sparkling Wash',            8,'month',10),
 ('c3000000-0000-4000-8000-000000000004','c2000000-0000-4000-8000-000000000002','P2','16 × Exterior Wash',           16,'month',20),
 ('c3000000-0000-4000-8000-000000000005','c2000000-0000-4000-8000-000000000003','B1','10 × Sparkling Wash per month',10,'month',10),
 ('c3000000-0000-4000-8000-000000000006','c2000000-0000-4000-8000-000000000003','B2','20 × Exterior Wash',           20,'month',20),
 ('c3000000-0000-4000-8000-000000000007','c2000000-0000-4000-8000-000000000004','B3','1 × Auto Detail Complete per month',1,'month',10),
 ('c3000000-0000-4000-8000-000000000008','c2000000-0000-4000-8000-000000000004','B4','1 × Engine Steam Clean per month',  1,'month',20),
 ('c3000000-0000-4000-8000-000000000009','c2000000-0000-4000-8000-000000000005','B5','1 × Ceramic coating per annum',    1,'year', 10)
on conflict (group_id, code) do update set label = excluded.label, quantity = excluded.quantity, period = excluded.period, sort_order = excluded.sort_order;

-- Service mapping (by catalogue code). "Exterior Wash" = whichever exterior wash the outlet sells.
with map(ent, code, is_primary) as (values
  ('c3000000-0000-4000-8000-000000000001'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000003'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000005'::uuid,'SPARKLING_WASH',true),
  ('c3000000-0000-4000-8000-000000000002'::uuid,'EXT_WASH',true),      ('c3000000-0000-4000-8000-000000000002'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000002'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000004'::uuid,'EXT_WASH',true),      ('c3000000-0000-4000-8000-000000000004'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000004'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000006'::uuid,'EXT_WASH',true),      ('c3000000-0000-4000-8000-000000000006'::uuid,'EXT_WASH_TYRE',false), ('c3000000-0000-4000-8000-000000000006'::uuid,'WASH_GO',false),
  ('c3000000-0000-4000-8000-000000000007'::uuid,'AUTO_DETAIL_COMPLETE',true),
  ('c3000000-0000-4000-8000-000000000008'::uuid,'ENGINE_STEAM',true),
  ('c3000000-0000-4000-8000-000000000009'::uuid,'CERAMIC_COATING',true)
)
insert into public.membership_entitlement_services (entitlement_id, service_id, is_primary)
select m.ent, s.id, m.is_primary from map m join public.services s on s.code = m.code
on conflict (entitlement_id, service_id) do update set is_primary = excluded.is_primary;

-- Tier discounts now come from the plan; the loyalty config keeps earn multipliers only.
update public.loyalty_configs
   set tiers = (select jsonb_agg(t || jsonb_build_object('discount_pct', 0)) from jsonb_array_elements(tiers) t)
                || case when tiers @> '[{"tier":"black"}]' then '[]'::jsonb
                        else '[{"tier":"black","name":"Black","min_points":5000,"max_points":null,"earn_multiplier":1.75,"discount_pct":0}]'::jsonb end
 where status in ('published','draft');
