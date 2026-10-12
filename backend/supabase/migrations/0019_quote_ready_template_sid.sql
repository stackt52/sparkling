-- 0019: new approved Twilio Content template for `quote_ready` (WhatsApp). Same placeholders as before:
-- {{1}} = first_name, {{2}} = public_token (button URL <PUBLIC_WEB_BASE_URL>/q/{{2}}).
update public.notification_templates
   set provider_template_sid = 'HXded96b02f33c4fa2ff9881a05d918172',
       provider_variables    = '{"1":"first_name","2":"public_token"}'::jsonb,
       version               = version + 1
 where key = 'quote_ready' and channel = 'whatsapp' and provider = 'twilio';
