-- 0018: `director` role — identical rights to `admin` (dashboard, every outlet, user management).
-- The enum value is added first; the helpers below compare the JWT `role` claim as text, so they may be
-- replaced in the same migration.
alter type public.user_role add value if not exists 'director';

create or replace function app.is_staff() returns boolean
language sql stable as $$ select app.role() in ('technician','supervisor','manager','admin','director','finance') $$;

create or replace function app.is_manager() returns boolean
language sql stable as $$ select app.role() in ('manager','admin','director') $$;

create or replace function app.is_admin() returns boolean
language sql stable as $$ select app.role() in ('admin','director') $$;

-- Policies that list roles literally.
drop policy if exists payments_finance on public.payments;
create policy payments_finance on public.payments for select using (app.role() in ('finance','admin','director','manager'));
drop policy if exists payment_events_finance on public.payment_events;
create policy payment_events_finance on public.payment_events for select using (app.role() in ('finance','admin','director'));

-- `create or replace` drops the search_path pin from 0003 — restore it on every function touched here (and on
-- app.role(), which a hotfix on the project replaced without the pin).
alter function app.is_staff()   set search_path = pg_catalog, public, extensions;
alter function app.is_manager() set search_path = pg_catalog, public, extensions;
alter function app.is_admin()   set search_path = pg_catalog, public, extensions;
alter function app.role()       set search_path = pg_catalog, public, extensions;
