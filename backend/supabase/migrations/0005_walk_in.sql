-- Migration 0005: walk-in customers, staff-created bookings and POS payment attestation
-- (STF-010/012, CUS-020..025 on behalf of a customer; docs/API.md "Staff — walk-in customers & bookings")
-- Idempotent: safe to re-run.

-- In-person payments recorded by staff (`POST /v1/payments/record`).
-- `payments.provider` is already free text ('pos' needs no change).
alter table public.payments
  add column if not exists method      text,                                    -- cash | card_terminal | card | eft
  add column if not exists recorded_by text references public.profiles(id) on update cascade;  -- staff member who attested the payment

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payments_method_check') then
    alter table public.payments
      add constraint payments_method_check check (method is null or method in ('cash', 'card_terminal', 'card', 'eft'));
  end if;
end $$;

create index if not exists payments_recorded_by_idx on public.payments(recorded_by) where recorded_by is not null;

-- Walk-in bookings created by staff at the counter (status starts `confirmed`).
alter table public.bookings
  add column if not exists walk_in boolean not null default false;

-- Convenience flag: booking made by someone other than the customer (staff on behalf of).
alter table public.bookings
  add column if not exists created_by_staff boolean generated always as (created_by is not null and created_by <> customer_id) stored;

create index if not exists bookings_walk_in_idx on public.bookings(outlet_id, slot_start) where walk_in;

-- Phone lookups: walk-in registration dedupe, customer search and profile claim on sign-up
-- (`walkin_<uuid>` profiles are claimed by e-mail OR phone in POST /v1/auth/session).
create index if not exists profiles_phone_idx on public.profiles(phone) where phone is not null;
