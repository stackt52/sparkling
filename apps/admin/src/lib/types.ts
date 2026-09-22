/**
 * Domain types mirroring backend/supabase/migrations/0001_schema.sql and the
 * admin routes in docs/API.md. All money is integer cents (ZAR), timestamps ISO-8601.
 */

export type UserRole = 'customer' | 'technician' | 'supervisor' | 'manager' | 'admin' | 'finance';
export const ADMIN_ROLES: UserRole[] = ['manager', 'admin', 'finance', 'supervisor'];

export type ServiceCategory = 'car_wash' | 'auto_body';
/** Price-sheet groups (migration 0008). */
export type ServiceGroup = 'Car Wash Options' | 'Combinations' | 'Auto Body Repair';
export const SERVICE_GROUPS: ServiceGroup[] = ['Car Wash Options', 'Combinations', 'Auto Body Repair'];
export type PricingMode = 'from' | 'fixed' | 'by_quote';
export type VatMode = 'incl' | 'excl';
/** Vehicle size class used for pricing (`vehicles.size_class`; null → small). */
export type VehicleSize = 'small' | 'large' | 'bike';
export const VEHICLE_SIZES: VehicleSize[] = ['small', 'large', 'bike'];
/** VAT rate applied on top of `vat_mode: excl` prices. */
export const VAT_RATE = 0.15;
export type BookingStatus = 'draft' | 'pending' | 'confirmed' | 'in_service' | 'completed' | 'cancelled';
export type QuotationStatus =
  | 'requested'
  | 'assessing'
  | 'quoted'
  | 'accepted'
  | 'declined'
  | 'expired'
  | 'converted';
export type WorkStatus =
  | 'queued'
  | 'assigned'
  | 'in_progress'
  | 'blocked'
  | 'completed'
  | 'verified'
  | 'cancelled';
export type PaymentStatus = 'initiated' | 'pending' | 'successful' | 'failed' | 'cancelled' | 'refunded';
/** Loyalty tier = membership plan tier (docs/MEMBERSHIPS.md): silver is the free default. */
export type LoyaltyTier = 'silver' | 'gold' | 'platinum' | 'black';
export const LOYALTY_TIERS: LoyaltyTier[] = ['silver', 'gold', 'platinum', 'black'];
export type LedgerType = 'earn' | 'redeem' | 'adjust' | 'expire' | 'bonus';
export type AlertLevel = 'low' | 'out';
export type StepType = 'confirm' | 'text' | 'numeric' | 'select' | 'photo' | 'ack' | 'supervisor_verify';
export type ConfigStatus = 'draft' | 'published' | 'archived';

export interface ApiError {
  code:
    | 'unauthenticated'
    | 'forbidden'
    | 'not_found'
    | 'validation_error'
    | 'conflict'
    | 'invalid_transition'
    | 'rate_limited'
    | 'gone'
    | 'internal'
    | 'network';
  message: string;
  /** Validation issues (array) or a conflict payload such as `{ existing_customer }` / `{ existing_vehicle_id }`. */
  details?: unknown;
  correlation_id?: string;
}

export interface Page<T> {
  data: T[];
  next_cursor: string | null;
}

/* ---------- identity ---------- */
export interface Profile {
  id: string;
  role: UserRole;
  full_name: string;
  email: string | null;
  phone: string | null;
  avatar_url: string | null;
  is_active: boolean;
  marketing_opt_in: boolean;
  whatsapp_opt_in: boolean;
  push_opt_in: boolean;
  last_seen_at: string | null;
  created_at: string;
  /** Set when the account was created (or reset) with a temporary password; the app forces a password change (ADM-010). */
  must_change_password: boolean;
  password_changed_at: string | null;
}

export interface SessionResponse {
  profile: Profile & { outlet_ids?: string[] };
  /** Outlets the staff member belongs to (top-level in `POST /auth/session`). */
  outlet_ids?: string[];
  claims_updated: boolean;
}

export interface StaffUser extends Profile {
  outlet_ids: string[];
  outlet_names: string[];
  skills: string[];
  availability?: 'available' | 'busy' | 'break' | 'off' | null;
}

/** `POST /admin/users` body (ADM-010). `invite:'link'` additionally returns a Firebase password-reset link. */
export interface CreateStaffInput {
  email: string;
  full_name: string;
  role: UserRole;
  phone?: string | null;
  outlet_ids: string[];
  skills?: string[];
  invite?: 'password' | 'link';
}

/** `201` from `POST /admin/users`: the temporary password is shown once to the admin. */
export interface CreateStaffResult {
  profile: Profile;
  uid: string;
  temporary_password: string;
  invite_link: string | null;
}

