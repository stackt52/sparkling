-- Migration 0006: staff-raised quotations, damage photos and the public quote page
-- (CUS-030..034, STF-010/012, INT-002; docs/API.md "Staff-raised quotations, damage photos & public quote page")
-- Idempotent: safe to re-run.

-- Quotations: public link token (rotated by POST /quotations/:id/share), decision provenance, PDF bookkeeping.
alter table public.quotations
  add column if not exists public_token            uuid unique,                      -- link token: ${PUBLIC_WEB_BASE_URL}/q/<token>
  add column if not exists public_token_expires_at timestamptz,                      -- 30 days from issue / rotation
  add column if not exists decision_source         text check (decision_source in ('app', 'public_link', 'staff')),
  add column if not exists decision_by_name        text,                             -- name typed on the public page (accepted_by_name) or the profile name
  add column if not exists items_note              text,                             -- free-text note under the items table
  add column if not exists pdf_generated_at        timestamptz;                      -- first time the PDF was rendered

create index if not exists quotations_public_token_idx on public.quotations(public_token) where public_token is not null;

-- Attachments: damage photos are served through the API (never a raw bucket URL).
alter table public.attachments
  add column if not exists kind    text not null default 'document',                 -- 'damage_photo' | 'document'
  add column if not exists width   int,
  add column if not exists height  int,
  add column if not exists caption text;

-- quote_ready WhatsApp: Content template variable 2 is now the public token (button URL <PUBLIC_WEB_BASE_URL>/q/{{2}}).
insert into public.notification_templates (key, channel, title, body, is_promotional, provider, provider_template_sid, provider_variables) values
 ('quote_ready', 'whatsapp', null, 'Hi {{first_name}}, your Sparkling quotation {{ref}} is ready: {{public_url}}', false,
  'twilio', 'HX011c7f1b31697f8e21d36ff6b4d02b06', '{"1":"first_name","2":"public_token"}')
on conflict (key, channel) do update set
  body = excluded.body,
  provider = excluded.provider,
  provider_template_sid = excluded.provider_template_sid,
  provider_variables = excluded.provider_variables,
  version = public.notification_templates.version + 1;

-- quote_ready push: only inserted when missing (the seed already ships one).
insert into public.notification_templates (key, channel, title, body, is_promotional, provider, provider_template_sid, provider_variables) values
 ('quote_ready', 'push', 'Your quotation is ready', '{{ref}}: R {{amount}}. Review it in the app.', false, null, null, '{}')
on conflict (key, channel) do nothing;

-- Decision notifications: outlet staff (assessor + supervisors/managers) and the customer receipt.
insert into public.notification_templates (key, channel, title, body, is_promotional, provider, provider_template_sid, provider_variables) values
 ('quote_decided', 'push', 'Quotation {{decision}}', '{{ref}} {{decision}} by {{customer}}', false, null, null, '{}'),
 ('quote_decision_receipt', 'push', 'Quotation {{decision}}', 'Thanks {{first_name}}, quotation {{ref}} was {{decision}}.', false, null, null, '{}'),
 ('quote_decision_receipt', 'whatsapp', null, 'Thanks {{first_name}}, quotation {{ref}} was {{decision}}.', false, null, null, '{}')
on conflict (key, channel) do update set
  title = excluded.title,
  body = excluded.body,
  provider = excluded.provider,
  provider_template_sid = excluded.provider_template_sid,
  provider_variables = excluded.provider_variables,
  version = public.notification_templates.version + 1;
