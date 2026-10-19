-- 0023: when the customer intends to pay. A booking is either paid online when it is made
-- (`booking`) or settled at the counter — at check-in, before the wash (`checkin`), or on
-- collection, after it (`collection`). Counter bookings keep `payment_method = 'cash'` (the
-- existing "pay at the counter" choice, feature flag `cash_on_collection`); `pay_at` only says
-- when staff should ask for it. The hand-over gate (`payment_due`) is unchanged: keys are not
-- released while a counter booking is unpaid, whichever moment the customer picked.
alter table public.bookings
  add column if not exists pay_at text check (pay_at in ('booking', 'checkin', 'collection'));
comment on column public.bookings.pay_at is 'When the customer chose to pay: booking (online, when booking), checkin (counter, before the wash) or collection (counter, after the wash). Counter bookings carry payment_method = cash.';

-- Backfill: cash bookings were always settled on collection; card / EFT bookings paid online.
update public.bookings set pay_at = 'collection' where pay_at is null and payment_method = 'cash';
update public.bookings set pay_at = 'booking' where pay_at is null and payment_method in ('card', 'eft');

update public.feature_flags
   set description = 'Allow customers to pay at the counter instead of online — at check-in or on collection; the payment is recorded at the counter before the vehicle is released'
 where key = 'cash_on_collection';