/** `POST /admin/users/:id/reset-password`. */
export interface ResetPasswordResult {
  profile: Profile;
  temporary_password: string;
}

/* ---------- catalogue ---------- */
export type OpeningHours = Record<'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun', [string, string] | null>;

/** `outlets.bank_details` JSON (migration 0007) — printed under "Our banking details" on quotes. */
export interface OutletBankDetails {
  financial_institution: string | null;
  account_name: string | null;
  branch: string | null;
  branch_code: string | null;
  account_number: string | null;
  account_type: string | null;
}

/** Per-outlet legal / billing identity (migration 0007) as embedded on quotations. */
export interface OutletLegal {
  legal_name: string | null;
  trading_as: string | null;
  company_registration_no: string | null;
  vat_number: string | null;
  registered_office: string | null;
  bank_details: OutletBankDetails | null;
}

export interface Outlet extends OutletLegal {
  id: string;
  code: string;
  name: string;
  address_line: string | null;
  city: string | null;
  province: string | null;
  phone: string | null;
  email: string | null;
  timezone: string;
  opening_hours: OpeningHours;
  slot_minutes: number;
  bay_count: number;
  rating: number | null;
  is_active: boolean;
}

/** One row of a composite's "includes" set (`service_components`). */
export interface ServiceComponent {
  child_service_id: string;
  quantity: number;
  sort_order: number;
}

/** Canonical service (`services`, migration 0008) as returned by `GET /admin/services` (with `components`). */
export interface Service {
  id: string;
  code: string;
  name: string;
  description: string | null;
  category: ServiceCategory;
  group_name: ServiceGroup;
  duration_minutes: number;
  /** Legacy: mirrors `price_small_cents ?? price_general_cents ?? 0` for old readers. */
  base_price_cents: number;
  /** Legacy: `pricing_mode === 'by_quote'`. */
  is_quote_based: boolean;
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  is_addon: boolean;
  addon_group_name: string | null;
  notes: string | null;
  points_per_rand: number;
  icon: string;
  checklist_template_id: string | null;
  is_active: boolean;
  sort_order: number;
  /** Global default composition (outlets may override). */
  components: ServiceComponent[];
}

/** `POST/PUT /admin/services` body. */
export type ServiceInput = Partial<Omit<Service, 'id' | 'components'>> & { components?: ServiceComponent[] };

/** `PUT /admin/outlets/:id/services/:serviceId` body (`components: null` = use the global set). */
export interface OutletServiceInput {
  display_name?: string | null;
  price_small_cents?: number | null;
  price_large_cents?: number | null;
  price_general_cents?: number | null;
  pricing_mode?: PricingMode | null;
  vat_mode?: VatMode | null;
  is_available?: boolean;
  sort_order?: number | null;
  notes?: string | null;
  components?: ServiceComponent[] | null;
}

export interface ChecklistStep {
  key: string;
  title: string;
  type: StepType;
  required: boolean;
  hint?: string;
  options?: string[];
  unit?: string;
  min?: number;
  max?: number;
  photo_required?: boolean;
}

export interface ChecklistTemplate {
  id: string;
  name: string;
  category: ServiceCategory;
  version: number;
  status: ConfigStatus;
  steps: ChecklistStep[];
  outlet_id: string | null;
  created_by: string | null;
  created_at: string;
}

/* ---------- customers ---------- */
export interface Vehicle {
  id: string;
  customer_id: string;
  registration_no: string;
  vin: string | null;
  make: string | null;
  model: string | null;
  colour: string | null;
  year: number | null;
  disc_expiry: string | null;
  source: 'manual' | 'scan';
  disc_verified: boolean;
  /** Pricing size class (null = unknown → small). */
  size_class?: VehicleSize | null;
}

export interface LoyaltyAccount {
  customer_id: string;
  tier: LoyaltyTier;
  balance_points: number;
  lifetime_points: number;
  tier_since: string;
}

/** Loyalty summary on customer rows: the live plan (docs/MEMBERSHIPS.md "customer summary"). */
export interface LoyaltySummary extends LoyaltyAccount {
  plan_code: string | null;
  plan_name: string | null;
  /** Sum of remaining monthly washes across the selected entitlements (0 for non-members). */
  included_remaining: number;
}

export interface LedgerEntry {
  id: string;
  customer_id: string;
  delta: number;
  type: LedgerType;
  reference: string | null;
  description: string | null;
  idempotency_key: string;
  created_at: string;
}

