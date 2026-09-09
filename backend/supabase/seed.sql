-- =============================================================================
-- Sparkling — demo seed (South African sample data matching the design handoff)
-- Safe to re-run: truncates all business tables first.
-- Profiles use placeholder ids ("seed_*"). On first sign-in the API claims a seed
-- profile by e-mail and rewrites its id to the real Firebase UID (FKs cascade).
-- =============================================================================
begin;

truncate table
  public.audit_events, public.sync_operations, public.idempotency_keys, public.notifications,
  public.staff_badges, public.staff_points_ledger, public.reward_redemptions, public.loyalty_ledger,
  public.loyalty_accounts, public.inventory_alerts, public.inventory_movements, public.inventory_items,
  public.payment_events, public.payments, public.payment_methods, public.checklist_step_results,
  public.task_events, public.tasks, public.work_orders, public.bookings, public.quotations, public.attachments,
  public.vehicles, public.device_tokens, public.staff_availability, public.staff_skills, public.staff_outlets,
  public.outlet_services, public.services, public.checklist_templates, public.profiles, public.outlets,
  public.rewards, public.badges, public.gamification_rules, public.loyalty_configs, public.notification_templates,
  public.feature_flags
restart identity cascade;

-- ---------- Outlets ----------------------------------------------------------
insert into public.outlets (id, code, name, address_line, city, province, latitude, longitude, phone, email, bay_count, rating) values
 ('a0000000-0000-4000-8000-000000000001','SAN','Sparkling Sandton','14 Rivonia Rd, Sandton','Johannesburg','Gauteng',-26.1076,28.0567,'+27 11 555 0101','sandton@sparkling.co.za',4,4.8),
 ('a0000000-0000-4000-8000-000000000002','ROS','Sparkling Rosebank','Cradock Ave, Rosebank','Johannesburg','Gauteng',-26.1450,28.0430,'+27 11 555 0102','rosebank@sparkling.co.za',3,4.7),
 ('a0000000-0000-4000-8000-000000000003','CEN','Sparkling Centurion','Lenchen Ave, Centurion','Centurion','Gauteng',-25.8600,28.1890,'+27 12 555 0103','centurion@sparkling.co.za',3,4.6);

-- ---------- Checklist templates (STF-031) -----------------------------------
insert into public.checklist_templates (id, name, category, version, status, steps) values
 ('c0000000-0000-4000-8000-000000000001','Full valet checklist','car_wash',3,'published','[
   {"key":"prewash","title":"Pre-wash inspection","type":"photo","required":true,"hint":"Photograph all four sides before starting","photo_required":true},
   {"key":"exterior","title":"Exterior wash & rinse","type":"confirm","required":true},
   {"key":"wheels","title":"Wheels, arches & tyre shine","type":"confirm","required":true},
   {"key":"interior","title":"Interior vacuum & dash","type":"confirm","required":true,"hint":"Include boot and door pockets"},
   {"key":"windows","title":"Windows inside & out","type":"confirm","required":true},
   {"key":"tyre_pressure","title":"Tyre pressure check","type":"numeric","required":true,"unit":"bar","min":1.5,"max":3.5,"hint":"Record front-left pressure"},
   {"key":"supervisor","title":"Supervisor verification","type":"supervisor_verify","required":true,"hint":"Locked until all required steps pass"}
 ]'),
 ('c0000000-0000-4000-8000-000000000002','Express wash checklist','car_wash',2,'published','[
   {"key":"exterior","title":"Exterior wash & rinse","type":"confirm","required":true},
   {"key":"wheels","title":"Wheels & tyres","type":"confirm","required":true},
   {"key":"dry","title":"Hand dry & windows","type":"confirm","required":true},
   {"key":"supervisor","title":"Supervisor verification","type":"supervisor_verify","required":false}
 ]'),
 ('c0000000-0000-4000-8000-000000000003','Auto body repair checklist','auto_body',1,'published','[
   {"key":"intake","title":"Damage intake photos","type":"photo","required":true,"photo_required":true},
   {"key":"prep","title":"Panel prep & masking","type":"confirm","required":true},
   {"key":"repair","title":"Repair / filler / sanding","type":"confirm","required":true},
   {"key":"paint","title":"Paint & clear coat","type":"select","required":true,"options":["Spot","Panel","Blend"]},
   {"key":"cure","title":"Cure time (hours)","type":"numeric","required":true,"unit":"h","min":1,"max":48},
   {"key":"polish","title":"Polish & final photos","type":"photo","required":true,"photo_required":true},
   {"key":"supervisor","title":"Supervisor verification","type":"supervisor_verify","required":true}
 ]');

