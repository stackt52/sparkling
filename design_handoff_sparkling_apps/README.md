# Handoff: Sparkling Platform UI — Customer App, Outlet Staff App, Admin Dashboard

## Overview
Hi-fi UI mockups for the Sparkling multi-outlet car-wash / auto-body platform per SRS v1.0 (28 Aug 2026): a Customer mobile app (Android/iOS, Flutter), an Outlet Staff mobile app (Android, Flutter), and a responsive web Admin Dashboard. Design system: **Google Material 3 Expressive**, themed from the Sparkling brand logos. Sample data is South African (ZAR, GP plates, PDF417 vehicle licence discs).

## About the Design Files
The files in this bundle are **design references created in HTML** — static prototypes showing intended look and behavior, not production code. The task is to **recreate these designs in the target codebases**: Flutter/Dart with Material 3 (`useMaterial3: true`) for both mobile apps, and the chosen web framework (deployed on Firebase App Hosting) for the Admin Dashboard, using a shared design-token system (SRS UX-001). Do not ship the HTML.

## Fidelity
**High-fidelity.** Colors, type scale, radii, spacing and copy are final-intent. Recreate pixel-faithfully using M3 theme primitives (ColorScheme, Shape, Typography) rather than hard-coded values — every value below should become a token.

## Screenshots
`screenshots/` contains one PNG per screen, named by screen id (e.g. `1a-customer-home-light.png`). Ids match the source mockup file (`Sparkling UI Mockups.dc.html`).

## Design Tokens

### Color — Light scheme
| Role | Hex |
|---|---|
| primary | #006398 |
| onPrimary | #FFFFFF |
| primaryContainer | #CBE6FF |
| onPrimaryContainer | #001D31 |
| secondary (brand navy) | #203060 |
| secondaryContainer | #D7E3F9 |
| onSecondaryContainer | #14243D |
| surface | #F6FAFD |
| surfaceContainer | #EBF1F7 |
| surfaceContainerHigh | #E1EAF2 |
| onSurface | #16212B |
| onSurfaceVariant | #51606F |
| outline | #C3CFDA |
| error / errorContainer | #BA1A1A / #FFDAD6 (on: #93000A) |
| success / container | #1D8A4E / #C9F0D8 (on: #0D5C32) |
| warning container | #FFE6B8 (on: #7A5000) |
| gold (loyalty) | gradient #F3DDA4 → #E2BA5F (on: #5C4200) |

### Color — Dark scheme
| Role | Hex |
|---|---|
| primary | #8BD2FF |
| onPrimary | #00344F |
| primaryContainer | #0F3550 |
| onPrimaryContainer | #CBE8FF |
| surface | #0D1524 |
| surfaceContainer | #151F33 |
| surfaceContainerHigh | #1B2942 / #1D2942 |
| onSurface | #E3E9F4 |
| onSurfaceVariant | #98A6BB |
| outline (track) | #2B3C58 |
| error-ish accent | #FFB59F |
| success accent | #6EE7A0 |

### Brand
- Navy: **#203060** (logo background; hero cards, dark accents)
- Azure: **#00A0E0** (logo car swoosh; gradients `linear-gradient(135deg, #00A0E0, #0074B8)`)
- Hero gradient (light): `linear-gradient(130deg, #203060 30%, #0A5F96 80%, #00A0E0)`
- Hero gradient (dark): `linear-gradient(130deg, #1B2942 20%, #0A4F7D 75%, #0083C4)`

### Typography
Mockups use **Outfit** (Google Fonts) as a stand-in for the final M3 Expressive type ramp; monospace (ui-monospace) for plates, VINs and refs.
- Display / balances: 700, 34–40px
- Headline (screen titles): 600, 19–22px
- Title (card titles): 600, 14.5–16px
- Body: 400, 12.5–13.5px, line-height 1.5–1.6
- Label (chips, badges): 500–700, 10–12.5px; overlines 10.5px uppercase, letter-spacing .06em

