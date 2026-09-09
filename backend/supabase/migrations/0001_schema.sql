-- =============================================================================
-- Sparkling Platform — authoritative Supabase (PostgreSQL) schema
-- Migration 0001: full reset + schema (SRS v1.0 §10, ARC-007 data ownership)
--
-- Identity  : Firebase Auth is the identity provider. profiles.id = Firebase UID.
--             Supabase "Third-Party Auth (Firebase)" lets clients hit PostgREST /
--             Realtime with a Firebase ID token; RLS reads auth.jwt() claims:
--               sub        -> Firebase UID
--               role       -> customer|technician|supervisor|manager|admin|finance
--               outlet_ids -> text[] of outlet UUIDs the staff member may access
-- Writes    : All protected writes go through the versioned REST API
--             (Cloud Functions, service_role). Clients read through RLS and
--             subscribe to Realtime with the same policies (API-008).
-- =============================================================================

-- ---------- 0. RESET (the user asked for a clean slate) ----------------------
-- Drop every object inside public (safer on Supabase than dropping the schema itself).
do $$
declare r record;
begin
  for r in select 'drop view if exists public.' || quote_ident(viewname) || ' cascade' as q from pg_views where schemaname = 'public' loop execute r.q; end loop;
  for r in select 'drop table if exists public.' || quote_ident(tablename) || ' cascade' as q from pg_tables where schemaname = 'public' loop execute r.q; end loop;
  for r in select 'drop sequence if exists public.' || quote_ident(sequencename) || ' cascade' as q from pg_sequences where schemaname = 'public' loop execute r.q; end loop;
  for r in select 'drop function if exists public.' || quote_ident(p.proname) || '(' || pg_get_function_identity_arguments(p.oid) || ') cascade' as q
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop execute r.q; end loop;
  for r in select 'drop type if exists public.' || quote_ident(t.typname) || ' cascade' as q
             from pg_type t join pg_namespace n on n.oid = t.typnamespace
            where n.nspname = 'public' and t.typtype in ('e','d','c') and not exists (select 1 from pg_class c where c.reltype = t.oid)
              and not exists (select 1 from pg_depend d where d.objid = t.oid and d.deptype = 'e') loop execute r.q; end loop;
end $$;
drop schema if exists app cascade;
create schema app;
grant usage on schema app to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create schema if not exists extensions;
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "citext" with schema extensions;
set search_path = public, extensions;

-- ---------- 1. ENUMS ---------------------------------------------------------
create type public.user_role      as enum ('customer','technician','supervisor','manager','admin','finance');
create type public.service_category as enum ('car_wash','auto_body');
create type public.vehicle_source  as enum ('manual','scan');
create type public.booking_status  as enum ('draft','pending','confirmed','in_service','completed','cancelled');
create type public.quotation_status as enum ('requested','assessing','quoted','accepted','declined','expired','converted');
create type public.work_status     as enum ('queued','assigned','in_progress','blocked','completed','verified','cancelled');
create type public.step_status     as enum ('pending','done','blocked','skipped');
create type public.step_type       as enum ('confirm','text','numeric','select','photo','ack','supervisor_verify');
create type public.payment_status  as enum ('initiated','pending','successful','failed','cancelled','refunded');
create type public.loyalty_tier    as enum ('silver','gold','platinum');
create type public.ledger_type     as enum ('earn','redeem','adjust','expire','bonus');
create type public.inventory_reason as enum ('usage','receive','adjust','reorder_request','count');
create type public.alert_level     as enum ('low','out');
create type public.alert_status    as enum ('open','acknowledged','resolved');
create type public.notify_channel  as enum ('push','whatsapp','sms','email');
create type public.notify_status   as enum ('queued','sent','delivered','failed','suppressed');
create type public.config_status   as enum ('draft','published','archived');
create type public.sync_status     as enum ('pending','applied','conflict','rejected');