-- ---------- Services ---------------------------------------------------------
insert into public.services (id, code, name, description, category, duration_minutes, base_price_cents, is_quote_based, icon, checklist_template_id, sort_order) values
 ('b0000000-0000-4000-8000-000000000001','EXPRESS','Express Wash','Exterior wash, wheels and hand dry',                'car_wash',20,12000,false,'water_drop','c0000000-0000-4000-8000-000000000002',10),
 ('b0000000-0000-4000-8000-000000000002','VALET','Full Valet','Exterior + interior vacuum, dash and windows',        'car_wash',60,22000,false,'local_car_wash','c0000000-0000-4000-8000-000000000001',20),
 ('b0000000-0000-4000-8000-000000000003','DETAIL','Premium Detail','Clay bar, polish, wax and full interior detail','car_wash',120,45000,false,'auto_awesome','c0000000-0000-4000-8000-000000000001',30),
 ('b0000000-0000-4000-8000-000000000004','INTERIOR','Interior Deep Clean','Seats, carpets and upholstery shampoo',    'car_wash',90,28000,false,'cleaning_services','c0000000-0000-4000-8000-000000000001',40),
 ('b0000000-0000-4000-8000-000000000011','DENT','Dent removal','Paintless dent removal',                              'auto_body',240,0,true,'car_crash','c0000000-0000-4000-8000-000000000003',110),
 ('b0000000-0000-4000-8000-000000000012','SCRATCH','Scratch repair','Scratch and scuff repair with blend',           'auto_body',240,0,true,'car_crash','c0000000-0000-4000-8000-000000000003',120),
 ('b0000000-0000-4000-8000-000000000013','BUMPER','Bumper repair','Plastic bumper repair and respray',              'auto_body',480,0,true,'car_crash','c0000000-0000-4000-8000-000000000003',130),
 ('b0000000-0000-4000-8000-000000000014','PANEL','Panel respray','Single panel respray',                            'auto_body',960,0,true,'car_crash','c0000000-0000-4000-8000-000000000003',140);

insert into public.outlet_services (outlet_id, service_id, price_cents, is_available)
select o.id, s.id, null, true from public.outlets o cross join public.services s;
update public.outlet_services set price_cents = 24000 where outlet_id = 'a0000000-0000-4000-8000-000000000001' and service_id = 'b0000000-0000-4000-8000-000000000002';
update public.outlet_services set is_available = false where outlet_id = 'a0000000-0000-4000-8000-000000000003' and service_id = 'b0000000-0000-4000-8000-000000000014';

-- ---------- People -----------------------------------------------------------
insert into public.profiles (id, role, full_name, email, phone, marketing_opt_in) values
 ('seed_admin',      'admin',      'Sparkling Admin',       'admin@sparkling.co.za',    '+27 82 000 0001', false),
 ('seed_finance',    'finance',    'Nomvula Finance',       'finance@sparkling.co.za',  '+27 82 000 0002', false),
 ('seed_ayesha',     'manager',    'Ayesha Patel',          'ayesha@sparkling.co.za',   '+27 82 000 0010', false),
 ('seed_johan',      'supervisor', 'Johan Botha',           'johan@sparkling.co.za',    '+27 82 000 0011', false),
 ('seed_pieter',     'technician', 'Pieter van der Merwe',  'pieter@sparkling.co.za',   '+27 82 000 0012', false),
 ('seed_lerato',     'technician', 'Lerato Mahlangu',       'lerato@sparkling.co.za',   '+27 82 000 0013', false),
 ('seed_sipho_staff','technician', 'Sipho Ndlovu',          'sipho.n@sparkling.co.za',  '+27 82 000 0014', false),
 ('seed_thandi',     'technician', 'Thandi Khumalo',        'thandi@sparkling.co.za',   '+27 82 000 0015', false),
 ('seed_thabo',      'customer',   'Thabo Nkosi',           'thabo@example.com',        '+27 83 111 2222', true),
 ('seed_naledi',     'customer',   'Naledi Mokoena',        'naledi@example.com',       '+27 83 111 3333', false),
 ('seed_sipho',      'customer',   'Sipho Dlamini',         'sipho@example.com',        '+27 83 111 4444', true),
 ('seed_zanele',     'customer',   'Zanele Mthembu',        'zanele@example.com',       '+27 83 111 5555', true);

insert into public.staff_outlets (profile_id, outlet_id, is_primary) values
 ('seed_ayesha','a0000000-0000-4000-8000-000000000001',true),
 ('seed_ayesha','a0000000-0000-4000-8000-000000000002',false),
 ('seed_johan','a0000000-0000-4000-8000-000000000001',true),
 ('seed_pieter','a0000000-0000-4000-8000-000000000001',true),
 ('seed_lerato','a0000000-0000-4000-8000-000000000001',true),
 ('seed_sipho_staff','a0000000-0000-4000-8000-000000000001',true),
 ('seed_thandi','a0000000-0000-4000-8000-000000000002',true);

insert into public.staff_skills (profile_id, skill) values
 ('seed_pieter','wash'),('seed_pieter','detail'),('seed_lerato','wash'),('seed_lerato','interior'),
 ('seed_sipho_staff','wash'),('seed_sipho_staff','paint'),('seed_sipho_staff','panel'),('seed_thandi','wash');

insert into public.staff_availability (profile_id, status, capacity) values
 ('seed_pieter','available',3),('seed_lerato','busy',3),('seed_sipho_staff','busy',2),('seed_thandi','available',3),('seed_johan','available',5);

-- ---------- Vehicles ---------------------------------------------------------
insert into public.vehicles (id, customer_id, registration_no, vin, make, model, colour, year, licence_no, disc_expiry, source, disc_verified) values
 ('d0000000-0000-4000-8000-000000000001','seed_thabo','KL 45 MN GP','AHTFB3CB301234567','Toyota','Corolla Cross','Celestite Grey',2023,'ABC123456','2027-03-31','scan',true),
 ('d0000000-0000-4000-8000-000000000002','seed_thabo','CJ 12 PZ GP','WVWZZZ1KZ9W654321','Volkswagen','Polo Vivo','Reflex Silver',2019,null,'2026-11-30','manual',false),
 ('d0000000-0000-4000-8000-000000000003','seed_naledi','HR 88 TS GP','MA3FB1B4200123456','Suzuki','Swift','Pearl Arctic White',2022,'SW0091234','2027-01-31','scan',true),
 ('d0000000-0000-4000-8000-000000000004','seed_sipho','DN 07 KX GP','SB1KZ3BE10E234567','Toyota','Hilux','Glacier White',2021,'HX7711223','2026-10-15','scan',true),
 ('d0000000-0000-4000-8000-000000000005','seed_zanele','BW 33 RG GP','WBA5R1C50KA112233','BMW','330i','Portimao Blue',2020,'BM4451122','2027-05-31','scan',true);