export interface CustomerSummary extends Profile {
  vehicle_count: number;
  booking_count: number;
  loyalty?: LoyaltySummary;
}

export interface CustomerDetail extends CustomerSummary {
  vehicles: Vehicle[];
  bookings: Booking[];
  ledger: LedgerEntry[];
  /** `GET /admin/customers/:id` adds the membership summary (same shape as `/memberships/me`). */
  membership?: MembershipSummary | null;
}

/* ---------- bookings / work ---------- */
export interface WorkOrderSummary {
  id: string;
  ref: string;
  status: WorkStatus;
  stage: number;
  stage_count: number;
  progress_pct: number;
  assignee_id: string | null;
  assignee_name: string | null;
  bay: string | null;
  eta_at: string | null;
  blocked_reason: string | null;
}

/** How the customer chose to pay at booking time (`cash` = cash on collection, feature flag `cash_on_collection`). */
export type BookingPaymentMethod = 'card' | 'eft' | 'cash';

export interface Booking {
  id: string;
  ref: string;
  customer_id: string;
  status: BookingStatus;
  slot_start: string;
  slot_end: string;
  price_cents: number;
  discount_cents: number;
  total_cents: number;
  discount_label: string | null;
  points_pending: number;
  notes: string | null;
  cancel_reason: string | null;
  created_at: string;
  outlet: { id: string; name: string };
  service: { id: string; name: string; category: ServiceCategory; duration_minutes: number };
  vehicle: { id: string; registration_no: string; make: string | null; model: string | null };
  customer: { id: string; full_name: string; email: string | null; phone: string | null };
  work_order: WorkOrderSummary | null;
  payment: { id: string; status: PaymentStatus; receipt_no: string | null; amount_cents: number; method?: PosPaymentMethod | null; provider?: string | null } | null;
  /**
   * Chosen at booking time. A `cash` booking is created `confirmed` with no online payment; `payment` stays null
   * until staff record the cash at the counter (`POST /payments/record`), and collection is refused (409
   * `validation_error` `{ reason: 'payment_due', amount_cents }`) until then.
   */
  payment_method?: BookingPaymentMethod | null;
  quotation_id: string | null;
  /** Staff-created walk-in (STF-010/012). */
  walk_in?: boolean;
  created_by?: string | null;
  created_by_name?: string | null;
  /* ---- catalogue pricing (migration 0008) ---- */
  /** Size the price was resolved for. */
  vehicle_size?: VehicleSize | null;
  pricing_mode?: PricingMode | null;
  vat_mode?: VatMode | null;
  addon_service_ids?: string[];
  /** Sum of the add-on prices (already inside `price_cents`). */
  addons_cents?: number;
  /** "From R x" / "R x" / "By quote" as shown at booking time. */
  price_label?: string | null;
  addons?: { service_id: string; name: string; price_cents: number }[];
  /** 15 % VAT added on top when `vat_mode === 'excl'` (0 otherwise). */
  vat_cents?: number;
  /* ---- membership plans (migration 0010) ---- */
  membership_id?: string | null;
  entitlement_id?: string | null;
  membership_benefit?: MembershipBenefit | null;
  /** Pricing response block: which plan / entitlement priced this booking. */
  membership?: MembershipPricing | null;
}

export interface TimelineStage {
  key: string;
  title: string;
  state: 'done' | 'current' | 'pending' | 'blocked';
  at: string | null;
  actor?: string | null;
}

export interface BookingDetail extends Booking {
  timeline: TimelineStage[];
}

/** Attention-area categories used on quote items (staff app + admin chips). */
export const QUOTE_ITEM_CATEGORIES = ['dent', 'scratch', 'bumper', 'panel', 'paint', 'glass', 'other'] as const;
export type QuoteItemCategory = (typeof QUOTE_ITEM_CATEGORIES)[number];

/** One attention area on a quotation (docs/API.md "Staff-raised quotations"). */
export interface QuoteLineItem {
  label: string;
  description?: string | null;
  category?: QuoteItemCategory | string | null;
  service_id?: string | null;
  amount_cents: number;
  quantity?: number | null;
}

export type QuotationDecisionSource = 'app' | 'public_link' | 'staff';

/** Attachment as served by `GET /quotations/:id` — images are always streamed through the API. */
export interface QuotationAttachment {
  id: string;
  /** `/v1/quotations/:id/photos/:attachmentId` (signed-in) — resolve against the API base. */
  url?: string | null;
  kind?: 'damage_photo' | 'document';
  caption?: string | null;
  width?: number | null;
  height?: number | null;
  mime_type?: string | null;
  size_bytes?: number | null;
  storage_path?: string | null;
}

