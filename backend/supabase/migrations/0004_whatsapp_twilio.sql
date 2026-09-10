-- Migration 0004: Twilio WhatsApp Content templates + vehicle-collection OTP
-- (replicates the legacy sparkling-admin "quote ready" and "car pick-up" WhatsApp flows; INT-002, NOT-001/003)

-- Provider template binding for approved WhatsApp Content templates.
alter table public.notification_templates
  add column if not exists provider             text,                  -- 'twilio'
  add column if not exists provider_template_sid text,                 -- Twilio Content SID (HX…)
  add column if not exists provider_variables   jsonb not null default '{}'; -- {"1":"first_name","2":"quotation_id"} → positional vars from render context

-- Delivery receipts from the provider status callback.
alter table public.notifications
  add column if not exists delivered_at  timestamptz,
  add column if not exists read_by_recipient_at timestamptz,
  add column if not exists provider_status text,                       -- raw provider status (queued/sent/delivered/read/failed/undelivered)
  add column if not exists provider_error_code text;
create index if not exists notifications_provider_ref_idx on public.notifications(provider_ref) where provider_ref is not null;

-- Vehicle collection OTP: issued when the work order is verified, presented by the customer at handover.
alter table public.work_orders
  add column if not exists pickup_otp            text,
  add column if not exists pickup_otp_issued_at  timestamptz,
  add column if not exists pickup_otp_verified_at timestamptz,
  add column if not exists pickup_otp_verified_by text references public.profiles(id) on update cascade,
  add column if not exists collected_at          timestamptz;

-- Template bindings (Content SIDs from the legacy project's approved templates).
insert into public.notification_templates (key, channel, title, body, is_promotional, provider, provider_template_sid, provider_variables) values
 ('quote_ready', 'whatsapp', null, 'Hi {{first_name}}, your quotation {{ref}} is ready. Review it in the Sparkling app.', false,
  'twilio', 'HX011c7f1b31697f8e21d36ff6b4d02b06', '{"1":"first_name","2":"quotation_id"}'),
 ('service_ready', 'whatsapp', null, 'Thank you for visiting Sparkling Auto. Your {{vehicle}} is ready at {{outlet}}. Present OTP {{otp}} to collect your keys.', false,
  'twilio', 'HX63a748f8b6680eac890e0137dfcf0fdb', '{"1":"otp"}'),
 ('pickup_otp', 'whatsapp', null, 'Your Sparkling collection OTP is {{otp}}. Present it at {{outlet}} to collect your keys.', false,
  'twilio', 'HX63a748f8b6680eac890e0137dfcf0fdb', '{"1":"otp"}'),
 ('pickup_otp', 'push', 'Collection OTP', 'Show OTP {{otp}} at {{outlet}} to collect your {{vehicle}}.', false, null, null, '{}')
on conflict (key, channel) do update set
  body = excluded.body,
  provider = excluded.provider,
  provider_template_sid = excluded.provider_template_sid,
  provider_variables = excluded.provider_variables,
  version = public.notification_templates.version + 1;

-- The customer may see their own OTP through the API only (never via anon/PostgREST column grants to other users);
-- keep RLS as-is: work_orders_customer policy already scopes rows to the owner.
