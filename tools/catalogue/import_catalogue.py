#!/usr/bin/env python3
"""Generate backend/supabase/seed_catalogue.sql from the outlet list and the
"Sparkling_outlet_services_and_charges.xlsx" price sheet.

Usage:
    python3 tools/catalogue/import_catalogue.py [path/to/prices.xlsx] > backend/supabase/seed_catalogue.sql

Requires: pip install openpyxl

Rules encoded here (see docs/CATALOGUE.md):
- Every distinct service on the sheet maps to a canonical global `services` row
  (code in CANON below); the outlet's own wording is kept in
  `outlet_services.display_name`.
- "Small / Large" columns → price_small_cents / price_large_cents; "General"
  → price_general_cents. "By Quote" → pricing_mode 'by_quote'. "Incl VAT" /
  "Excl VAT" → vat_mode.
- Composite services: rows whose name says "include All of the above" include
  every prior row of the same outlet + group; "Including 'Sparkling Wash'"
  (in the name or the Notes column) includes the outlet's Sparkling Wash;
  explicit combos are listed in COMPOSITES.
- "Add to any Combo: …" rows are add-ons (is_addon) attached to the
  Combinations group.
The output is idempotent (upserts keyed by service code / outlet code).
"""
from __future__ import annotations

import re
import sys
import uuid
from collections import OrderedDict

import openpyxl

XLSX = sys.argv[1] if len(sys.argv) > 1 else 'backend/supabase/source/Sparkling_outlet_services_and_charges.xlsx'

# ---------------------------------------------------------------------------
# Outlets (from "Sparkling Outlets.docx"). Ids are stable so demo data can point at them.
# ---------------------------------------------------------------------------
OUTLETS = [
    # code, id, sheet name, display name, address, city, province, phone, email, lat, lng
    ('MEN', 'a0000000-0000-4000-8000-000000000001', 'Sparkling Auto Care Centre Menlyn', 'Sparkling Auto Care Centre Menlyn',
     'Menlyn Motor City, 149 Garsfontein Road, Menlyn', 'Pretoria', 'Gauteng', '012 348 4228 / 079 177 3146', 'menlyn@sparklingauto.co.za', -25.7822, 28.2769),
    ('GLV', 'a0000000-0000-4000-8000-000000000002', 'Sparkling Elite Centre Glen Village', 'Sparkling Elite Centre Glen Village',
     'Glen Village South Shopping Centre, c/o Solomon Mahlangu & Olympus Drive, Faerie Glen X24', 'Pretoria', 'Gauteng', '082 597 5848', 'glenvillage@sparklingauto.co.za', -25.7856, 28.3122),
    ('POT', 'a0000000-0000-4000-8000-000000000003', 'Sparkling Auto Care Centre Potchefstroom', 'Sparkling Auto Care Centre Potchefstroom',
     '31 Walter Sisulu Avenue', 'Potchefstroom', 'North West', '018 293 3973 / 072 720 2519', 'potch@sparklingauto.co.za', -26.7145, 27.0972),
    ('TOT', 'a0000000-0000-4000-8000-000000000004', 'Sparkling Car Wash Amanzimtoti', 'Sparkling Car Wash Amanzimtoti',
     'Arbour Crossing Shopping Centre, Arbour Road', 'Amanzimtoti', 'KwaZulu-Natal', '066 352 0528 / 082 871 6887', 'toti@sparklingauto.co.za', -30.0500, 30.8833),
    ('RUS', 'a0000000-0000-4000-8000-000000000005', 'Sparkling Car Wash Rustenburg', 'Sparkling Car Wash Rustenburg',
     '202 Beyers Naude Drive', 'Rustenburg', 'North West', '060 848 5523', 'rustenburg@sparklingauto.co.za', -25.6672, 27.2424),
]
SHEET_TO_CODE = {o[2]: o[0] for o in OUTLETS}
# The sheet spells Amanzimtoti with the final "i"; the docx drops it.
SHEET_TO_CODE['Sparkling Car Wash Amanzimtoti'] = 'TOT'

GROUP_CATEGORY = {'Car Wash Options': 'car_wash', 'Combinations': 'car_wash', 'Auto Body Repair': 'auto_body'}
GROUP_DURATION = {'Car Wash Options': 30, 'Combinations': 90, 'Auto Body Repair': 240}
GROUP_ICON = {'Car Wash Options': 'local_car_wash', 'Combinations': 'auto_awesome', 'Auto Body Repair': 'car_crash'}