-- ---------- Loyalty config v14 (published) + v15 draft (ADM-025) ------------
insert into public.loyalty_configs (id, version, status, tiers, rules, change_note, created_by, published_by, published_at) values
 ('e0000000-0000-4000-8000-000000000014',14,'published',
  '[{"tier":"silver","name":"Silver","min_points":0,"max_points":499,"earn_multiplier":1.0,"discount_pct":0},
    {"tier":"gold","name":"Gold","min_points":500,"max_points":1999,"earn_multiplier":1.25,"discount_pct":10},
    {"tier":"platinum","name":"Platinum","min_points":2000,"max_points":null,"earn_multiplier":1.5,"discount_pct":15}]',
  '{"points_per_rand":0.10,"award_on":"completion","idempotent_award":true,"expiry_months":24,"birthday_bonus":{"enabled":false,"points":100,"reason":"Pending consent review (ADM-042)"},"referral_bonus":{"enabled":true,"points":150}}',
  'Baseline tiers and earn rules','seed_admin','seed_admin', now() - interval '40 days'),
 ('e0000000-0000-4000-8000-000000000015',15,'draft',
  '[{"tier":"silver","name":"Silver","min_points":0,"max_points":499,"earn_multiplier":1.0,"discount_pct":0},
    {"tier":"gold","name":"Gold","min_points":500,"max_points":1999,"earn_multiplier":1.25,"discount_pct":10},
    {"tier":"platinum","name":"Platinum","min_points":2000,"max_points":null,"earn_multiplier":1.5,"discount_pct":15}]',
  '{"points_per_rand":0.12,"award_on":"completion","idempotent_award":true,"expiry_months":24,"birthday_bonus":{"enabled":false,"points":100,"reason":"Pending consent review (ADM-042)"},"referral_bonus":{"enabled":true,"points":200}}',
  'Raise earn rate to 0.12/R and referral bonus to 200','seed_ayesha',null,null);

insert into public.rewards (id, name, description, icon, points_cost, min_tier, sort_order) values
 ('f0000000-0000-4000-8000-000000000001','Free Express Wash','One express wash at any outlet','water_drop',600,'silver',10),
 ('f0000000-0000-4000-8000-000000000002','Interior refresh','Add-on interior vacuum and dash wipe','cleaning_services',350,'silver',20),
 ('f0000000-0000-4000-8000-000000000003','Full Valet upgrade','Upgrade any Express to a Full Valet','local_car_wash',900,'gold',30),
 ('f0000000-0000-4000-8000-000000000004','Premium Detail R150 off','Discount voucher for Premium Detail','auto_awesome',1200,'gold',40),
 ('f0000000-0000-4000-8000-000000000005','Priority bay','Skip the queue on your next visit','bolt',400,'platinum',50);

-- ---------- Gamification rules & badges (STF-051) ----------------------------
insert into public.gamification_rules (version, status, rules, created_by) values
 (3,'published','{"task_completed":25,"checklist_compliant":10,"verified_first_time":15,"p1_on_time":20,"blocked_resolved":5,"streak_5_days":50}','seed_admin');

insert into public.badges (id, code, name, description, icon, colour, criteria) values
 ('90000000-0000-4000-8000-000000000001','FIRST_50','Half century','Complete 50 tasks','military_tech','#E2BA5F','{"tasks_completed":50}'),
 ('90000000-0000-4000-8000-000000000002','STREAK_5','On a roll','5 verified tasks in a row','local_fire_department','#FF7A59','{"streak":5}'),
 ('90000000-0000-4000-8000-000000000003','SPOTLESS','Spotless','10 checklists with zero blocked steps','verified','#1D8A4E','{"compliant":10}'),
 ('90000000-0000-4000-8000-000000000004','SCANNER','Sharp eye','25 disc scans verified','qr_code_scanner','#00A0E0','{"scans":25}'),
 ('90000000-0000-4000-8000-000000000005','MENTOR','Mentor','Verify 20 colleague checklists','groups','#8BD2FF','{"verifications":20}'),
 ('90000000-0000-4000-8000-000000000006','TOP_MONTH','Top of the month','Finish #1 on a monthly leaderboard','social_leaderboard','#F3DDA4','{"rank":1}');