export interface Quotation {
  id: string;
  ref: string;
  customer_id: string;
  customer_name: string;
  vehicle: { id: string; registration_no: string; make: string | null; model: string | null; colour?: string | null };
  outlet: { id: string; name: string; code?: string | null; phone?: string | null; email?: string | null; address_line?: string | null; city?: string | null } & Partial<OutletLegal>;
  category: string;
  description: string;
  status: QuotationStatus;
  amount_cents: number | null;
  line_items: QuoteLineItem[];
  /** Alias of `line_items` (newer API responses carry both). */
  items?: QuoteLineItem[];
  items_note?: string | null;
  assessor_id: string | null;
  assessor_name: string | null;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_note: string | null;
  decision_source?: QuotationDecisionSource | null;
  decision_by_name?: string | null;
  attachments: QuotationAttachment[];
  created_at: string;
  work_order_ref?: string | null;
  /** Staff only: `<PUBLIC_WEB_BASE_URL>/q/<token>`; null until the quote has been shared. */
  public_url?: string | null;
  public_token_expires_at?: string | null;
  /** `/v1/quotations/:id/pdf` (signed-in). */
  pdf_url?: string | null;
  /** Standard terms printed on the quote (see `QUOTE_TERMS`). */
  terms?: string;
}

/** `POST /quotations` (staff shape): raise a quote for a walk-in customer in one step. */
export interface RaiseQuotationInput {
  customer_id: string;
  vehicle_id: string;
  outlet_id: string;
  category: string;
  description: string;
  items: QuoteLineItem[];
  valid_until: string;
  items_note?: string | null;
  client_op_id: string;
  send_to_customer?: boolean;
}

export interface ShareQuotationResult {
  public_url: string;
  expires_at: string;
}

/** `GET /public/quotations/:token` — the customer-facing view, no PII beyond what the quote needs. */
export interface PublicQuotation {
  ref: string;
  status: QuotationStatus;
  outlet: { name: string; code?: string | null; phone: string | null; email?: string | null; address_line: string | null; city?: string | null } & Partial<OutletLegal>;
  customer: { first_name: string };
  vehicle: { registration_no: string; make: string | null; model: string | null; colour: string | null };
  items: QuoteLineItem[];
  amount_cents: number;
  currency: string;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_source: QuotationDecisionSource | null;
  decision_by_name?: string | null;
  expired: boolean;
  can_decide: boolean;
  attachments: { id: string; url: string; caption: string | null; width: number | null; height: number | null }[];
  /** `/v1/public/quotations/:token/pdf` — resolve against the API base. */
  pdf_url: string;
  notes: string | null;
  /** Standard terms printed on the quote (see `QUOTE_TERMS`). */
  terms?: string;
}

export interface PublicDecisionInput {
  decision: 'accept' | 'decline';
  note?: string;
  accepted_by_name?: string;
}

/** `tasks` row as answered by `POST /tasks/:id/assign|transition` (only the fields the dashboard reads). */
export interface Task {
  id: string;
  work_order_id: string;
  status: WorkStatus;
  assignee_id: string | null;
}

export interface TaskEvent {
  id: string;
  actor_name: string | null;
  event: string;
  from_status: string | null;
  to_status: string | null;
  reason: string | null;
  created_at: string;
}

/** `GET /admin/work-orders[/:id]` row — the board card with names, refs, progress and the task audit trail. */
export interface WorkOrder {
  id: string;
  ref: string;
  outlet: { id: string; name: string };
  booking_ref: string | null;
  quotation_ref: string | null;
  customer_name: string;
  vehicle: { registration_no: string; make: string | null; model: string | null };
  service: { name: string; category: ServiceCategory };
  status: WorkStatus;
  priority: 1 | 2 | 3;
  bay: string | null;
  assignee_id: string | null;
  assignee_name: string | null;
  eta_at: string | null;
  due_at: string | null;
  started_at: string | null;
  blocked_reason: string | null;
  steps_done: number;
  step_count: number;
  /** First task of the work order — what `assignTask` / `transitionTask` act on (null only for legacy rows without a task). */
  task_id: string | null;
  events: TaskEvent[];
  updated_at: string;
}

/* ---------- walk-in (staff on behalf of a customer) ---------- */
export interface WalkInVehicle {
  id: string;
  registration_no: string;
  make: string | null;
  model: string | null;
  colour: string | null;
  disc_verified: boolean;
  size_class?: VehicleSize | null;
}