# ---------------------------------------------------------------------------
# Canonical services: code -> (canonical name, description, [name patterns])
# Patterns are matched (case-insensitive, punctuation-insensitive) against the sheet name.
# ---------------------------------------------------------------------------
CANON: "OrderedDict[str, tuple[str, str, list[str]]]" = OrderedDict([
    ('WASH_GO',              ('Wash & Go',                                   'Quick exterior wash',                                        [r'^wash go$'])),
    ('EXT_WASH',             ('Exterior wash',                               'Exterior wash only',                                         [r'^exterior wash only$'])),
    ('EXT_WASH_TYRE',        ('Exterior wash, tyre shine & drying',          'Exterior wash with tyre shine and hand drying',              [r'^exterior wash with tyre shine drying$'])),
    ('EXT_WASH_TYRE_BUMPER', ('Exterior wash, tyre shine, drying & bumper polish', 'Exterior wash, tyre shine, drying and bumper polish', [r'^exterior wash tyre shine drying bumper polish$', r'^exterior wash tyre shine bumper polish$'])),
    ('WINDOWS_INSIDE',       ('Extra: windows inside clean',                 'Inside window clean add-on',                                 [r'^extra windows inside clean$'])),
    ('INT_CLEAN',            ('Interior cleaning & vacuum',                  'Interior clean and vacuum',                                  [r'^interior cleaning vacuum( only)?$'])),
    ('SPARKLING_WASH',       ('Sparkling Wash',                              'Full wash: exterior, tyre shine, interior clean and vacuum', [r'^sparkling wash include all of the above$'])),
    ('POLISH_BUFF_2',        ('Polish & Buff (2 stage)',                     'Two-stage polish and buff',                                  [r'^polish buff 2 stage$'])),
    ('POLISH_BUFF_2_EXT',    ('Polish & Buff (2 stage) & exterior wash',     'Two-stage polish and buff with exterior wash',               [r'^polish buff 2 stage exterior wash$'])),
    ('HAND_POLISH',          ('Hand polish',                                 'Hand-applied polish',                                        [r'^hand polish$'])),
    ('CHASSIS_STEAM',        ('Chassis steam clean',                         'Steam clean of the chassis',                                 [r'^chassis steam clean$'])),
    ('ENGINE_STEAM',         ('Engine steam clean',                          'Steam clean of the engine bay',                              [r'^engine steam clean$'])),
    ('EXEC_WASH',            ('Executive wash',                              'Sparkling Wash plus engine wash',                            [r'^executive wash sparkling engine wash$'])),
    ('WASH_BIKE',            ('Wash bike',                                   'Motorcycle wash',                                            [r'^wash bike$'])),
    ('ODOUR_REMOVAL',        ('Odour removal',                               'Interior odour treatment',                                   [r'^odour removal$'])),
    ('SPARKLING_WASH_7_16',  ('Sparkling Wash (7–16 seater)',                'Sparkling Wash for 7–16 seater vehicles',                    [r'^sparkling wash 7 ?16 seater$', r'^sparkling wash 7 6 seater$'])),
    ('TAR_REMOVAL',          ('Tar removal / excess mud',                    'Tar or excess mud removal',                                  [r'^tar removal excess mud$'])),
    ('WASH_SEAT',            ('Wash seat',                                   'Seat wash',                                                  [r'^wash seat$'])),
    ('WASH_BABY_SEAT',       ('Wash baby seat',                              'Baby seat wash',                                             [r'^wash baby seat$'])),
    ('WASH_TAILGATE',        ('Wash tailgate',                               'Tailgate wash',                                              [r'^wash tailgate$'])),
    # Combinations
    ('ENGINE_CHASSIS_COMBO', ('Engine & chassis steam clean combo',          'Engine and chassis steam clean together',                    [r'^(engine chassis|chassis engine) steam clean combo$'])),
    ('AUTO_DETAIL_MINI',     ('Auto detailing mini',                         'Mini detailing package',                                     [r'^auto detailing mini$'])),
    ('AUTO_DETAIL_INTERIOR', ('Auto detailing interior',                     'Interior detailing package',                                 [r'^auto detailing interior$'])),
    ('AUTO_DETAIL_COMPLETE', ('Auto detailing complete & polish',            'Complete detailing package with polish',                     [r'^auto detailing complete polish( including sparkling wash)?$'])),
    ('SPARKLING_POLISH_BUFF',('Sparkling Wash, polish & buff',               'Sparkling Wash with two-stage polish and buff',              [r'^sparkling wash polish buff$'])),
    ('SPARKLING_HAND_POLISH',('Sparkling Wash & hand polish',                'Sparkling Wash with hand polish',                            [r'^sparkling wash hand polish$'])),
    ('SPARKLING_MACHINE_POLISH', ('Sparkling Wash & machine polish',         'Sparkling Wash with machine polish',                         [r'^sparkling wash machine polish$'])),
    ('SPARKLING_2STAGE_POLISH', ('Sparkling Wash & 2 stage polish',          'Sparkling Wash with two-stage polish',                       [r'^sparkling wash 2 stage polish$'])),
    ('FULL_MONTY',           ('The Sparkling Full Monty',                    'Complete detailing, engine & chassis steam clean and 3-stage polish', [r'^the sparkling full monty$'])),
    ('ADDON_ODOUR',          ('Add-on: odour removal',                       'Odour removal added to any combo',                           [r'^add to any combo odour removal$'])),
    # Auto body repair
    ('HEADLIGHT_RENEWAL',    ('Headlight renewal (per light)',               'Headlight lens restoration, per light',                      [r'^headlight renewal per light$'])),
    ('PAINT_POLISH_3STAGE',  ('3 stage paint polishing & auto glaze',        'Three-stage paint correction and glaze',                     [r'^3 stage paint polishing auto glaze( including spark(l)?ing wash)?$'])),
    ('CERAMIC_COATING',      ('Ceramic coating',                             'Ceramic paint protection',                                   [r'^ceramic coating$'])),
    ('ODOUR_REMOVAL_AB',     ('Odour removal (treatment)',                   'Professional odour treatment',                               [r'^odour removal ab$'])),
    ('SPOT_REPAIR',          ('Spot repair & blending (per panel)',          'Spot repair with paint blending, per panel',                 [r'^spot repair blending per panel$'])),
    ('BUMPER_SCUFF',         ('Bumper scuffs (0–15cm)',                      'Bumper scuff repair up to 15cm',                             [r'^bumper scuffs 0 ?15cm$'])),
    ('PDR',                  ('Paintless dent repair (per panel)',           'Paintless dent removal, per panel',                          [r'^paintless dent repair per (dent )?panel$'])),
    ('MAG_WHEEL',            ('Mag wheel repair',                            'Alloy wheel repair',                                         [r'^mag wheel repair$'])),
    ('MACHINE_POLISH_1STAGE',('1 stage machine polish',                      'Single-stage machine polish',                                [r'^1 stage machine polish$'])),
    ('FLAT_POLISH',          ('Flat & polish (per panel)',                   'Flat and polish, per panel',                                 [r'^flat polish per panel$'])),
    ('SMASH_GRAB',           ('Smash & grab film',                           'Smash-and-grab window film',                                 [r'^smash grab$'])),
    ('NUMBER_PLATE',         ('Number plate replacement',                    'Number plate replacement',                                   [r'^number plate replacement$'])),
    ('WINDSHIELD_REPAIR',    ('Windshield repair',                           'Windscreen chip/crack repair',                               [r'^windshield repair$'])),
])

