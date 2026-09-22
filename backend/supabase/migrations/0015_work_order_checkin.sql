-- 0015: explicit vehicle check-in on work orders. A work order can only be assigned (manually or by
-- auto-assignment) once the car has been confirmed on site. Booking check-ins set it immediately;
-- work orders converted from quotations wait for staff/admin confirmation.
alter table public.work_orders
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_in_by text references public.profiles(id) on update cascade;
create index if not exists work_orders_awaiting_checkin_idx on public.work_orders (outlet_id) where checked_in_at is null and status in ('queued', 'assigned');
-- Backfill: every existing work order that has started, or came from a booking check-in, counts as checked in.
update public.work_orders set checked_in_at = coalesce(started_at, created_at) where checked_in_at is null and (booking_id is not null or started_at is not null);
