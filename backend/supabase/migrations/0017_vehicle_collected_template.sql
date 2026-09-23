-- 0017: push the customer when their keys are handed over (collection OTP verified).
insert into public.notification_templates (key, channel, title, body, is_promotional)
values ('vehicle_collected', 'push', 'Keys collected', 'Your {{vehicle}} was collected from {{outlet}} at {{time}}. Thank you for choosing Sparkling!', false)
on conflict (key, channel) do update set title = excluded.title, body = excluded.body;
