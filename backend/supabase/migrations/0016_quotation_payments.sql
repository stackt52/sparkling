-- 0016: counter (cash / card-terminal) payments can settle an accepted quotation, not only a booking.
alter table public.payments
  add column if not exists quotation_id uuid references public.quotations(id);
create index if not exists payments_quotation_idx on public.payments (quotation_id) where quotation_id is not null;
alter table public.payments drop constraint if exists payments_target_check;
alter table public.payments add constraint payments_target_check
  check (num_nonnulls(booking_id, quotation_id, membership_invoice_id) <= 1);