/** `GET /staff/customers` row. */
export interface WalkInCustomer {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  marketing_opt_in: boolean;
  whatsapp_opt_in: boolean;
  /** `discount_pct` is always 0 now — discounts come from the plan (`plan_code`). */
  loyalty: { tier: LoyaltyTier; balance_points: number; discount_pct: number; plan_code: string | null; plan_name: string | null; included_remaining: number } | null;
  vehicles: WalkInVehicle[];
}

export interface WalkInCustomerInput {
  full_name: string;
  phone: string;
  email?: string | null;
  marketing_opt_in?: boolean;
  whatsapp_opt_in?: boolean;
  client_op_id: string;
}

export interface VehicleInput {
  registration_no: string;
  vin?: string | null;
  make?: string | null;
  model?: string | null;
  colour?: string | null;
  year?: number | null;
  source: 'manual' | 'scan';
  size_class?: VehicleSize | null;
  client_op_id: string;
}

export type WalkInPriority = 1 | 2 | 3;

export interface WalkInBookingInput {
  customer_id: string;
  vehicle_id: string;
  outlet_id: string;
  service_id: string;
  walk_in: true;
  /** Size used for pricing (defaults to the vehicle's `size_class`, else small). */
  vehicle_size?: VehicleSize;
  /** Add-ons (`is_addon` services of the chosen service's group) priced and summed into `addons_cents`. */
  addon_service_ids?: string[];
  /** Omit to book "now" (server rounds up to the outlet's slot grid). */
  slot_start?: string;
  notes?: string | null;
  client_op_id: string;
  checkin?: { bay?: string | null; priority?: WalkInPriority };
  /** `cash` needs the `cash_on_collection` flag (409 `validation_error` `{ reason: 'cash_disabled' }` otherwise). */
  payment_method?: BookingPaymentMethod | null;
}

export interface WalkInBookingResult {
  booking: Booking;
  duplicate: boolean;
  work_order?: WorkOrderSummary | null;
  task?: { id: string; status: WorkStatus } | null;
}

export type PosPaymentMethod = 'cash' | 'card_terminal';

export interface RecordPaymentInput {
  booking_id: string;
  method: PosPaymentMethod;
  reference?: string | null;
  amount_cents: number;
  idempotency_key: string;
}

/** `payments` row created by `POST /payments/record` (provider `pos`). */
export interface PosPayment {
  id: string;
  booking_id: string;
  method: PosPaymentMethod;
  provider: string;
  amount_cents: number;
  status: PaymentStatus;
  receipt_no: string | null;
  provider_ref: string | null;
  verified_at: string | null;
  created_at: string;
}

/** `GET /availability` row (wraps `get_available_slots`). */
export interface AvailabilitySlot {
  slot_start: string;
  slot_end: string;
  capacity: number;
  booked: number;
  available: boolean;
}

/** `GET /outlets/:id/services` row — the outlet's offer with resolved prices and composition (docs/API.md "Catalogue pricing model"). */
export interface OutletServiceOffer {
  /** Alias of `service_id` so offers can be used where a `Service`-like `id` is expected. */
  id: string;
  service_id: string;
  code: string;
  /** `display_name ?? services.name`. */
  name: string;
  /** Canonical name (for "also known as"). */
  service_name: string;
  display_name: string | null;
  description: string | null;
  group_name: ServiceGroup;
  category: ServiceCategory;
  duration_minutes: number;
  icon: string;
  /** Effective (outlet override ?? service default). */
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  /** Raw outlet overrides (null = inherit). */
  pricing_mode_override: PricingMode | null;
  vat_mode_override: VatMode | null;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  /** Lowest non-null price; null when by-quote. */
  price_from_cents: number | null;
  /** Resolved per size (null when by-quote / no price). */
  price_for: Record<VehicleSize, number | null>;
  /** Resolved for `?vehicle_size` when requested. */
  price_cents?: number | null;
  is_addon: boolean;
  addon_group_name: string | null;
  includes: { service_id: string; code: string; name: string; quantity: number }[];
  included_in: string[];
  /** Whether `includes` comes from an outlet-specific set or the global default. */
  components_source: 'outlet' | 'global';
  is_available: boolean;
  sort_order: number | null;
  notes: string | null;
  points_estimate: number;
  /** Legacy alias of `pricing_mode === 'by_quote'`. */
  is_quote_based: boolean;
}

