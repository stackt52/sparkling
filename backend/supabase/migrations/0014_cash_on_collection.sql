-- 0014: customers may choose "Cash on collection" when booking (paid at the counter before the keys are released).
alter table public.bookings
  add column if not exists payment_method text check (payment_method in ('card', 'eft', 'cash'));
comment on column public.bookings.payment_method is 'Customer''s chosen payment method at booking time; cash = pay at the counter on collection (feature flag cash_on_collection).';

insert into public.feature_flags (key, enabled, description)
values ('cash_on_collection', true, 'Allow customers to choose "Cash on collection" when booking; the cash payment is recorded at the counter before the vehicle is released')
on conflict (key) do nothing;