-- ---------- Notification templates (NOT-001) ---------------------------------
insert into public.notification_templates (key, channel, title, body, is_promotional) values
 ('booking_confirmed','push','Booking confirmed','{{service}} at {{outlet}} on {{slot}}. Ref {{ref}}.',false),
 ('booking_confirmed','whatsapp',null,'Hi {{name}}, your Sparkling booking {{ref}} is confirmed for {{slot}} at {{outlet}}. Reply STOP to opt out of promos.',false),
 ('service_started','push','Service started','Your {{vehicle}} is now in bay {{bay}}.',false),
 ('stage_changed','push','Progress update','{{vehicle}}: {{stage}} complete.',false),
 ('service_ready','push','Ready for collection','Your {{vehicle}} is ready at {{outlet}}.',false),
 ('service_ready','whatsapp',null,'Your {{vehicle}} is sparkling and ready for collection at {{outlet}}. Ref {{ref}}.',false),
 ('payment_successful','push','Payment received','R {{amount}} received. Receipt {{receipt}}.',false),
 ('payment_failed','push','Payment failed','We could not process R {{amount}}. Tap to retry.',false),
 ('quote_ready','push','Your quotation is ready','{{ref}}: R {{amount}}. Accept or decline in the app.',false),
 ('quote_ready','whatsapp',null,'Your Sparkling quotation {{ref}} for R {{amount}} is ready. Open the app to accept or decline.',false),
 ('points_posted','push','Points posted','+{{points}} pts added. Balance {{balance}}.',false),
 ('low_stock','push','Low stock alert','{{item}} at {{outlet}} is below threshold ({{on_hand}}/{{threshold}}).',false),
 ('task_assigned','push','New task','{{ref}} assigned to you · {{service}} · bay {{bay}}.',false),
 ('promo_weekend','whatsapp',null,'Weekend special: 15% off Premium Detail. Book in the Sparkling app.',true);

insert into public.feature_flags (key, enabled, description) values
 ('payments_sandbox', true, 'Use the sandbox payment provider (no real charges)'),
 ('whatsapp_enabled', false, 'Send WhatsApp Business notifications'),
 ('auto_assignment', true, 'Automatically assign queued work orders to available staff'),
 ('birthday_bonus', false, 'Award birthday loyalty bonus (pending consent review)');

-- ---------- Bookings / work orders / tasks (today-relative) ------------------
-- Helper: today's 10:00 in Johannesburg
create temp table t_now as select (date_trunc('day', now() at time zone 'Africa/Johannesburg') + interval '10 hours') at time zone 'Africa/Johannesburg' as ten;

-- Thabo: in-service Full Valet (WO-4821 equivalent), SPK ref, Gold discount
insert into public.bookings (id, ref, customer_id, vehicle_id, outlet_id, service_id, slot_start, slot_end, status, price_cents, discount_cents, total_cents, discount_label, points_pending, client_op_id, created_by, created_at)
select '10000000-0000-4000-8000-000000000001'::uuid,'SPK-2026-0091','seed_thabo','d0000000-0000-4000-8000-000000000001'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000002'::uuid, ten, ten + interval '60 min','in_service'::public.booking_status,22000,2200,19800,'Gold −10%',20,'seed-op-0091','seed_thabo', now() - interval '2 days' from t_now;

-- Thabo: next confirmed Express wash (tomorrow 09:00)
insert into public.bookings (id, ref, customer_id, vehicle_id, outlet_id, service_id, slot_start, slot_end, status, price_cents, discount_cents, total_cents, discount_label, points_pending, client_op_id, created_by)
select '10000000-0000-4000-8000-000000000002'::uuid,'SPK-2026-0094','seed_thabo','d0000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000002'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid, ten + interval '23 hours', ten + interval '23 hours 20 min','confirmed'::public.booking_status,12000,1200,10800,'Gold −10%',11,'seed-op-0094','seed_thabo' from t_now;

-- Thabo history: two completed
insert into public.bookings (id, ref, customer_id, vehicle_id, outlet_id, service_id, slot_start, slot_end, status, price_cents, discount_cents, total_cents, points_pending, client_op_id, created_by, created_at)
select '10000000-0000-4000-8000-000000000003'::uuid,'SPK-2026-0067','seed_thabo','d0000000-0000-4000-8000-000000000001'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000003'::uuid, ten - interval '21 days', ten - interval '21 days' + interval '120 min','completed'::public.booking_status,45000,4500,40500,0,'seed-op-0067','seed_thabo', now() - interval '24 days' from t_now
union all
select '10000000-0000-4000-8000-000000000004'::uuid,'SPK-2026-0052','seed_thabo','d0000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid, ten - interval '38 days', ten - interval '38 days' + interval '20 min','completed'::public.booking_status,12000,0,12000,0,'seed-op-0052','seed_thabo', now() - interval '40 days' from t_now;

-- Other customers today (feeds admin live table + staff queue)
insert into public.bookings (id, ref, customer_id, vehicle_id, outlet_id, service_id, slot_start, slot_end, status, price_cents, discount_cents, total_cents, points_pending, client_op_id, created_by)
select '10000000-0000-4000-8000-000000000005'::uuid,'SPK-2026-0092','seed_naledi','d0000000-0000-4000-8000-000000000003'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid, ten - interval '90 min', ten - interval '70 min','completed'::public.booking_status,12000,0,12000,12,'seed-op-0092','seed_naledi' from t_now
union all
select '10000000-0000-4000-8000-000000000006'::uuid,'SPK-2026-0093','seed_sipho','d0000000-0000-4000-8000-000000000004'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000004'::uuid, ten + interval '30 min', ten + interval '120 min','confirmed'::public.booking_status,28000,0,28000,28,'seed-op-0093','seed_sipho' from t_now
union all
select '10000000-0000-4000-8000-000000000007'::uuid,'SPK-2026-0095','seed_zanele','d0000000-0000-4000-8000-000000000005'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000003'::uuid, ten + interval '2 hours', ten + interval '4 hours','confirmed'::public.booking_status,45000,6750,38250,68,'seed-op-0095','seed_zanele' from t_now
union all
select '10000000-0000-4000-8000-000000000008'::uuid,'SPK-2026-0096','seed_naledi','d0000000-0000-4000-8000-000000000003'::uuid,'a0000000-0000-4000-8000-000000000002'::uuid,'b0000000-0000-4000-8000-000000000002'::uuid, ten + interval '3 hours', ten + interval '4 hours','pending'::public.booking_status,22000,0,22000,22,'seed-op-0096','seed_naledi' from t_now
union all
select '10000000-0000-4000-8000-000000000009'::uuid,'SPK-2026-0090','seed_sipho','d0000000-0000-4000-8000-000000000004'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid, ten - interval '3 hours', ten - interval '160 min','cancelled'::public.booking_status,12000,0,12000,0,'seed-op-0090','seed_sipho' from t_now;

