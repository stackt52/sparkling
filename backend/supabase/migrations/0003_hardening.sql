-- Migration 0003: security hardening from the Supabase advisor run (SEC-003/004)
-- 1. Views evaluate RLS as the querying user, not the view owner.
alter view public.v_work_order_progress set (security_invoker = on);
alter view public.v_staff_points set (security_invoker = on);

-- 2. Pin search_path on every function (prevents search-path hijacking).
do $$
declare r record;
begin
  for r in select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('app','public')
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('alter function %I.%I(%s) set search_path = pg_catalog, public, extensions', r.nspname, r.proname, r.args);
  end loop;
end $$;

-- 3. Anonymous callers may only read the public catalogue; everything else needs a signed-in identity.
revoke select on all tables in schema public from anon;
grant select on public.outlets, public.services, public.outlet_services, public.rewards, public.badges, public.feature_flags to anon;
alter default privileges in schema public revoke select on tables from anon;

-- 4. Server-only tables: no client role may read them at all.
revoke all on public.idempotency_keys from anon, authenticated;
revoke all on public.payment_events from anon, authenticated;
