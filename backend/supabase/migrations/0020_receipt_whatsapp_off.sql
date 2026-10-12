-- 0020: the customer's quote decision receipt goes out on push + in-app only. Its WhatsApp row had no
-- Content template, so it was sent free-form and failed outside the 24-hour session window (Twilio 63016).
update public.notification_templates
   set is_active = false,
       version   = version + 1
 where key = 'quote_decision_receipt' and channel = 'whatsapp';
