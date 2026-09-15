-- 0012: staff accounts created from the admin app must change their temporary password on first sign-in.
alter table public.profiles
  add column if not exists must_change_password boolean not null default false,
  add column if not exists password_changed_at  timestamptz;
