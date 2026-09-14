-- Migration 0008: outlet catalogue pricing model (per-outlet service catalogue from
-- Sparkling_outlet_services_and_charges.xlsx): service groups, vehicle-size pricing,
-- "from" / by-quote pricing modes, VAT mode, composite services and add-ons.
-- Idempotent: safe to re-run.

-- ---------- services (global canonical catalogue) ----------------------------
alter table public.services
  add column if not exists group_name          text not null default 'Car Wash Options',  -- 'Car Wash Options' | 'Combinations' | 'Auto Body Repair'
  add column if not exists pricing_mode        text not null default 'from',              -- 'from' | 'fixed' | 'by_quote'
  add column if not exists vat_mode            text not null default 'incl',              -- 'incl' | 'excl'
  add column if not exists price_small_cents   int,                                       -- small vehicle "from" price
  add column if not exists price_large_cents   int,                                       -- large vehicle "from" price
  add column if not exists price_general_cents int,                                       -- size-independent price (auto body)
  add column if not exists is_addon            boolean not null default false,            -- "Add to any Combo" items
  add column if not exists addon_group_name    text,                                      -- which group the add-on attaches to
  add column if not exists notes               text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'services_pricing_mode_check') then
    alter table public.services add constraint services_pricing_mode_check check (pricing_mode in ('from','fixed','by_quote'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'services_vat_mode_check') then
    alter table public.services add constraint services_vat_mode_check check (vat_mode in ('incl','excl'));
  end if;
end $$;

-- ---------- outlet_services (per-outlet binding + overrides) -----------------
alter table public.outlet_services
  add column if not exists display_name        text,     -- outlet's own wording for the service
  add column if not exists price_small_cents   int,
  add column if not exists price_large_cents   int,
  add column if not exists price_general_cents int,
  add column if not exists pricing_mode        text,     -- null = inherit from services
  add column if not exists vat_mode            text,     -- null = inherit
  add column if not exists sort_order          int,
  add column if not exists notes               text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'outlet_services_pricing_mode_check') then
    alter table public.outlet_services add constraint outlet_services_pricing_mode_check check (pricing_mode is null or pricing_mode in ('from','fixed','by_quote'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'outlet_services_vat_mode_check') then
    alter table public.outlet_services add constraint outlet_services_vat_mode_check check (vat_mode is null or vat_mode in ('incl','excl'));
  end if;
end $$;

-- ---------- composite membership ------------------------------------------------
-- A composite service "includes" its components. outlet_id null = global default;
-- an outlet row set overrides the global set for that outlet.
create table if not exists public.service_components (
  id                uuid primary key default gen_random_uuid(),
  parent_service_id uuid not null references public.services(id) on delete cascade,
  child_service_id  uuid not null references public.services(id) on delete cascade,
  outlet_id         uuid references public.outlets(id) on delete cascade,
  quantity          int not null default 1 check (quantity > 0),
  sort_order        int not null default 100,
  created_at        timestamptz not null default now(),
  check (parent_service_id <> child_service_id)
);
create unique index if not exists service_components_unique
  on public.service_components(parent_service_id, child_service_id, coalesce(outlet_id, '00000000-0000-0000-0000-000000000000'::uuid));
alter table public.service_components enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'service_components_read') then
    create policy service_components_read on public.service_components for select using (true);
  end if;
end $$;
grant select on public.service_components to anon, authenticated;
grant all on public.service_components to service_role;

-- ---------- vehicles: size class drives pricing ----------------------------------
alter table public.vehicles
  add column if not exists size_class text;   -- 'small' | 'large' | 'bike' (null = unknown → small)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'vehicles_size_class_check') then
    alter table public.vehicles add constraint vehicles_size_class_check check (size_class is null or size_class in ('small','large','bike'));
  end if;
end $$;

-- ---------- bookings: pricing basis + add-ons ----------------------------------------
alter table public.bookings
  add column if not exists vehicle_size     text,                       -- size used for pricing
  add column if not exists pricing_mode     text,                       -- 'from' | 'fixed' | 'by_quote' at booking time
  add column if not exists vat_mode         text,
  add column if not exists addon_service_ids uuid[] not null default '{}',
  add column if not exists addons_cents     int not null default 0;

-- Keep the legacy base_price_cents in step for old readers: small/general price when present.
update public.services set base_price_cents = coalesce(price_small_cents, price_general_cents, base_price_cents)
 where (price_small_cents is not null or price_general_cents is not null);
