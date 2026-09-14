# Outlet catalogue & pricing rules

Source of truth: `backend/supabase/source/Sparkling_Outlets.docx` (outlets) and
`Sparkling_outlet_services_and_charges.xlsx` (services and charges). Regenerate the seed with

```bash
python3 tools/catalogue/import_catalogue.py > backend/supabase/seed_catalogue.sql   # needs `pip install openpyxl`
```

## Outlets (5)
| Code | Name | City |
|---|---|---|
| MEN | Sparkling Auto Care Centre Menlyn | Pretoria |
| GLV | Sparkling Elite Centre Glen Village | Pretoria |
| POT | Sparkling Auto Care Centre Potchefstroom | Potchefstroom |
| TOT | Sparkling Car Wash Amanzimtoti | Amanzimtoti |
| RUS | Sparkling Car Wash Rustenburg | Rustenburg |

Menlyn carries the legal/banking identity from the reference quotation; the other outlets' legal fields are captured in Admin → Outlets.

## Model
- **Canonical services** (`services`): one row per distinct service across outlets (43), with `code`, `group_name` (Car Wash Options, Combinations, Auto Body Repair), `pricing_mode` (`from`, `fixed`, `by_quote`), `vat_mode` (`incl` for car wash groups, `excl` for auto body), optional default prices, `is_addon`.
- **Outlet offers** (`outlet_services`): the outlet's own wording (`display_name`), small/large or general prices in cents, mode/VAT overrides, order, notes, availability. Prices on the sheet are minimums ("From R x").
- **Composites** (`service_components`): parent → child links, per outlet (global rows apply where an outlet has none). "Include all of the above" rows include every earlier priced row of the same outlet and group; explicit combos are defined in the importer (`COMPOSITES`).
- **Add-ons**: `is_addon` services (e.g. odour removal) attach to a booking of a service in `addon_group_name`.
- **Vehicle size**: `vehicles.size_class` (`small`, `large`, `bike`), derived from the disc description when not set; picks the small/large price.
- **VAT**: `incl` prices are final; `excl` prices get 15% VAT added on totals and quotation PDFs.

Merging rule for names: near-identical wordings map to one canonical code (e.g. Menlyn's "Exterior wash, Tyre shine & Bumper polish" and Glen Village's "Exterior wash Tyre shine & drying & Bumper polish" are both `EXT_WASH_TYRE_BUMPER`); the outlet's original wording is preserved in `display_name`.