-- Quotations
insert into public.quotations (id, ref, customer_id, vehicle_id, outlet_id, category, description, status, amount_cents, line_items, assessor_id, valid_until, quoted_at, client_op_id) values
 ('20000000-0000-4000-8000-000000000001','QT-2026-0041','seed_thabo','d0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Bumper','Rear bumper scuffed in parking lot, paint cracked on left corner.','quoted',385000,
   '[{"label":"Bumper repair & respray","amount_cents":320000},{"label":"Blend to quarter panel","amount_cents":65000}]','seed_sipho_staff', current_date + 14, now() - interval '1 day','seed-op-qt41'),
 ('20000000-0000-4000-8000-000000000002','QT-2026-0042','seed_zanele','d0000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000001','Dent','Door ding on driver door, no paint damage.','requested',null,'[]',null,null,null,'seed-op-qt42'),
 ('20000000-0000-4000-8000-000000000003','QT-2026-0038','seed_sipho','d0000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','Scratch','Key scratch along passenger side.','accepted',210000,
   '[{"label":"Scratch repair & blend","amount_cents":210000}]','seed_sipho_staff', current_date + 7, now() - interval '4 days','seed-op-qt38');
update public.quotations set decided_at = now() - interval '2 days', decision_by = 'seed_sipho' where id = '20000000-0000-4000-8000-000000000003';

-- Work orders
insert into public.work_orders (id, ref, outlet_id, booking_id, vehicle_id, customer_id, service_id, status, priority, bay, checklist_template_id, template_version, assignee_id, eta_at, started_at, due_at)
select '30000000-0000-4000-8000-000000000001'::uuid,'WO-2026-4821','a0000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,'d0000000-0000-4000-8000-000000000001'::uuid,'seed_thabo','b0000000-0000-4000-8000-000000000002'::uuid,'in_progress'::public.work_status,1,'Bay 2','c0000000-0000-4000-8000-000000000001'::uuid,3,'seed_pieter', ten + interval '55 min', ten + interval '5 min', ten + interval '60 min' from t_now
union all
select '30000000-0000-4000-8000-000000000002'::uuid,'WO-2026-4822','a0000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000005'::uuid,'d0000000-0000-4000-8000-000000000003'::uuid,'seed_naledi','b0000000-0000-4000-8000-000000000001'::uuid,'verified'::public.work_status,2,'Bay 1','c0000000-0000-4000-8000-000000000002'::uuid,2,'seed_lerato', ten - interval '70 min', ten - interval '90 min', ten - interval '70 min' from t_now
union all
select '30000000-0000-4000-8000-000000000003'::uuid,'WO-2026-4823','a0000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000006'::uuid,'d0000000-0000-4000-8000-000000000004'::uuid,'seed_sipho','b0000000-0000-4000-8000-000000000004'::uuid,'blocked'::public.work_status,1,'Bay 3','c0000000-0000-4000-8000-000000000001'::uuid,3,'seed_lerato', ten + interval '120 min', ten - interval '10 min', ten + interval '120 min' from t_now
union all
select '30000000-0000-4000-8000-000000000004'::uuid,'WO-2026-4824','a0000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000007'::uuid,'d0000000-0000-4000-8000-000000000005'::uuid,'seed_zanele','b0000000-0000-4000-8000-000000000003'::uuid,'queued'::public.work_status,2,null,'c0000000-0000-4000-8000-000000000001'::uuid,3,null, ten + interval '4 hours', null, ten + interval '4 hours' from t_now
union all
select '30000000-0000-4000-8000-000000000005'::uuid,'WO-2026-4818','a0000000-0000-4000-8000-000000000001'::uuid,null,'d0000000-0000-4000-8000-000000000004'::uuid,'seed_sipho','b0000000-0000-4000-8000-000000000012'::uuid,'assigned'::public.work_status,2,'Body 1','c0000000-0000-4000-8000-000000000003'::uuid,1,'seed_sipho_staff', ten + interval '2 days', null, ten - interval '30 min' from t_now;
update public.work_orders set quotation_id = '20000000-0000-4000-8000-000000000003', blocked_reason = null where id = '30000000-0000-4000-8000-000000000005';
update public.work_orders set blocked_reason = 'Out of interior shampoo — substitute stock needed' where id = '30000000-0000-4000-8000-000000000003';
update public.work_orders set completed_at = (select ten - interval '72 min' from t_now), verified_at = (select ten - interval '70 min' from t_now), verified_by = 'seed_johan' where id = '30000000-0000-4000-8000-000000000002';