/** Derives the pricing size from a vehicle (disc description mapping; null → small). */
export function vehicleSizeOf(v: { size_class?: VehicleSize | null; model?: string | null } | null | undefined): VehicleSize {
  if (v?.size_class) return v.size_class;
  const m = (v?.model ?? '').toLowerCase();
  if (/hilux|ranger|bakkie|pick-?up|suv|x-?trail|fortuner|everest|amarok|navara|d-?max|cx-?5|tucson|sportage|rav4|kuga|tiguan|q5|x3|x5|glc|discovery|defender|bus|quantum|hiace|wagon/.test(m)) return 'large';
  return 'small';
}

/** Price shown for an offer at a size: outlet/service price per size (bike → small, general when size-independent). */
export function offerPrice(o: OutletServiceOffer, size: VehicleSize): number | null {
  if (o.pricing_mode === 'by_quote') return null;
  return o.price_for[size] ?? null;
}

/** "From R x" / "R x" / "By quote" (+ "excl. VAT" for excl offers). */
export function priceLabel(o: Pick<OutletServiceOffer, 'pricing_mode' | 'vat_mode'>, cents: number | null, fmt: (c: number) => string): string {
  if (o.pricing_mode === 'by_quote' || cents === null) return 'By quote';
  const base = o.pricing_mode === 'from' ? `From ${fmt(cents)}` : fmt(cents);
  return o.vat_mode === 'excl' ? `${base} excl. VAT` : base;
}

/* ---------- payments ---------- */
export interface Payment {
  id: string;
  booking_ref: string | null;
  /** Set for membership invoice payments (`booking_ref` is null for these). */
  membership_invoice_id?: string | null;
  customer_name: string;
  provider: string;
  amount_cents: number;
  status: PaymentStatus;
  receipt_no: string | null;
  verified_at: string | null;
  created_at: string;
}

/* ---------- loyalty config ---------- */
export interface LoyaltyTierConfig {
  tier: LoyaltyTier;
  name: string;
  min_points: number;
  max_points: number | null;
  earn_multiplier: number;
  discount_pct: number;
  perks?: string;
  members?: number;
}

export interface LoyaltyRules {
  points_per_rand: number;
  award_on: 'completion' | 'payment';
  idempotent_award: boolean;
  expiry_months: number;
  birthday_bonus: { enabled: boolean; points: number; reason?: string };
  referral_bonus: { enabled: boolean; points: number };
}

export interface LoyaltyConfig {
  id: string;
  version: number;
  status: ConfigStatus;
  tiers: LoyaltyTierConfig[];
  rules: LoyaltyRules;
  change_note: string | null;
  created_by: string | null;
  published_by: string | null;
  published_at: string | null;
  created_at: string;
}

export interface LoyaltyConfigResponse {
  published: LoyaltyConfig;
  draft: LoyaltyConfig | null;
}

/* ---------- inventory ---------- */
export interface InventoryItem {
  id: string;
  outlet_id: string;
  outlet_name: string;
  sku: string;
  name: string;
  unit: string;
  on_hand: number;
  reorder_threshold: number;
  pack_size: number | null;
  /** Suggested full level used to draw the level bar. */
  capacity: number;
  is_active: boolean;
  alert: { id: string; level: AlertLevel; status: 'open' | 'acknowledged' | 'resolved'; created_at: string } | null;
  blocking_work_orders: number;
  updated_at: string;
}

/* ---------- staff performance ---------- */
export interface StaffPerformanceRow {
  staff_id: string;
  name: string;
  outlet_name: string;
  tasks_completed: number;
  avg_cycle_minutes: number;
  checklist_compliance_pct: number;
  points: number;
  points_period: number;
  rank: number;
  delta: number;
  badges: { code: string; name: string; icon: string; colour: string; earned_at: string }[];
}

/* ---------- ops ---------- */
export type Period = 'today' | 'week' | 'month';

export interface Kpis {
  period: Period;
  revenue_cents: number;
  revenue_trend_pct: number;
  revenue_compare_label: string;
  bookings_count: number;
  bookings_completed: number;
  bookings_in_service: number;
  on_time_pct: number;
  active_work_orders: number;
  completed_today: number;
  avg_cycle_minutes: number;
  cycle_delta_minutes: number;
  quotes_accepted: number;
  quotes_total: number;
  exceptions_count: number;
  exceptions_breakdown: { blocked: number; overdue: number; low_stock: number; failed_payments: number };
  bookings_by_hour: { hour: number; car_wash: number; auto_body: number; future: boolean }[];
  revenue_by_outlet: { outlet_id: string; name: string; revenue_cents: number }[];
  top_staff: { staff_id: string; name: string; initials: string; points: number; tier: 'gold' | 'silver' | 'bronze' }[];
  services_count: number;
  outlets_count: number;
  /** Live memberships (active + past_due). */
  active_members: number;
  /** Monthly recurring revenue of active memberships. */
  membership_mrr_cents: number;
}

