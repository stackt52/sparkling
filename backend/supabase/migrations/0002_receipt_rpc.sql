-- Migration 0002: receipt number RPC (callable through PostgREST by the service role)
create or replace function public.next_receipt_no() returns text
language sql volatile security definer as $$
  select 'RCP-' || nextval('public.receipt_ref_seq')::text
$$;
revoke all on function public.next_receipt_no() from public, anon, authenticated;
grant execute on function public.next_receipt_no() to service_role;