-- Tasks (one per work order)
insert into public.tasks (id, work_order_id, outlet_id, title, assignee_id, status, priority, blocked_reason, due_at, started_at, completed_at, elapsed_seconds)
select '40000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'Full Valet · KL 45 MN GP','seed_pieter','in_progress'::public.work_status,1,null, ten + interval '60 min', ten + interval '5 min', null, 1740 from t_now
union all
select '40000000-0000-4000-8000-000000000002'::uuid,'30000000-0000-4000-8000-000000000002'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'Express Wash · HR 88 TS GP','seed_lerato','verified'::public.work_status,2,null, ten - interval '70 min', ten - interval '90 min', ten - interval '72 min', 1080 from t_now
union all
select '40000000-0000-4000-8000-000000000003'::uuid,'30000000-0000-4000-8000-000000000003'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'Interior Deep Clean · DN 07 KX GP','seed_lerato','blocked'::public.work_status,1,'Out of interior shampoo — substitute stock needed', ten + interval '120 min', ten - interval '10 min', null, 600 from t_now
union all
select '40000000-0000-4000-8000-000000000004'::uuid,'30000000-0000-4000-8000-000000000004'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'Premium Detail · BW 33 RG GP',null,'queued'::public.work_status,2,null, ten + interval '4 hours', null, null, 0 from t_now
union all
select '40000000-0000-4000-8000-000000000005'::uuid,'30000000-0000-4000-8000-000000000005'::uuid,'a0000000-0000-4000-8000-000000000001'::uuid,'Scratch repair · DN 07 KX GP','seed_sipho_staff','assigned'::public.work_status,2,null, ten - interval '30 min', null, null, 0 from t_now;

-- Checklist progress for WO-4821: 4 of 7 done (matches mockup 2b)
insert into public.checklist_step_results (work_order_id, step_key, status, value, actor_id, completed_at)
select '30000000-0000-4000-8000-000000000001'::uuid, k, 'done'::public.step_status, v::jsonb, 'seed_pieter', ten + interval '1 min' * m
from t_now, (values ('prewash','{"photos":1}',8),('exterior','true',18),('wheels','true',24),('interior','true',31)) as s(k,v,m);
insert into public.checklist_step_results (work_order_id, step_key, status) values
 ('30000000-0000-4000-8000-000000000001','windows','pending'),
 ('30000000-0000-4000-8000-000000000001','tyre_pressure','pending'),
 ('30000000-0000-4000-8000-000000000001','supervisor','pending');
-- WO-4822 all done
insert into public.checklist_step_results (work_order_id, step_key, status, value, actor_id, completed_at)
select '30000000-0000-4000-8000-000000000002'::uuid, k, 'done'::public.step_status, 'true'::jsonb, case when k='supervisor' then 'seed_johan' else 'seed_lerato' end, ten - interval '75 min'
from t_now, unnest(array['exterior','wheels','dry','supervisor']) as k;
-- WO-4823 blocked at interior
insert into public.checklist_step_results (work_order_id, step_key, status, value, actor_id, completed_at, note)
select '30000000-0000-4000-8000-000000000003'::uuid,'prewash','done'::public.step_status,'{"photos":2}'::jsonb,'seed_lerato', ten - interval '8 min', null from t_now
union all select '30000000-0000-4000-8000-000000000003'::uuid,'exterior','done'::public.step_status,'true'::jsonb,'seed_lerato', ten - interval '2 min', null from t_now
union all select '30000000-0000-4000-8000-000000000003'::uuid,'interior','blocked'::public.step_status,null,'seed_lerato', null, 'Out of interior shampoo' from t_now;

-- Task events (audit)
insert into public.task_events (task_id, work_order_id, actor_id, event, from_status, to_status, reason, created_at)
select '40000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,'seed_johan','assigned','queued','assigned','Auto-assign: skill match, lowest load', ten - interval '20 min' from t_now
union all select '40000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,'seed_pieter','transition','assigned','in_progress',null, ten + interval '5 min' from t_now
union all select '40000000-0000-4000-8000-000000000003'::uuid,'30000000-0000-4000-8000-000000000003'::uuid,'seed_lerato','transition','in_progress','blocked','Out of interior shampoo — substitute stock needed', ten - interval '1 min' from t_now
union all select '40000000-0000-4000-8000-000000000002'::uuid,'30000000-0000-4000-8000-000000000002'::uuid,'seed_johan','transition','completed','verified','Checklist compliant', ten - interval '70 min' from t_now;

-- ---------- Payments ---------------------------------------------------------
insert into public.payment_methods (id, customer_id, provider, token, brand, last4, label, is_default) values
 ('50000000-0000-4000-8000-000000000001','seed_thabo','sandbox','tok_sandbox_visa_4242','visa','4242','Visa •••• 4242',true),
 ('50000000-0000-4000-8000-000000000002','seed_thabo','sandbox','tok_sandbox_eft','eft',null,'Instant EFT',false);

insert into public.payments (id, booking_id, customer_id, provider, provider_ref, method_id, amount_cents, status, receipt_no, idempotency_key, verified_at, created_at) values
 ('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','seed_thabo','sandbox','pi_sbx_0091','50000000-0000-4000-8000-000000000001',19800,'successful','RCP-70001','pay-seed-0091', now() - interval '2 days', now() - interval '2 days'),
 ('60000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003','seed_thabo','sandbox','pi_sbx_0067','50000000-0000-4000-8000-000000000001',40500,'successful','RCP-70002','pay-seed-0067', now() - interval '24 days', now() - interval '24 days'),
 ('60000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004','seed_thabo','sandbox','pi_sbx_0052','50000000-0000-4000-8000-000000000001',12000,'successful','RCP-70003','pay-seed-0052', now() - interval '40 days', now() - interval '40 days'),
 ('60000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000005','seed_naledi','sandbox','pi_sbx_0092',null,12000,'successful','RCP-70004','pay-seed-0092', now() - interval '80 min', now() - interval '85 min'),
 ('60000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000007','seed_zanele','sandbox','pi_sbx_0095',null,38250,'pending',null,'pay-seed-0095', null, now() - interval '30 min'),
 ('60000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000002','seed_thabo','sandbox','pi_sbx_0094','50000000-0000-4000-8000-000000000001',10800,'successful','RCP-70005','pay-seed-0094', now() - interval '3 hours', now() - interval '3 hours');