export type ExceptionKind = 'blocked' | 'overdue' | 'low_stock' | 'out_of_stock' | 'failed_payment';
export interface ExceptionItem {
  id: string;
  kind: ExceptionKind;
  title: string;
  subtitle: string;
  severity: 'error' | 'warning';
  icon: string;
  link: { type: 'work_order' | 'inventory_item' | 'payment' | 'booking'; id: string };
  created_at: string;
}

export interface ActivityItem {
  id: string;
  kind: 'completed' | 'payment' | 'quote' | 'stock' | 'loyalty' | 'assigned' | 'blocked';
  title: string;
  subtitle: string;
  icon: string;
  tone: 'success' | 'primary' | 'warning' | 'error' | 'neutral';
  at: string;
}

/* ---------- audit / flags ---------- */
export interface AuditEvent {
  id: string;
  actor_id: string | null;
  actor_name: string | null;
  actor_role: string | null;
  action: string;
  entity_type: string;
  entity_id: string | null;
  outlet_id: string | null;
  before: unknown;
  after: unknown;
  correlation_id: string | null;
  outcome: string;
  created_at: string;
}

export interface FeatureFlag {
  key: string;
  enabled: boolean;
  description: string | null;
  updated_at: string;
}

export interface IntegrationStatus {
  key: 'supabase' | 'firebase' | 'payments' | 'whatsapp';
  name: string;
  status: 'connected' | 'sandbox' | 'disabled' | 'demo' | 'error';
  detail: string;
  icon: string;
  /** WhatsApp (Twilio) card: `{ provider, configured, messaging_service, enabled }` — never secrets. */
  provider?: string;
  configured?: boolean;
  messaging_service?: string | null;
  enabled?: boolean;
}

/* ---------- notifications ---------- */
export type NotifyChannel = 'push' | 'whatsapp' | 'sms' | 'email';
export type NotifyStatus = 'queued' | 'sent' | 'delivered' | 'failed' | 'suppressed';

/** `notifications` row as returned by `GET /admin/notifications` (with recipient + provider expansions). */
export interface NotificationRow {
  id: string;
  recipient_id: string;
  recipient_name: string | null;
  channel: NotifyChannel;
  template_key: string;
  title: string | null;
  body: string;
  payload: Record<string, unknown>;
  status: NotifyStatus;
  /** Provider-side state (Twilio: queued / sent / delivered / read / undelivered / failed). */
  provider_status: string | null;
  provider_ref: string | null;
  /** Provider error code (e.g. Twilio `63016` = outside the 24 h session window). */
  provider_error_code: string | null;
  error: string | null;
  attempts: number;
  sent_at: string | null;
  delivered_at: string | null;
  read_at: string | null;
  created_at: string;
}

export type ReportKind = 'bookings' | 'payments' | 'inventory' | 'staff_performance' | 'loyalty' | 'memberships';

export interface ReportSummary {
  financial: {
    revenue_cents: number;
    refunds_cents: number;
    payments_successful: number;
    payments_failed: number;
    avg_ticket_cents: number;
    by_outlet: { name: string; revenue_cents: number; bookings: number }[];
    by_service: { name: string; revenue_cents: number; count: number }[];
  };
  operational: {
    bookings: number;
    completed: number;
    cancelled: number;
    on_time_pct: number;
    avg_cycle_minutes: number;
    checklist_compliance_pct: number;
    quotes: { requested: number; quoted: number; accepted: number; converted: number };
  };
}

/* ---------- membership plans (docs/MEMBERSHIPS.md, migration 0010) ---------- */
export type MembershipStatus = 'pending' | 'active' | 'past_due' | 'cancelled' | 'expired';
export const MEMBERSHIP_STATUSES: MembershipStatus[] = ['pending', 'active', 'past_due', 'cancelled', 'expired'];
export type MembershipPaymentMethod = 'card' | 'cash' | 'eft' | 'sandbox' | 'card_terminal';
/** Counter enrolment methods (`POST /admin/customers/:id/membership`). */
export type CounterPaymentMethod = 'cash' | 'card_terminal' | 'eft';
export type DiscountScope = 'plan_services' | 'other_services' | 'all_services' | 'none';
export const DISCOUNT_SCOPES: DiscountScope[] = ['plan_services', 'other_services', 'all_services', 'none'];
export type EntitlementPeriod = 'month' | 'year';
export type GroupSelection = 'choose_one' | 'all';
export type MembershipBenefit = 'included' | 'discount';
export type MembershipInvoiceStatus = 'pending' | 'paid' | 'failed' | 'void';