# Explicit composite memberships (parent code -> child codes) applied at every outlet
# where both exist; "include all of the above" is computed from row order.
COMPOSITES = {
    'ENGINE_CHASSIS_COMBO': ['ENGINE_STEAM', 'CHASSIS_STEAM'],
    'EXEC_WASH': ['SPARKLING_WASH', 'ENGINE_STEAM'],
    'SPARKLING_POLISH_BUFF': ['SPARKLING_WASH', 'POLISH_BUFF_2', 'POLISH_BUFF_2_EXT'],
    'SPARKLING_HAND_POLISH': ['SPARKLING_WASH', 'HAND_POLISH'],
    'SPARKLING_MACHINE_POLISH': ['SPARKLING_WASH'],
    'SPARKLING_2STAGE_POLISH': ['SPARKLING_WASH'],
    'AUTO_DETAIL_INTERIOR': ['SPARKLING_WASH'],
    'AUTO_DETAIL_COMPLETE': ['SPARKLING_WASH'],
    'FULL_MONTY': ['AUTO_DETAIL_COMPLETE', 'ENGINE_CHASSIS_COMBO', 'PAINT_POLISH_3STAGE'],
    'PAINT_POLISH_3STAGE': ['SPARKLING_WASH'],
    'POLISH_BUFF_2_EXT': ['EXT_WASH'],
}