insert into public.payment_events (payment_id, provider, provider_event_id, event_type, signature_ok, payload) values
 ('60000000-0000-4000-8000-000000000001','sandbox','evt_sbx_0091_1','payment.succeeded',true,'{"amount":19800}'),
 ('60000000-0000-4000-8000-000000000001','sandbox','evt_sbx_0091_1_retry','payment.succeeded',true,'{"amount":19800,"replay":true}'),
 ('60000000-0000-4000-8000-000000000004','sandbox','evt_sbx_0092_1','payment.succeeded',true,'{"amount":12000}');

-- ---------- Loyalty ledger (append-only) — Thabo = Gold, 1 450 pts ----------
insert into public.loyalty_ledger (customer_id, delta, type, source_type, source_id, reference, description, idempotency_key, created_by, created_at) values
 ('seed_thabo', 500,'bonus','admin',null,'WELCOME','Welcome bonus','ll-thabo-welcome','seed_admin', now() - interval '120 days'),
 ('seed_thabo', 380,'earn','booking','10000000-0000-4000-8000-000000000004','SPK-2026-0031','Premium Detail','ll-thabo-0031','seed_admin', now() - interval '95 days'),
 ('seed_thabo', 150,'bonus','referral',null,'REF-NALEDI','Referral: Naledi M.','ll-thabo-ref1','seed_admin', now() - interval '70 days'),
 ('seed_thabo', 120,'earn','booking','10000000-0000-4000-8000-000000000004','SPK-2026-0052','Express Wash','ll-thabo-0052','seed_admin', now() - interval '40 days'),
 ('seed_thabo',-350,'redeem','reward','f0000000-0000-4000-8000-000000000002','RW-1182','Interior refresh','ll-thabo-rw1182','seed_thabo', now() - interval '30 days'),
 ('seed_thabo', 450,'earn','booking','10000000-0000-4000-8000-000000000003','SPK-2026-0067','Premium Detail','ll-thabo-0067','seed_admin', now() - interval '21 days'),
 ('seed_thabo', 200,'earn','booking',null,'SPK-2026-0078','Full Valet','ll-thabo-0078','seed_admin', now() - interval '9 days'),
 ('seed_naledi', 500,'bonus','admin',null,'WELCOME','Welcome bonus','ll-naledi-welcome','seed_admin', now() - interval '60 days'),
 ('seed_naledi', 120,'earn','booking','10000000-0000-4000-8000-000000000005','SPK-2026-0092','Express Wash','ll-naledi-0092','seed_admin', now() - interval '70 min'),
 ('seed_sipho', 500,'bonus','admin',null,'WELCOME','Welcome bonus','ll-sipho-welcome','seed_admin', now() - interval '200 days'),
 ('seed_sipho',1650,'earn','booking',null,'SPK-2025-0410','Panel respray','ll-sipho-0410','seed_admin', now() - interval '150 days'),
 ('seed_zanele', 500,'bonus','admin',null,'WELCOME','Welcome bonus','ll-zanele-welcome','seed_admin', now() - interval '10 days');
update public.loyalty_accounts set tier = 'gold',     tier_since = now() - interval '95 days' where customer_id = 'seed_thabo';
update public.loyalty_accounts set tier = 'gold',     tier_since = now() - interval '60 days' where customer_id = 'seed_naledi';
update public.loyalty_accounts set tier = 'platinum', tier_since = now() - interval '150 days' where customer_id = 'seed_sipho';
update public.loyalty_accounts set tier = 'gold',     tier_since = now() - interval '10 days' where customer_id = 'seed_zanele';

insert into public.reward_redemptions (customer_id, reward_id, ledger_id, code, status, used_at, created_at)
select 'seed_thabo','f0000000-0000-4000-8000-000000000002'::uuid, id, 'RW-1182', 'used', now() - interval '28 days', now() - interval '30 days'
from public.loyalty_ledger where idempotency_key = 'll-thabo-rw1182';

-- ---------- Inventory (STF-040..042) ----------------------------------------
insert into public.inventory_items (id, outlet_id, sku, name, unit, on_hand, reorder_threshold, pack_size) values
 ('70000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','SHP-INT','Interior shampoo 5L','bottle',1,4,5),
 ('70000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','WAX-CRN','Carnauba wax 500ml','tin',3,6,1),
 ('70000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','TWL-MF','Microfibre towels','pack',18,10,20),
 ('70000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','TYR-SHN','Tyre shine 1L','bottle',9,4,1),
 ('70000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000001','SNW-FOAM','Snow foam 5L','bottle',12,5,5),
 ('70000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000001','GLS-CLN','Glass cleaner 1L','bottle',7,4,1),
 ('70000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000001','PNT-CLR','Clear coat 1L','tin',2,3,1),
 ('70000000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000002','SHP-INT','Interior shampoo 5L','bottle',6,4,5),
 ('70000000-0000-4000-8000-000000000012','a0000000-0000-4000-8000-000000000002','WAX-CRN','Carnauba wax 500ml','tin',8,6,1),
 ('70000000-0000-4000-8000-000000000013','a0000000-0000-4000-8000-000000000002','TWL-MF','Microfibre towels','pack',4,10,20),
 ('70000000-0000-4000-8000-000000000021','a0000000-0000-4000-8000-000000000003','SNW-FOAM','Snow foam 5L','bottle',15,5,5),
 ('70000000-0000-4000-8000-000000000022','a0000000-0000-4000-8000-000000000003','TYR-SHN','Tyre shine 1L','bottle',1,4,1);