export interface EntitlementService {
  id: string;
  code: string;
  name: string;
  is_primary: boolean;
}

export interface PlanEntitlement {
  id: string;
  code: string;
  label: string;
  quantity: number;
  period: EntitlementPeriod;
  services: EntitlementService[];
}

export interface PlanGroup {
  id: string;
  code: string;
  name: string;
  selection: GroupSelection;
  entitlements: PlanEntitlement[];
}

/** `GET /admin/memberships/plans` row (`member_count` / `mrr_cents` are admin-only extras). */
export interface MembershipPlan {
  id: string;
  code: string;
  tier: LoyaltyTier;
  name: string;
  tagline: string | null;
  monthly_fee_cents: number;
  discount_pct: number;
  discount_scope: DiscountScope;
  discount_note: string | null;
  color: string | null;
  sort_order: number;
  is_active: boolean;
  groups: PlanGroup[];
  member_count?: number;
  mrr_cents?: number;
}

/** `PUT /admin/memberships/plans/:code` body — full replace of groups / entitlements by code. */
export interface MembershipPlanInput {
  name: string;
  tagline: string | null;
  monthly_fee_cents: number;
  discount_pct: number;
  discount_scope: DiscountScope;
  discount_note: string | null;
  is_active: boolean;
  groups: {
    code: string;
    name: string;
    selection: GroupSelection;
    entitlements: { code: string; label: string; quantity: number; period: EntitlementPeriod; service_codes: string[] }[];
  }[];
}

export interface Membership {
  id: string;
  ref: string;
  customer_id: string;
  plan_id: string;
  status: MembershipStatus;
  started_at: string;
  current_period_start: string;
  current_period_end: string;
  cancel_at_period_end: boolean;
  cancelled_at: string | null;
  ended_at: string | null;
  next_plan_id: string | null;
  payment_method: MembershipPaymentMethod;
  created_by: string | null;
  created_at: string;
}

export interface MembershipInvoice {
  id: string;
  ref: string;
  membership_id: string;
  customer_id: string;
  period_start: string;
  period_end: string;
  amount_cents: number;
  status: MembershipInvoiceStatus;
  due_at: string;
  paid_at: string | null;
  payment_id: string | null;
}

/** Remaining allowance of one entitlement for its current period. */
export interface MembershipAllowance {
  entitlement_id: string;
  entitlement_code: string;
  group_code: string;
  label: string;
  quantity: number;
  used: number;
  remaining: number;
  period: EntitlementPeriod;
  period_start: string;
  period_end: string;
}

/** `GET /memberships/me` / `GET /staff/customers/:id/membership` / `customer.membership`. */
export interface MembershipSummary {
  membership: Membership | null;
  plan: MembershipPlan | null;
  /** Chosen option per `choose_one` group: `{ [group_code]: entitlement_code }`. */
  selections: Record<string, string>;
  allowances: MembershipAllowance[];
  open_invoice: MembershipInvoice | null;
  /** Last 12. */
  invoices: MembershipInvoice[];
  next_renewal_at: string | null;
  benefits_summary: string;
}

/** `GET /admin/memberships` row. */
export interface MembershipRow extends Membership {
  customer: { id: string; full_name: string; email: string | null; phone: string | null };
  plan: { id: string; code: string; name: string; tier: LoyaltyTier; monthly_fee_cents: number };
  selections: Record<string, string>;
  allowances: MembershipAllowance[];
  /** Monthly washes used / remaining (sum over month-period entitlements). */
  used: number;
  remaining: number;
  open_invoice: MembershipInvoice | null;
}

export interface EnrolMembershipInput {
  plan_code: string;
  selections: Record<string, string>;
  payment_method: CounterPaymentMethod;
  client_op_id: string;
}

/** Pricing response block added to bookings priced for a member. */
export interface MembershipPricing {
  plan_code: string;
  plan_name: string;
  benefit: MembershipBenefit | null;
  entitlement_code: string | null;
  /** Remaining for the entitlement *after* this booking (included only). */
  remaining_after: number | null;
  period_end: string | null;
}

export interface RenewalRunResult {
  expired: number;
  invoiced: number;
  past_due: number;
  renewed: number;
}

/** `POST /admin/memberships/:id/invoices/:invoiceId/record-payment` → the paid invoice and the rolled membership. */
export interface RecordMembershipPaymentResult {
  invoice: MembershipInvoice;
  membership: Membership;
  payment?: PosPayment | null;
  duplicate?: boolean;
}