### Shape
- Phone screen corners: 36px; hero/feature cards 24–28px; standard cards 20–24px; list tiles 18–20px; chips/buttons/sliders full pill (100px); nav-item active indicator 56×30 pill; admin cards 24px, admin frame 20px.

### Spacing
4px base grid. Screen gutter 20px (phone) / 26px (admin content). Card padding 14–20px. Gap between sibling cards 9–14px.

### Elevation / effects
Flat tonal surfaces (M3). Shadows only on: FAB (`0 8px 20px rgba(0,160,224,.35)`), bottom sheet (`0 -12px 32px rgba(0,0,0,.4)`), hero podium avatar glow. Progress rings via conic-gradient equivalents (use CustomPaint / CircularProgressIndicator in Flutter).

### Iconography
Material Symbols **Rounded**, FILL=1 for active/filled, FILL=0 for inactive nav and neutral actions. Key glyphs used: local_car_wash, car_crash, qr_code_scanner, water_drop, cleaning_services, auto_awesome, loyalty, checklist, inventory_2, social_leaderboard, cloud_done/cloud_off, block, schedule, notification_important, storefront, dashboard, request_quote, groups, settings, download, trending_up.

## Screens / Views

### t1 — Customer App (412px frames)
- **1a Home (light)**: status bar; logo app bar + notification (badge dot #00A0E0) + avatar tile (44px, r16); greeting block (Good morning / name 28px 600); gold loyalty pill; **Next booking hero card** (navy→azure gradient, r28, status pill w/ green dot, white pill CTA "Track service"); two quick-action tonal cards (primaryContainer "Book a wash" / secondaryContainer "Repair quote", 42px icon tile r14); horizontal vehicle cards (200px, plate in mono, "Disc verified" / "Manual entry" status chips); M3 nav bar (active pill indicator on surfaceContainer).
- **1b Service select**: back tile + title + "Step 1 of 3"; 3-segment progress strip (5px, filled #006398); navy outlet selector card (rating, distance, unfold_more); service list — radio cards (unselected surfaceContainer, r22; selected primaryContainer + 2px #006398 border + filled radio check); "Earn 22 pts" white chip on selected; bottom bar: total + pill CTA "Choose date & time".
- **1c Slot picker**: date chips (5-up, r18; disabled = muted; selected = navy block w/ azure weekday); slot grid 3-col pill chips (booked = struck-through muted; selected = filled primary); summary banner (secondaryContainer, event_available, cancellation policy); CTA "Review & pay".
- **1d PDF417 scan**: full dark (#0B1018); viewfinder card (r28) with 4 azure corner brackets (42px, 4px stroke, r18 outer), simulated barcode strip, glowing azure scan line (`box-shadow: 0 0 14px #00A0E0`); torch toggle tile; hint banner (azure-tinted, "decoding happens on your phone, even offline" — SRS STF-013/INT-005); actions: outlined "Enter manually" / filled tonal "Retry scan" (CUS-014, UX-008).
- **1e Scan review**: success banner (successContainer, task_alt) — "nothing is committed silently" (CUS-013); field tiles (overline label + value; mono for reg/VIN; VIN masked + lock = non-editable); disc-expiry tile warning-bordered (#E2BA5F); duplicate-detection info banner (CUS-015); actions Rescan / Save vehicle.
- **1f Payment**: order summary card w/ line items, Gold −10% discount line (success color), dashed divider, total 22px 700 primary; payment method radio cards (selected primaryContainer + border; VISA plate 44×32 r8 navy); "Add card or instant EFT" tile; PCI note w/ verified_user (CUS-044); CTA "Pay R 198.00 securely" with lock icon.
- **1g Confirmation**: expressive asymmetric blob (organic border-radius, primaryContainer outer + primary inner, 56px check; azure + gold confetti dots); title 24px 700; ref in mono; detail rows (calendar/receipt links, "+20 pts pending completion" — points post on completion, CUS-064); WhatsApp/push notice banner (CUS-051/052); Done / Track service.
- **1h Tracking timeline**: header w/ ref + vehicle + "Live · 2 min ago" success chip; navy stage card w/ 58px conic progress ring (58%), stage 3/6, assignee, big ETA; vertical timeline — done (filled primary circle + check), current (primaryContainer ring + dot, primary-colored title), pending (muted circles), connectors 3px; "Notify me when ready" switch tile (M3 switch, 46×26).
- **1i Loyalty**: navy→gold gradient tier card (GOLD MEMBER gold pill, white logo, balance 40px 700, progress bar to Platinum w/ azure gradient fill, "550 pts to Platinum"); Silver/Gold/Platinum segmented pills (active = navy filled); reward cards 2-up (points price + filled Redeem pill); ledger list (+earn green add_circle / −redeem red do_not_disturb_on, ref + date + delta) — append-only ledger presentation (CUS-063).
- **1j Quote request**: vehicle selector tile; category filter chips (selected = navy filled + check); description textarea card w/ caret; photo attachments row (88px striped placeholders + remove badges, dashed add tile) (CUS-031); expectation banner ("Accept or decline — nothing is booked until you approve", CUS-033); CTA "Request quote".
- **1k Home (dark)**: same layout as 1a in dark scheme; in-service hero card w/ inline progress bar; gold chip becomes translucent gold-bordered.
- **1l Offline (dark)**: offline banner (gold-tinted, cloud_off, "showing status from 20:47", Retry); "Last sync 20:47" chip replaces Live chip; progress ring desaturated (#5A7A94); queued-change sync notice (CUS-054, ARC-004).

### t2 — Outlet Staff App (412px, dark-first)
- **2a Task list**: outlet + "My tasks"; sync chip (cloud_done green "Synced 09:41" — STF-062); segmented filter pills Mine/Queue/Done with counts; task cards: P1/P2 priority chips (P1 #FFB59F on #5C1900-text, P2 gold), WO ref mono, status chip, vehicle + bay in mono, checklist progress bar + "4/7 steps", big CTA "Continue checklist" + timer tile; blocked card = error-bordered w/ reason line; extended FAB "Scan disc" (azure, r20); 5-item nav bar.
- **2b Checklist execution**: header w/ WO + 48px conic ring 4/7; done steps (green check circle, struck-through, 65% opacity, timestamp + actor — STF-024); **current step** expanded card (primaryContainer bg + 2px primary border, REQUIRED badge, photo-proof placeholder + camera tile, "Complete step" filled / "Mark blocked" outlined-error); upcoming steps incl. numeric input step (`__ : 10` mono field) and supervisor-verification step locked until required steps pass (STF-033); offline note (STF-034).
- **2c Supervisor ops**: 4 KPI stat tiles (In progress azure / Queued neutral / Blocked error-tint / Done success-tint, 24px 700 numerals); "Needs attention" cards (blocked w/ Reassign + Substitute stock actions; overdue SLA card gold-bordered); team load rows (avatar tile, workload bar, task count / "Available" in green) (STF-060/061, STF-036).
- **2d Assign sheet**: modal bottom sheet (r32 top, drag handle, dimmed backdrop) over ops screen; staff radio cards w/ availability + skill chips (selected = primaryContainer + border; at-capacity row 55% opacity); audit note ("actor, time and reason are recorded" — STF-021/024); Cancel / "Assign to Pieter".
- **2e Leaderboard**: Week/Month segmented control; podium (winner 64px gold-gradient avatar + crown + tallest column, 2nd/3rd smaller); ranked list w/ delta arrows, "You" row highlighted azure-tinted; badges grid (earned = colored icons, locked = 45% opacity lock) (STF-050, STF-052).
- **2f Inventory**: alert banner (error-tinted, "2 items below reorder threshold · Manager notified"); search pill; item cards w/ level bar (LOW = #FFB59F fill + bordered card; OUT = red badge, empty bar, blocking note; OK = green) and "x of y · min z" labels; technician actions Request reorder / Log usage; RBAC note "reorder & threshold edits are manager-only" (STF-040–042).
- **2g Task list (light)**: 2a mapped to light tokens (P1 chip → errorContainer, status chips → primaryContainer/surfaceContainerHigh).

### t3 — Admin Dashboard (1240px frames)
- **3a Ops overview (light)**: 84px M3 navigation rail (logo, 7 destinations w/ active pill + filled icon, avatar bottom); header: title + "Live · updated hh:mm:ss", outlet filter pill, date pill, navy "Export CSV" pill (ADM-012, ADM-063); KPI row: revenue hero (navy gradient, +12% trend chip) + 3 white stat cards + exceptions card (error-bordered); "Bookings by hour" stacked bar chart (car wash #006398 / auto body #8BD2FF, future hours 40% opacity); Exceptions list (tinted rows linking to records — ADM-011/013); Live bookings table (7 cols: mono ref in primary, customer, mono plate, service, slot, status chip, right-aligned amount).
- **3b Loyalty config**: "Published · v14" green chip, Audit log pill, "Edit draft" navy pill (ADM-025, versioned + audited); three tier cards (Silver/Gold/Platinum, Gold highlighted w/ gold border; qualify range, earn rate, discount rows); earning/expiry rule tiles w/ M3 switches (idempotent award note, 24-mo expiry, disabled birthday-bonus rule pending consent review — ADM-042); navy "Draft changes · v15" panel w/ diff summary + "takes effect server-side within 60 s" + Discard/Publish.
- **3c Inventory & alerts**: 3 summary cards (tracked items / below threshold gold-bordered / out-of-stock error-bordered); stock table (item, outlet, level bar, on hand, threshold, status chip) w/ alert rows tinted and sorted first, "Alerts first" chip (ADM-050–052).
- **3d Ops overview (dark)**: rail + cards in dark tokens; revenue-by-outlet horizontal bars (azure gradient fills on #2B3C58 tracks); top-staff chips; live activity feed (completed / payment webhook verified / quote accepted→converted / low stock / idempotent loyalty posting).

## Interactions & Behavior (motion = M3 Expressive)
- Shared-axis transitions between booking steps; container-transform from task card → checklist detail, reward card → redeem sheet.
- Progress rings/bars animate on value change (spring, ~350–500ms); confirmation blob scales in w/ overshoot + confetti dots stagger.
- Scan screen: scan line loops vertically; success = haptic + green flash then container-transform to review screen (haptics configurable, non-essential).
- Real-time: timeline stages, task lists, KPI values and activity feed update via server events without refresh (ARC-003); reduced-motion mode disables non-essential animation (UX-004).
- Offline: forms preserve state (UX-009); queued ops show pending indicators; sync chip states = synced (green) / queued (gold) / offline (banner).
- All status/priority/tier chips are pill-shaped; touch targets ≥44px (staff primary actions ≥48px, gloved use — UX-006).

## State Management (per screen family)
- Booking flow: draft persists locally (offline-capable), server revalidates availability + price on submit (CUS-022/023); states Draft→Pending→Confirmed→In Service→Completed/Cancelled (CUS-025).
- Payment: initiated/pending/successful/failed/cancelled/refunded; backend webhook is source of truth (CUS-041/042); UI shows verified state only after server confirmation.
- Tasks/checklist: queued→assigned→in progress→blocked→completed→verified, transitions validated server-side (STF-023); offline queue with op ids (DAT-005).
- Loyalty: balance derived from ledger; awards idempotent (CUS-063/064).

## Assets
- `assets/logo-light.png` — full-color logo for light surfaces (grey car, blue wordmark)
- `assets/logo-dark.png` — white-text logo for dark/navy surfaces
- Icons: Material Symbols Rounded (Google Fonts); font: Outfit (Google Fonts)
- Photo areas use striped placeholders — replace with real imagery/camera capture.

## Files
- `Sparkling UI Mockups.dc.html` — the full mockup canvas (all 23 screens, inline-styled; open in a browser)
- `screenshots/*.png` — per-screen captures, named `<id>-<slug>.png`