-- Movements create/refresh alerts through the trigger (delta 0 = stock count)
insert into public.inventory_movements (item_id, delta, reason, actor_id, note)
select id, 0, 'count', 'seed_ayesha', 'Opening stock count' from public.inventory_items;
insert into public.inventory_movements (item_id, delta, reason, actor_id, work_order_id, note, created_at) values
 ('70000000-0000-4000-8000-000000000001',-1,'usage','seed_lerato','30000000-0000-4000-8000-000000000003','Last bottle used', now() - interval '15 min');
update public.inventory_alerts set notified_at = now() - interval '14 min' where status = 'open';

-- ---------- Staff points & badges (STF-050) ----------------------------------
insert into public.staff_points_ledger (staff_id, outlet_id, delta, event_type, source_type, source_id, idempotency_key, created_at)
select s.staff, 'a0000000-0000-4000-8000-000000000001'::uuid, s.pts, 'task_completed', 'task', null, 'sp-' || s.staff || '-' || g, now() - (g || ' days')::interval
from (values ('seed_pieter',25,52),('seed_lerato',25,44),('seed_sipho_staff',25,38),('seed_thandi',25,30)) as s(staff, pts, n),
     generate_series(0, 60) as g
where g <= s.n and g % 2 = 0;
insert into public.staff_points_ledger (staff_id, outlet_id, delta, event_type, idempotency_key, created_at) values
 ('seed_pieter','a0000000-0000-4000-8000-000000000001',50,'streak_5_days','sp-pieter-streak-1', now() - interval '3 days'),
 ('seed_lerato','a0000000-0000-4000-8000-000000000001',20,'p1_on_time','sp-lerato-p1-1', now() - interval '1 day'),
 ('seed_pieter','a0000000-0000-4000-8000-000000000001',15,'verified_first_time','sp-pieter-vft-1', now() - interval '2 hours');

insert into public.staff_badges (staff_id, badge_id, awarded_at) values
 ('seed_pieter','90000000-0000-4000-8000-000000000001', now() - interval '20 days'),
 ('seed_pieter','90000000-0000-4000-8000-000000000002', now() - interval '3 days'),
 ('seed_pieter','90000000-0000-4000-8000-000000000004', now() - interval '12 days'),
 ('seed_lerato','90000000-0000-4000-8000-000000000001', now() - interval '30 days'),
 ('seed_lerato','90000000-0000-4000-8000-000000000003', now() - interval '6 days'),
 ('seed_sipho_staff','90000000-0000-4000-8000-000000000001', now() - interval '50 days');

-- ---------- Notifications ----------------------------------------------------
insert into public.notifications (recipient_id, channel, template_key, title, body, status, dedupe_key, sent_at, created_at) values
 ('seed_thabo','push','service_started','Service started','Your Toyota Corolla Cross is now in Bay 2.','sent','n-thabo-started-4821', now() - interval '25 min', now() - interval '25 min'),
 ('seed_thabo','whatsapp','booking_confirmed',null,'Hi Thabo, your Sparkling booking SPK-2026-0094 is confirmed for tomorrow 09:00 at Sparkling Rosebank.','delivered','n-thabo-conf-0094', now() - interval '3 hours', now() - interval '3 hours'),
 ('seed_thabo','push','quote_ready','Your quotation is ready','QT-2026-0041: R 3 850.00. Accept or decline in the app.','sent','n-thabo-qt41', now() - interval '1 day', now() - interval '1 day'),
 ('seed_pieter','push','task_assigned','New task','WO-2026-4821 assigned to you · Full Valet · Bay 2.','sent','n-pieter-4821', now() - interval '35 min', now() - interval '35 min'),
 ('seed_ayesha','push','low_stock','Low stock alert','Interior shampoo 5L at Sparkling Sandton is out of stock (0/4).','sent','n-ayesha-low-shp', now() - interval '14 min', now() - interval '14 min');

-- ---------- Audit ------------------------------------------------------------
insert into public.audit_events (actor_id, actor_role, action, entity_type, entity_id, outlet_id, after, correlation_id, created_at) values
 ('seed_admin','admin','loyalty_config.publish','loyalty_config','e0000000-0000-4000-8000-000000000014',null,'{"version":14}','seed-corr-1', now() - interval '40 days'),
 ('seed_ayesha','manager','loyalty_config.draft','loyalty_config','e0000000-0000-4000-8000-000000000015',null,'{"version":15}','seed-corr-2', now() - interval '2 days'),
 ('seed_johan','supervisor','task.assign','task','40000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','{"assignee":"seed_pieter"}','seed-corr-3', now() - interval '20 min'),
 ('seed_ayesha','manager','inventory.threshold','inventory_item','70000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','{"reorder_threshold":4}','seed-corr-4', now() - interval '10 days');

drop table t_now;
commit;
