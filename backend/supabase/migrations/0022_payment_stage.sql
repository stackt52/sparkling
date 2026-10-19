-- 0022: when a payment was captured. Bookings can now be settled at three moments — online when
-- booking (`booking`), at the counter when the car is checked in (`checkin`) or when it is collected
-- (`collection`). Counter payments (`POST /payments/record`, provider `pos`) may be cash, card terminal
-- or an EFT reference and may be captured by outlet staff or dashboard users; the stage is inferred
-- from the booking / work order unless the check-in or hand-over call carried the payment itself.
alter table public.payments
  add column if not exists stage text check (stage in ('booking', 'checkin', 'collection'));
comment on column public.payments.stage is 'When the payment was captured: booking (online, at booking time), checkin (counter, car checked in) or collection (counter, hand-over).';

-- Backfill: online provider payments were taken at booking time; existing counter payments were
-- recorded on collection (the only staff path before this migration).
update public.payments set stage = 'booking' where stage is null and provider <> 'pos';
update public.payments set stage = 'collection' where stage is null and provider = 'pos' and booking_id is not null;
