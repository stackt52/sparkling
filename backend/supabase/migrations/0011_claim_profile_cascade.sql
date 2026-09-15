-- 0011: let a profile-id rename cascade through append-only tables.
--
-- POST /auth/session claims a seeded / walk-in profile by changing profiles.id to the Firebase UID.
-- Every FK to profiles is `on update cascade`, so the rename touches loyalty_ledger, staff_points_ledger,
-- task_events and membership_usage rows — whose BEFORE UPDATE trigger (app.deny_change) rejected the
-- cascade with "append-only table … cannot be modified" and the sign-in failed with a 500.
-- Deletes stay forbidden; updates are allowed only when nothing but a profile-reference column changed.
create or replace function app.deny_change() returns trigger
language plpgsql as $$
declare
  ref_cols text[] := array['customer_id', 'created_by', 'staff_id', 'actor_id', 'recorded_by', 'profile_id'];
  o jsonb; n jsonb; c text;
begin
  if tg_op = 'UPDATE' then
    o := to_jsonb(old); n := to_jsonb(new);
    foreach c in array ref_cols loop
      o := o - c; n := n - c;
    end loop;
    if o = n then
      return new;               -- only profile references changed → FK cascade from a profile claim
    end if;
  end if;
  raise exception 'append-only table: % cannot be modified', tg_table_name;
end $$;