-- ---------- 2. JWT HELPERS (used by RLS) -------------------------------------
create or replace function app.uid() returns text
language sql stable as $$
  select nullif(coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', ''), '')
$$;

create or replace function app.role() returns text
language sql stable as $$
  select coalesce(
    current_setting('request.jwt.claims', true)::jsonb ->> 'role',
    (current_setting('request.jwt.claims', true)::jsonb -> 'app' ->> 'role'),
    'anon')
$$;

create or replace function app.outlet_ids() returns uuid[]
language sql stable as $$
  select coalesce(
    (select array_agg(x::uuid) from jsonb_array_elements_text(
       coalesce(current_setting('request.jwt.claims', true)::jsonb -> 'outlet_ids',
                current_setting('request.jwt.claims', true)::jsonb -> 'app' -> 'outlet_ids',
                '[]'::jsonb)) as t(x)),
    '{}'::uuid[])
$$;

create or replace function app.is_staff() returns boolean
language sql stable as $$ select app.role() in ('technician','supervisor','manager','admin','finance') $$;

create or replace function app.is_manager() returns boolean
language sql stable as $$ select app.role() in ('manager','admin') $$;

create or replace function app.is_admin() returns boolean
language sql stable as $$ select app.role() = 'admin' $$;

create or replace function app.can_see_outlet(p_outlet uuid) returns boolean
language sql stable as $$ select app.is_admin() or app.role() = 'finance' or p_outlet = any(app.outlet_ids()) $$;

create or replace function app.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

-- Human-friendly references (DAT-001 uniqueness comes from the uuid PK).
create sequence public.booking_ref_seq   start 1000;
create sequence public.quotation_ref_seq start 1000;
create sequence public.work_order_ref_seq start 4000;
create sequence public.receipt_ref_seq   start 70000;

create or replace function app.next_ref(prefix text, seq regclass) returns text
language sql volatile as $$
  select prefix || '-' || to_char(now(),'YYYY') || '-' || lpad(nextval(seq)::text, 4, '0')
$$;

-- ---------- 3. IDENTITY & ORGANISATION --------------------------------------
create table public.outlets (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  address_line  text,
  city          text,
  province      text,
  country       text not null default 'ZA',
  latitude      double precision,
  longitude     double precision,
  phone         text,
  email         citext,
  timezone      text not null default 'Africa/Johannesburg',
  opening_hours jsonb not null default '{"mon":["07:30","17:30"],"tue":["07:30","17:30"],"wed":["07:30","17:30"],"thu":["07:30","17:30"],"fri":["07:30","17:30"],"sat":["08:00","14:00"],"sun":null}',
  slot_minutes  int  not null default 30 check (slot_minutes between 10 and 240),
  bay_count     int  not null default 3 check (bay_count > 0),
  rating        numeric(2,1) default 4.8,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.profiles (
  id                text primary key,                       -- Firebase UID
  role              public.user_role not null default 'customer',
  full_name         text not null,
  email             citext unique,
  phone             text,
  avatar_url        text,
  is_active         boolean not null default true,
  marketing_opt_in  boolean not null default false,          -- CUS-053 / ADM-042
  whatsapp_opt_in   boolean not null default true,
  push_opt_in       boolean not null default true,
  locale            text not null default 'en-ZA',
  reduced_motion    boolean not null default false,
  haptics           boolean not null default true,
  last_seen_at      timestamptz,
  deactivated_at    timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.staff_outlets (
  profile_id  text not null references public.profiles(id) on update cascade on delete cascade,
  outlet_id   uuid not null references public.outlets(id) on delete cascade,
  is_primary  boolean not null default false,
  primary key (profile_id, outlet_id)
);

create table public.staff_skills (
  profile_id  text not null references public.profiles(id) on update cascade on delete cascade,
  skill       text not null,                                   -- e.g. 'wash','detail','paint','panel'
  primary key (profile_id, skill)
);

create table public.staff_availability (
  profile_id   text primary key references public.profiles(id) on update cascade on delete cascade,
  status       text not null default 'available' check (status in ('available','busy','break','off')),
  capacity     int  not null default 3,
  updated_at   timestamptz not null default now()
);

create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  profile_id  text not null references public.profiles(id) on update cascade on delete cascade,
  token       text not null unique,
  platform    text not null check (platform in ('android','ios','web')),
  app         text not null check (app in ('customer','staff','admin')),
  updated_at  timestamptz not null default now()
);

-- ---------- 4. CATALOGUE -----------------------------------------------------
create table public.checklist_templates (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  category     public.service_category not null,
  version      int  not null default 1,
  status       public.config_status not null default 'published',
  steps        jsonb not null default '[]',
  -- step: {key,title,type,required,hint,options[],unit,min,max,photo_required}
  outlet_id    uuid references public.outlets(id),           -- null = organisation-wide
  outlet_key   uuid generated always as (coalesce(outlet_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  created_by   text references public.profiles(id) on update cascade,
  created_at   timestamptz not null default now(),
  unique (name, version, outlet_key)
);

create table public.services (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  name              text not null,
  description       text,
  category          public.service_category not null,
  duration_minutes  int  not null default 30,
  base_price_cents  int  not null default 0 check (base_price_cents >= 0),
  is_quote_based    boolean not null default false,
  points_per_rand   numeric(6,3) not null default 0.10,       -- configurable earn rate (CUS-062)
  icon              text default 'local_car_wash',
  checklist_template_id uuid references public.checklist_templates(id),
  is_active         boolean not null default true,
  sort_order        int not null default 100,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.outlet_services (
  outlet_id     uuid not null references public.outlets(id) on delete cascade,
  service_id    uuid not null references public.services(id) on delete cascade,
  price_cents   int,                                           -- null = inherit base price
  is_available  boolean not null default true,
  primary key (outlet_id, service_id)
);

-- ---------- 5. CUSTOMERS & VEHICLES ------------------------------------------
create table public.vehicles (
  id               uuid primary key default gen_random_uuid(),
  customer_id      text not null references public.profiles(id) on update cascade on delete cascade,
  registration_no  text not null,
  vin              text,
  engine_no        text,
  make             text,
  model            text,
  colour           text,
  year             int check (year between 1950 and 2100),
  licence_no       text,
  disc_expiry      date,
  source           public.vehicle_source not null default 'manual',
  disc_verified    boolean not null default false,
  disc_hash        text,                                      -- sha256 of raw payload (BAR-004: raw not stored)
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index vehicles_customer_reg_unique on public.vehicles(customer_id, upper(regexp_replace(registration_no,'[^A-Za-z0-9]','','g'))) where is_active;
create index vehicles_vin_idx on public.vehicles(vin) where vin is not null;

create table public.attachments (
  id            uuid primary key default gen_random_uuid(),
  entity_type   text not null,                                 -- 'quotation','checklist_step','vehicle'
  entity_id     uuid not null,
  storage_path  text not null,                                 -- Cloud Storage for Firebase object path
  mime_type     text not null,
  size_bytes    bigint not null check (size_bytes >= 0),
  sha256        text,
  uploaded_by   text references public.profiles(id) on update cascade,
  created_at    timestamptz not null default now()
);
create index attachments_entity_idx on public.attachments(entity_type, entity_id);

-- ---------- 6. BOOKINGS, QUOTATIONS, WORK -----------------------------------
create table public.quotations (
  id             uuid primary key default gen_random_uuid(),
  ref            text not null unique default app.next_ref('QT', 'public.quotation_ref_seq'),
  customer_id    text not null references public.profiles(id) on update cascade,
  vehicle_id     uuid not null references public.vehicles(id),
  outlet_id      uuid not null references public.outlets(id),
  category       text not null,                                -- 'Dent','Scratch','Bumper','Panel','Paint','Glass'
  description    text not null,
  status         public.quotation_status not null default 'requested',
  amount_cents   int check (amount_cents >= 0),
  line_items     jsonb not null default '[]',
  assessor_id    text references public.profiles(id) on update cascade,
  valid_until    date,
  quoted_at      timestamptz,
  decided_at     timestamptz,
  decision_by    text references public.profiles(id) on update cascade,
  decision_note  text,
  client_op_id   text unique,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.bookings (
  id              uuid primary key default gen_random_uuid(),
  ref             text not null unique default app.next_ref('SPK', 'public.booking_ref_seq'),
  customer_id     text not null references public.profiles(id) on update cascade,
  vehicle_id      uuid not null references public.vehicles(id),
  outlet_id       uuid not null references public.outlets(id),
  service_id      uuid not null references public.services(id),
  quotation_id    uuid references public.quotations(id),
  slot_start      timestamptz not null,
  slot_end        timestamptz not null,
  status          public.booking_status not null default 'pending',
  price_cents     int not null default 0,
  discount_cents  int not null default 0,
  total_cents     int not null default 0,
  discount_label  text,
  points_pending  int not null default 0,
  notes           text,
  cancel_reason   text,
  client_op_id    text unique,                                 -- idempotency (API-003 / DAT-005)
  created_by      text references public.profiles(id) on update cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (slot_end > slot_start)
);
create index bookings_customer_idx on public.bookings(customer_id, slot_start desc);
create index bookings_outlet_slot_idx on public.bookings(outlet_id, slot_start);

create table public.work_orders (
  id                    uuid primary key default gen_random_uuid(),
  ref                   text not null unique default app.next_ref('WO', 'public.work_order_ref_seq'),
  outlet_id             uuid not null references public.outlets(id),
  booking_id            uuid references public.bookings(id),
  quotation_id          uuid references public.quotations(id),
  vehicle_id            uuid not null references public.vehicles(id),
  customer_id           text not null references public.profiles(id) on update cascade,
  service_id            uuid not null references public.services(id),
  status                public.work_status not null default 'queued',
  priority              smallint not null default 2 check (priority between 1 and 3),
  bay                   text,
  checklist_template_id uuid references public.checklist_templates(id),
  template_version      int,
  assignee_id           text references public.profiles(id) on update cascade,
  eta_at                timestamptz,
  started_at            timestamptz,
  blocked_reason        text,
  completed_at          timestamptz,
  verified_at           timestamptz,
  verified_by           text references public.profiles(id) on update cascade,
  due_at                timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index work_orders_outlet_status_idx on public.work_orders(outlet_id, status);
create index work_orders_assignee_idx on public.work_orders(assignee_id) where assignee_id is not null;

create table public.tasks (
  id              uuid primary key default gen_random_uuid(),
  work_order_id   uuid not null references public.work_orders(id) on delete cascade,
  outlet_id       uuid not null references public.outlets(id),
  title           text not null,
  seq             int not null default 1,
  assignee_id     text references public.profiles(id) on update cascade,
  status          public.work_status not null default 'queued',
  priority        smallint not null default 2 check (priority between 1 and 3),
  blocked_reason  text,
  due_at          timestamptz,
  started_at      timestamptz,
  completed_at    timestamptz,
  elapsed_seconds int not null default 0,
  client_op_id    text unique,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index tasks_assignee_idx on public.tasks(assignee_id, status);
create index tasks_outlet_idx  on public.tasks(outlet_id, status);

create table public.task_events (                              -- STF-024 audit trail (append-only)
  id             uuid primary key default gen_random_uuid(),
  task_id        uuid references public.tasks(id) on delete cascade,
  work_order_id  uuid references public.work_orders(id) on delete cascade,
  actor_id       text references public.profiles(id) on update cascade,
  event          text not null,                                 -- 'assigned','transition','step_done','step_blocked','override'
  from_status    text,
  to_status      text,
  reason         text,
  metadata       jsonb not null default '{}',
  client_op_id   text unique,
  created_at     timestamptz not null default now()
);

create table public.checklist_step_results (
  id             uuid primary key default gen_random_uuid(),
  work_order_id  uuid not null references public.work_orders(id) on delete cascade,
  step_key       text not null,
  status         public.step_status not null default 'pending',
  value          jsonb,
  attachment_id  uuid references public.attachments(id),
  actor_id       text references public.profiles(id) on update cascade,
  note           text,
  client_op_id   text unique,
  completed_at   timestamptz,
  updated_at     timestamptz not null default now(),
  unique (work_order_id, step_key)
);

-- ---------- 7. PAYMENTS ------------------------------------------------------
create table public.payment_methods (
  id           uuid primary key default gen_random_uuid(),
  customer_id  text not null references public.profiles(id) on update cascade on delete cascade,
  provider     text not null default 'sandbox',
  token        text not null,                                  -- provider token only (SEC-009), never PAN
  brand        text,                                            -- 'visa','mastercard','eft'
  last4        text,
  label        text,
  is_default   boolean not null default false,
  created_at   timestamptz not null default now()
);

create table public.payments (
  id               uuid primary key default gen_random_uuid(),
  booking_id       uuid references public.bookings(id),
  quotation_id     uuid references public.quotations(id),
  customer_id      text not null references public.profiles(id) on update cascade,
  provider         text not null default 'sandbox',
  provider_ref     text,
  method_id        uuid references public.payment_methods(id),
  amount_cents     int not null check (amount_cents >= 0),
  currency         text not null default 'ZAR',
  status           public.payment_status not null default 'initiated',
  receipt_no       text unique,
  idempotency_key  text not null unique,                       -- CUS-045
  failure_reason   text,
  verified_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table public.payment_events (                           -- webhook replay protection (API-009)
  id                 uuid primary key default gen_random_uuid(),
  payment_id         uuid references public.payments(id) on delete cascade,
  provider           text not null,
  provider_event_id  text not null,
  event_type         text not null,
  signature_ok       boolean not null default false,
  payload            jsonb not null default '{}',
  received_at        timestamptz not null default now(),
  unique (provider, provider_event_id)
);

-- ---------- 8. LOYALTY -------------------------------------------------------
create table public.loyalty_configs (                          -- versioned + audited (ADM-025)
  id            uuid primary key default gen_random_uuid(),
  version       int not null unique,
  status        public.config_status not null default 'draft',
  tiers         jsonb not null,
  rules         jsonb not null,
  change_note   text,
  created_by    text references public.profiles(id) on update cascade,
  published_by  text references public.profiles(id) on update cascade,
  published_at  timestamptz,
  created_at    timestamptz not null default now()
);
create unique index loyalty_configs_single_published on public.loyalty_configs(status) where status = 'published';

create table public.loyalty_accounts (
  customer_id     text primary key references public.profiles(id) on update cascade on delete cascade,
  tier            public.loyalty_tier not null default 'silver',
  balance_points  int not null default 0,                     -- cache; authoritative = ledger sum
  lifetime_points int not null default 0,
  tier_since      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table public.loyalty_ledger (                           -- append-only (CUS-063)
  id               uuid primary key default gen_random_uuid(),
  customer_id      text not null references public.profiles(id) on update cascade,
  delta            int not null,
  type             public.ledger_type not null,
  source_type      text,                                        -- 'booking','payment','reward','admin','expiry'
  source_id        uuid,
  reference        text,
  description      text,
  idempotency_key  text not null unique,                       -- CUS-064
  expires_at       timestamptz,
  created_by       text references public.profiles(id) on update cascade,
  created_at       timestamptz not null default now()
);
create index loyalty_ledger_customer_idx on public.loyalty_ledger(customer_id, created_at desc);

create table public.rewards (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  description   text,
  icon          text default 'auto_awesome',
  points_cost   int not null check (points_cost > 0),
  min_tier      public.loyalty_tier not null default 'silver',
  is_active     boolean not null default true,
  sort_order    int not null default 100
);

create table public.reward_redemptions (
  id            uuid primary key default gen_random_uuid(),
  customer_id   text not null references public.profiles(id) on update cascade,
  reward_id     uuid not null references public.rewards(id),
  ledger_id     uuid not null references public.loyalty_ledger(id),
  code          text not null unique,
  status        text not null default 'issued' check (status in ('issued','used','expired','cancelled')),
  used_at       timestamptz,
  created_at    timestamptz not null default now()
);

-- ---------- 9. INVENTORY -----------------------------------------------------
create table public.inventory_items (
  id                 uuid primary key default gen_random_uuid(),
  outlet_id          uuid not null references public.outlets(id) on delete cascade,
  sku                text not null,
  name               text not null,
  unit               text not null default 'unit',
  on_hand            numeric(12,2) not null default 0 check (on_hand >= 0),   -- STF-043 no silent negatives
  reorder_threshold  numeric(12,2) not null default 0,
  pack_size          numeric(12,2),
  is_active          boolean not null default true,
  updated_at         timestamptz not null default now(),
  unique (outlet_id, sku)
);

create table public.inventory_movements (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references public.inventory_items(id) on delete cascade,
  delta          numeric(12,2) not null,
  reason         public.inventory_reason not null,
  actor_id       text references public.profiles(id) on update cascade,
  work_order_id  uuid references public.work_orders(id),
  note           text,
  client_op_id   text unique,
  created_at     timestamptz not null default now()
);

create table public.inventory_alerts (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references public.inventory_items(id) on delete cascade,
  outlet_id    uuid not null references public.outlets(id) on delete cascade,
  level        public.alert_level not null,
  status       public.alert_status not null default 'open',
  notified_at  timestamptz,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now()
);
create unique index inventory_alerts_open_unique on public.inventory_alerts(item_id) where status <> 'resolved';

-- ---------- 10. GAMIFICATION -------------------------------------------------
create table public.gamification_rules (
  id          uuid primary key default gen_random_uuid(),
  version     int not null unique,
  status      public.config_status not null default 'draft',
  rules       jsonb not null,   -- {"task_completed":25,"checklist_compliant":10,"verified_first_time":15,"p1_on_time":20}
  created_by  text references public.profiles(id) on update cascade,
  created_at  timestamptz not null default now()
);

create table public.staff_points_ledger (                      -- STF-053/054 (append-only, idempotent)
  id               uuid primary key default gen_random_uuid(),
  staff_id         text not null references public.profiles(id) on update cascade,
  outlet_id        uuid references public.outlets(id),
  delta            int not null,
  event_type       text not null,
  source_type      text,
  source_id        uuid,
  idempotency_key  text not null unique,
  created_at       timestamptz not null default now()
);
create index staff_points_staff_idx on public.staff_points_ledger(staff_id, created_at desc);

create table public.badges (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  description text,
  icon        text not null default 'military_tech',
  colour      text not null default '#00A0E0',
  criteria    jsonb not null default '{}'
);

create table public.staff_badges (
  staff_id    text not null references public.profiles(id) on update cascade on delete cascade,
  badge_id    uuid not null references public.badges(id) on delete cascade,
  awarded_at  timestamptz not null default now(),
  primary key (staff_id, badge_id)
);

-- ---------- 11. NOTIFICATIONS ------------------------------------------------
create table public.notification_templates (                  -- NOT-001
  key         text not null,
  channel     public.notify_channel not null,
  version     int not null default 1,
  title       text,
  body        text not null,
  is_promotional boolean not null default false,
  is_active   boolean not null default true,
  primary key (key, channel)
);

create table public.notifications (                            -- NOT-003
  id             uuid primary key default gen_random_uuid(),
  recipient_id   text not null references public.profiles(id) on update cascade on delete cascade,
  channel        public.notify_channel not null,
  template_key   text not null,
  title          text,
  body           text not null,
  payload        jsonb not null default '{}',
  status         public.notify_status not null default 'queued',
  provider_ref   text,
  error          text,
  attempts       int not null default 0,
  dedupe_key     text unique,                                  -- NOT-004
  read_at        timestamptz,
  sent_at        timestamptz,
  created_at     timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications(recipient_id, created_at desc);

-- ---------- 12. AUDIT & SYNC -------------------------------------------------
create table public.audit_events (                             -- ADM-003 / SEC-006 (append-only)
  id              uuid primary key default gen_random_uuid(),
  actor_id        text,
  actor_role      text,
  action          text not null,
  entity_type     text not null,
  entity_id       text,
  outlet_id       uuid,
  before          jsonb,
  after           jsonb,
  correlation_id  text,
  ip              inet,
  user_agent      text,
  outcome         text not null default 'ok',
  created_at      timestamptz not null default now()
);
create index audit_events_entity_idx on public.audit_events(entity_type, entity_id);
create index audit_events_created_idx on public.audit_events(created_at desc);

create table public.sync_operations (                          -- DAT-005 / ARC-004
  id            uuid primary key default gen_random_uuid(),
  client_op_id  text not null unique,
  profile_id    text not null references public.profiles(id) on update cascade,
  kind          text not null,
  payload       jsonb not null,
  status        public.sync_status not null default 'pending',
  result        jsonb,
  device_time   timestamptz,
  created_at    timestamptz not null default now(),
  applied_at    timestamptz
);

create table public.idempotency_keys (                         -- API-003 generic response cache
  key           text primary key,
  profile_id    text,
  method        text not null,
  path          text not null,
  status_code   int not null,
  response      jsonb,
  created_at    timestamptz not null default now()
);

create table public.feature_flags (                            -- NFR-013
  key         text primary key,
  enabled     boolean not null default false,
  description text,
  updated_at  timestamptz not null default now()
);

-- ---------- 13. TRIGGERS -----------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['outlets','profiles','services','vehicles','quotations','bookings','work_orders','tasks','payments','inventory_items','loyalty_accounts']
  loop
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function app.set_updated_at()', t, t);
  end loop;
end $$;

-- Loyalty balance cache maintained from the ledger (authoritative = ledger).
create or replace function app.apply_loyalty_ledger() returns trigger
language plpgsql security definer as $$
begin
  insert into public.loyalty_accounts (customer_id, balance_points, lifetime_points)
  values (new.customer_id, new.delta, greatest(new.delta,0))
  on conflict (customer_id) do update
    set balance_points  = public.loyalty_accounts.balance_points + new.delta,
        lifetime_points = public.loyalty_accounts.lifetime_points + greatest(new.delta,0),
        updated_at      = now();
  return new;
end $$;
create trigger loyalty_ledger_apply after insert on public.loyalty_ledger
for each row execute function app.apply_loyalty_ledger();

-- Inventory: movements update on_hand and raise/resolve alerts (STF-041).
create or replace function app.apply_inventory_movement() returns trigger
language plpgsql security definer as $$
declare v_item public.inventory_items%rowtype;
begin
  update public.inventory_items set on_hand = on_hand + new.delta, updated_at = now()
   where id = new.item_id returning * into v_item;
  if v_item.on_hand <= 0 then
    insert into public.inventory_alerts (item_id, outlet_id, level) values (v_item.id, v_item.outlet_id, 'out')
    on conflict (item_id) where status <> 'resolved' do update set level = 'out';
  elsif v_item.on_hand <= v_item.reorder_threshold then
    insert into public.inventory_alerts (item_id, outlet_id, level) values (v_item.id, v_item.outlet_id, 'low')
    on conflict (item_id) where status <> 'resolved' do update set level = 'low';
  else
    update public.inventory_alerts set status = 'resolved', resolved_at = now()
     where item_id = v_item.id and status <> 'resolved';
  end if;
  return new;
end $$;
create trigger inventory_movement_apply after insert on public.inventory_movements
for each row execute function app.apply_inventory_movement();

-- Append-only guards (SEC-006, CUS-063)
create or replace function app.deny_change() returns trigger
language plpgsql as $$ begin raise exception 'append-only table: % cannot be modified', tg_table_name; end $$;
create trigger loyalty_ledger_immutable before update or delete on public.loyalty_ledger for each row execute function app.deny_change();
create trigger staff_points_immutable before update or delete on public.staff_points_ledger for each row execute function app.deny_change();
create trigger audit_events_immutable before update or delete on public.audit_events for each row execute function app.deny_change();
create trigger task_events_immutable  before update or delete on public.task_events  for each row execute function app.deny_change();
create trigger payment_events_immutable before update or delete on public.payment_events for each row execute function app.deny_change();

-- ---------- 14. AVAILABILITY -------------------------------------------------
-- Server-side slot generation; a slot is bookable while active bookings < bay_count (CUS-022).
create or replace function public.get_available_slots(p_outlet uuid, p_service uuid, p_date date)
returns table (slot_start timestamptz, slot_end timestamptz, capacity int, booked int, available boolean)
language plpgsql stable as $$
#variable_conflict use_variable
declare
  v_outlet public.outlets%rowtype;
  v_dur int;
  v_hours jsonb;
  v_open time; v_close time;
  v_cursor timestamptz; v_day_end timestamptz;
  v_dow text;
begin
  select * into v_outlet from public.outlets where id = p_outlet and is_active;
  if not found then return; end if;
  select duration_minutes into v_dur from public.services where id = p_service;
  v_dur := coalesce(v_dur, v_outlet.slot_minutes);
  v_dow := lower(to_char(p_date, 'Dy'));
  v_hours := v_outlet.opening_hours -> v_dow;
  if v_hours is null or jsonb_typeof(v_hours) = 'null' then return; end if;
  v_open  := (v_hours ->> 0)::time;
  v_close := (v_hours ->> 1)::time;
  v_cursor  := (p_date::text || ' ' || v_open::text)::timestamp at time zone v_outlet.timezone;
  v_day_end := (p_date::text || ' ' || v_close::text)::timestamp at time zone v_outlet.timezone;
  while v_cursor + make_interval(mins => v_dur) <= v_day_end loop
    slot_start := v_cursor;
    slot_end   := v_cursor + make_interval(mins => v_dur);
    capacity   := v_outlet.bay_count;
    select count(*)::int into booked from public.bookings b
      where b.outlet_id = p_outlet and b.status in ('pending','confirmed','in_service')
        and b.slot_start < slot_end and b.slot_end > slot_start;
    available := booked < capacity and slot_start > now();
    return next;
    v_cursor := v_cursor + make_interval(mins => v_outlet.slot_minutes);
  end loop;
end $$;

-- ---------- 15. VIEWS (read models) -----------------------------------------
create or replace view public.v_work_order_progress as
select w.id as work_order_id,
       coalesce(jsonb_array_length(t.steps),0) as step_count,
       (select count(*) from public.checklist_step_results r where r.work_order_id = w.id and r.status = 'done')::int as steps_done
from public.work_orders w
left join public.checklist_templates t on t.id = w.checklist_template_id;

create or replace view public.v_staff_points as
select staff_id, outlet_id, sum(delta)::int as points,
       sum(delta) filter (where created_at >= date_trunc('week', now()))::int as points_week,
       sum(delta) filter (where created_at >= date_trunc('month', now()))::int as points_month
from public.staff_points_ledger group by staff_id, outlet_id;

-- ---------- 16. ROW LEVEL SECURITY (API-008 / ARC-005) ----------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Public catalogue (read)
create policy outlets_read on public.outlets for select using (true);
create policy services_read on public.services for select using (true);
create policy outlet_services_read on public.outlet_services for select using (true);
create policy rewards_read on public.rewards for select using (true);
create policy badges_read on public.badges for select using (true);
create policy feature_flags_read on public.feature_flags for select using (true);
create policy templates_read on public.checklist_templates for select using (app.is_staff());
create policy loyalty_config_read on public.loyalty_configs for select using (status = 'published' or app.is_manager());
create policy gamification_rules_read on public.gamification_rules for select using (app.is_staff());
create policy notification_templates_read on public.notification_templates for select using (app.is_manager());

-- Profiles: self, or staff of a shared outlet, or managers/admin
create policy profiles_self on public.profiles for select using (id = app.uid());
create policy profiles_staff_read on public.profiles for select using (app.is_staff() and role <> 'customer');
create policy profiles_customer_for_staff on public.profiles for select using (
  app.is_staff() and exists (select 1 from public.bookings b where b.customer_id = profiles.id and app.can_see_outlet(b.outlet_id)));
create policy profiles_self_update on public.profiles for update using (id = app.uid())
  with check (id = app.uid() and role = (select p.role from public.profiles p where p.id = app.uid()));

create policy staff_outlets_read on public.staff_outlets for select using (profile_id = app.uid() or app.is_staff());
create policy staff_skills_read  on public.staff_skills  for select using (app.is_staff());
create policy staff_availability_read on public.staff_availability for select using (app.is_staff());
create policy staff_availability_self on public.staff_availability for update using (profile_id = app.uid());
create policy device_tokens_self on public.device_tokens for all using (profile_id = app.uid()) with check (profile_id = app.uid());

-- Customer-owned data
create policy vehicles_owner on public.vehicles for select using (customer_id = app.uid());
create policy vehicles_staff on public.vehicles for select using (app.is_staff());
create policy vehicles_owner_insert on public.vehicles for insert with check (customer_id = app.uid());
create policy vehicles_owner_update on public.vehicles for update using (customer_id = app.uid());

create policy bookings_owner on public.bookings for select using (customer_id = app.uid());
create policy bookings_staff on public.bookings for select using (app.is_staff() and app.can_see_outlet(outlet_id));
create policy quotations_owner on public.quotations for select using (customer_id = app.uid());
create policy quotations_staff on public.quotations for select using (app.is_staff() and app.can_see_outlet(outlet_id));
create policy attachments_read on public.attachments for select using (uploaded_by = app.uid() or app.is_staff());

create policy work_orders_customer on public.work_orders for select using (customer_id = app.uid());
create policy work_orders_staff on public.work_orders for select using (app.is_staff() and app.can_see_outlet(outlet_id));
create policy tasks_staff on public.tasks for select using (app.is_staff() and app.can_see_outlet(outlet_id));
create policy task_events_staff on public.task_events for select using (
  app.is_staff() and exists (select 1 from public.work_orders w where w.id = task_events.work_order_id and app.can_see_outlet(w.outlet_id)));
create policy step_results_customer on public.checklist_step_results for select using (
  exists (select 1 from public.work_orders w where w.id = checklist_step_results.work_order_id and w.customer_id = app.uid()));
create policy step_results_staff on public.checklist_step_results for select using (
  app.is_staff() and exists (select 1 from public.work_orders w where w.id = checklist_step_results.work_order_id and app.can_see_outlet(w.outlet_id)));

create policy payment_methods_owner on public.payment_methods for select using (customer_id = app.uid());
create policy payments_owner on public.payments for select using (customer_id = app.uid());
create policy payments_finance on public.payments for select using (app.role() in ('finance','admin','manager'));
create policy payment_events_finance on public.payment_events for select using (app.role() in ('finance','admin'));

create policy loyalty_accounts_owner on public.loyalty_accounts for select using (customer_id = app.uid() or app.is_manager());
create policy loyalty_ledger_owner on public.loyalty_ledger for select using (customer_id = app.uid() or app.is_manager());
create policy redemptions_owner on public.reward_redemptions for select using (customer_id = app.uid() or app.is_staff());

create policy inventory_items_staff on public.inventory_items for select using (app.is_staff() and app.can_see_outlet(outlet_id));
create policy inventory_movements_staff on public.inventory_movements for select using (
  app.is_staff() and exists (select 1 from public.inventory_items i where i.id = inventory_movements.item_id and app.can_see_outlet(i.outlet_id)));
create policy inventory_alerts_staff on public.inventory_alerts for select using (app.is_staff() and app.can_see_outlet(outlet_id));

create policy staff_points_read on public.staff_points_ledger for select using (staff_id = app.uid() or (app.is_staff() and app.can_see_outlet(outlet_id)));
create policy staff_badges_read on public.staff_badges for select using (app.is_staff());

create policy notifications_owner on public.notifications for select using (recipient_id = app.uid());
create policy notifications_owner_read_mark on public.notifications for update using (recipient_id = app.uid()) with check (recipient_id = app.uid());
create policy audit_read on public.audit_events for select using (app.is_admin() or (app.is_manager() and app.can_see_outlet(outlet_id)));
create policy sync_ops_owner on public.sync_operations for select using (profile_id = app.uid());

-- ---------- 17. REALTIME (ARC-003 / API-007) --------------------------------
drop publication if exists supabase_realtime;
create publication supabase_realtime for table
  public.bookings, public.quotations, public.work_orders, public.tasks, public.checklist_step_results,
  public.payments, public.loyalty_ledger, public.loyalty_accounts, public.inventory_items, public.inventory_alerts,
  public.notifications, public.staff_points_ledger, public.staff_availability;

-- Realtime needs REPLICA IDENTITY FULL for RLS filtering on updates/deletes.
do $$
declare t text;
begin
  foreach t in array array['bookings','quotations','work_orders','tasks','checklist_step_results','payments','loyalty_ledger','loyalty_accounts','inventory_items','inventory_alerts','notifications','staff_points_ledger','staff_availability']
  loop execute format('alter table public.%I replica identity full', t); end loop;
end $$;

-- ---------- 18. GRANTS -------------------------------------------------------
grant select on all tables in schema public to anon, authenticated;
grant update (full_name, phone, avatar_url, marketing_opt_in, whatsapp_opt_in, push_opt_in, locale, reduced_motion, haptics, last_seen_at) on public.profiles to authenticated;
grant insert, update on public.vehicles to authenticated;
grant all on public.device_tokens to authenticated;
grant update (status, capacity, updated_at) on public.staff_availability to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on function public.get_available_slots(uuid, uuid, date) to anon, authenticated, service_role;
