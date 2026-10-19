-- 0021: supervisor verification requests. When a checklist reaches its `supervisor_verify` step (every
-- step before it is done) or the technician completes the task, the task is flagged as awaiting
-- supervisor sign-off: it appears on the "Mine" tab of every supervisor at the outlet and they get a
-- `task_verify_requested` push. Cleared when the task goes back to in_progress (rework).
alter table public.tasks
  add column if not exists verification_requested_at timestamptz;
create index if not exists tasks_awaiting_verification_idx on public.tasks (outlet_id)
  where verification_requested_at is not null and status in ('in_progress', 'blocked', 'completed');

-- Backfill: completed work that is still waiting for a supervisor.
update public.tasks set verification_requested_at = coalesce(completed_at, updated_at)
  where verification_requested_at is null and status = 'completed';

insert into public.notification_templates (key, channel, title, body, is_promotional)
values ('task_verify_requested', 'push', 'Verification needed', '{{ref}} · {{service}} · bay {{bay}} is ready for your sign-off.', false)
on conflict (key, channel) do update set title = excluded.title, body = excluded.body;