def norm(name: str) -> str:
    s = name.lower().replace('“', '"').replace('”', '"').replace('’', "'")
    s = re.sub(r'[^a-z0-9]+', ' ', s)
    return s.strip()


def canon_code(sheet_name: str, group: str) -> str:
    n = norm(sheet_name)
    if group == 'Auto Body Repair' and n == 'odour removal':
        n = 'odour removal ab'
    for code, (_, _, pats) in CANON.items():
        if any(re.match(p, n) for p in pats):
            return code
    raise SystemExit(f'No canonical service for "{sheet_name}" ({group}) → "{n}"')


def cents(v) -> str:
    if v is None or str(v).strip() == '':
        return 'null'
    return str(int(round(float(v) * 100)))


def q(s) -> str:
    return 'null' if s is None else "'" + str(s).replace("'", "''") + "'"


def stable_uuid(key: str) -> str:
    return str(uuid.uuid5(uuid.UUID('6f2c1c1e-8f1c-4c3a-9d7a-3a9b0c1d2e3f'), key))


def main() -> None:
    wb = openpyxl.load_workbook(XLSX, data_only=True)
    ws = wb.worksheets[0]
    rows = [r for r in ws.iter_rows(values_only=True)][1:]
    rows = [r for r in rows if r and r[0]]

    out = []
    w = out.append
    w('-- GENERATED by tools/catalogue/import_catalogue.py from backend/supabase/source/Sparkling_outlet_services_and_charges.xlsx')
    w('-- and Sparkling_Outlets.docx. Idempotent upserts. Do not edit by hand; re-run the importer.')
    w('begin;')
    # Outlets
    w('-- ---------- outlets ----------')
    for code, oid, _, name, addr, city, prov, phone, email, lat, lng in OUTLETS:
        w(f"insert into public.outlets (id, code, name, trading_as, address_line, city, province, phone, email, latitude, longitude, bay_count, is_active)\n"
          f"values ('{oid}', '{code}', {q(name)}, {q(name)}, {q(addr)}, {q(city)}, {q(prov)}, {q(phone)}, {q(email)}, {lat}, {lng}, 3, true)\n"
          f"on conflict (id) do update set code = excluded.code, name = excluded.name, trading_as = excluded.trading_as, address_line = excluded.address_line, city = excluded.city, province = excluded.province, phone = excluded.phone, email = excluded.email, latitude = excluded.latitude, longitude = excluded.longitude, is_active = true;")
    w("update public.outlets set is_active = false where code not in (" + ', '.join(q(o[0]) for o in OUTLETS) + ");")
    # Menlyn legal identity is known from a real quotation; other outlets are captured in the admin app.
    w("update public.outlets set legal_name = 'Izandra Trading 36 (Pty) Ltd', company_registration_no = '2006/024689/07', vat_number = '4310233384',\n"
      "  registered_office = 'PO Box 238, Potchefstroom, North West, 2531, South Africa',\n"
      "  bank_details = jsonb_build_object('financial_institution','First National Bank','account_name','Izandra Trading 36 (Pty) Ltd','branch','Menlyn','branch_code','250655','account_number','63041170711','account_type','Gold Business Account')\n"
      " where code = 'MEN';")
    w("update public.outlets set legal_name = null, company_registration_no = null, vat_number = null, registered_office = null, bank_details = null where code <> 'MEN' and legal_name = 'Izandra Trading 36 (Pty) Ltd';")

    # Services (canonical)
    w('-- ---------- canonical services ----------')
    used: "OrderedDict[str, dict]" = OrderedDict()
    per_outlet: "OrderedDict[str, list[dict]]" = OrderedDict()
    for r in rows:
        outlet_name, group, name, small, large, general, pricing, vat, notes = (list(r) + [None] * 9)[:9]
        outlet = SHEET_TO_CODE.get(str(outlet_name).strip())
        if not outlet:
            raise SystemExit(f'Unknown outlet on sheet: {outlet_name}')
        group = str(group).strip()
        code = canon_code(str(name), group)
        entry = used.setdefault(code, {'group': group, 'vat': 'excl' if str(vat).lower().startswith('excl') else 'incl', 'mode': 'by_quote' if str(pricing).lower().startswith('by') else 'from', 'addon': code.startswith('ADDON_')})
        per_outlet.setdefault(outlet, []).append({
            'code': code, 'group': group, 'display': str(name).strip(), 'small': small, 'large': large, 'general': general,
            'mode': 'by_quote' if str(pricing).lower().startswith('by') else 'from', 'vat': 'excl' if str(vat).lower().startswith('excl') else 'incl', 'notes': notes,
        })
    svc_rows = []
    sort = 0
    for code, meta in used.items():
        sort += 10
        cname, desc, _ = CANON[code]
        sid = stable_uuid('service:' + code)
        svc_rows.append(f"('{sid}','{code}',{q(cname)},{q(desc)},'{GROUP_CATEGORY[meta['group']]}',{q(meta['group'])},{GROUP_DURATION[meta['group']]},0,{str(meta['mode']=='by_quote').lower()},'{meta['mode']}','{meta['vat']}',{str(meta['addon']).lower()},{q('Combinations') if meta['addon'] else 'null'},'{GROUP_ICON[meta['group']]}',{sort},true)")
    w("insert into public.services (id, code, name, description, category, group_name, duration_minutes, base_price_cents, is_quote_based, pricing_mode, vat_mode, is_addon, addon_group_name, icon, sort_order, is_active) values\n"
      + ",\n".join(svc_rows)
      + "\non conflict (code) do update set name = excluded.name, description = excluded.description, category = excluded.category, group_name = excluded.group_name, pricing_mode = excluded.pricing_mode, vat_mode = excluded.vat_mode, is_quote_based = excluded.is_quote_based, is_addon = excluded.is_addon, addon_group_name = excluded.addon_group_name, icon = excluded.icon, sort_order = excluded.sort_order, is_active = true;")
    w("-- Legacy demo services that are not on the price sheet are retired (kept for historical bookings).")
    w("update public.services set is_active = false where code not in (" + ', '.join(q(c) for c in used) + ");")

    # Outlet services
    w('-- ---------- outlet services (prices + wording per outlet) ----------')
    w("delete from public.outlet_services where outlet_id in (select id from public.outlets where code in (" + ', '.join(q(o[0]) for o in OUTLETS) + "));")
    os_rows = []
    for outlet, items in per_outlet.items():
        oid = next(o[1] for o in OUTLETS if o[0] == outlet)
        for i, it in enumerate(items):
            sid = stable_uuid('service:' + it['code'])
            general = it['general'] if it['general'] not in (None, '') else None
            os_rows.append(f"('{oid}','{sid}',{q(it['display'])},{cents(it['small'] if it['small'] not in (None, '') else general)},{cents(it['small'])},{cents(it['large'])},{cents(general)},'{it['mode']}','{it['vat']}',{(i + 1) * 10},{q(it['notes'])},true)")
    w("insert into public.outlet_services (outlet_id, service_id, display_name, price_cents, price_small_cents, price_large_cents, price_general_cents, pricing_mode, vat_mode, sort_order, notes, is_available) values\n" + ",\n".join(os_rows) + ";")

    # Composites
    w('-- ---------- composite memberships (per outlet) ----------')
    w("delete from public.service_components where outlet_id in (select id from public.outlets where code in (" + ', '.join(q(o[0]) for o in OUTLETS) + "));")
    comp_rows = []
    for outlet, items in per_outlet.items():
        oid = next(o[1] for o in OUTLETS if o[0] == outlet)
        codes_here = [it['code'] for it in items]
        def add(parent: str, child: str, order: int, oid=oid, codes_here=codes_here) -> None:
            if parent in codes_here and child in codes_here and parent != child:
                comp_rows.append(f"('{stable_uuid('service:' + parent)}','{stable_uuid('service:' + child)}','{oid}',{order})")
        for idx, it in enumerate(items):
            if 'include all of the above' in norm(it['display']):
                prior = [p for p in items[:idx] if p['group'] == it['group'] and p['mode'] != 'by_quote']
                for k, p in enumerate(prior):
                    add(it['code'], p['code'], (k + 1) * 10)
            for k, child in enumerate(COMPOSITES.get(it['code'], [])):
                add(it['code'], child, 100 + k * 10)
    if comp_rows:
        w("insert into public.service_components (parent_service_id, child_service_id, outlet_id, sort_order) values\n" + ",\n".join(dict.fromkeys(comp_rows)) + "\non conflict do nothing;")
    w('commit;')
    sys.stdout.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
