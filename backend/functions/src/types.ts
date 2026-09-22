/**
 * Domain types mirrored from backend/supabase/migrations/0001_schema.sql.
 * Column names are the API's JSON field names (snake_case).
 */
import type { Logger } from 'pino';

export type UserRole = 'customer' | 'technician' | 'supervisor' | 'manager' | 'admin' | 'finance';
export type ServiceCategory = 'car_wash' | 'auto_body';
export type BookingStatus = 'draft' | 'pending' | 'confirmed' | 'in_service' | 'completed' | 'cancelled';
export type QuotationStatus = 'requested' | 'assessing' | 'quoted' | 'accepted' | 'declined' | 'expired' | 'converted';
export type WorkStatus = 'queued' | 'assigned' | 'in_progress' | 'blocked' | 'completed' | 'verified' | 'cancelled';
export type StepStatus = 'pending' | 'done' | 'blocked' | 'skipped';
export type StepType = 'confirm' | 'text' | 'numeric' | 'select' | 'photo' | 'ack' | 'supervisor_verify';
export type PaymentStatus = 'initiated' | 'pending' | 'successful' | 'failed' | 'cancelled' | 'refunded';
export type PosPaymentMethod = 'cash' | 'card_terminal' | 'card' | 'eft';
export type LoyaltyTier = 'silver' | 'gold' | 'platinum' | 'black';
export type LedgerType = 'earn' | 'redeem' | 'adjust' | 'expire' | 'bonus';
export type InventoryReason = 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count';
export type NotifyChannel = 'push' | 'whatsapp' | 'sms' | 'email';
export type NotifyStatus = 'queued' | 'sent' | 'delivered' | 'failed' | 'suppressed';
export type ConfigStatus = 'draft' | 'published' | 'archived';
export type SyncStatus = 'pending' | 'applied' | 'conflict' | 'rejected';
/** Catalogue pricing model (migration 0008). */
export type VehicleSize = 'small' | 'large' | 'bike';
export type PricingMode = 'from' | 'fixed' | 'by_quote';
export type VatMode = 'incl' | 'excl';
export type ServiceGroup = 'Car Wash Options' | 'Combinations' | 'Auto Body Repair';

export const VEHICLE_SIZES: VehicleSize[] = ['small', 'large', 'bike'];
export const PRICING_MODES: PricingMode[] = ['from', 'fixed', 'by_quote'];
export const VAT_MODES: VatMode[] = ['incl', 'excl'];
/** South African VAT rate applied on top of `excl` prices. */
export const VAT_RATE = 0.15;

export const STAFF_ROLES: UserRole[] = ['technician', 'supervisor', 'manager', 'admin', 'finance'];
export const SUPERVISOR_ROLES: UserRole[] = ['supervisor', 'manager', 'admin'];
export const MANAGER_ROLES: UserRole[] = ['manager', 'admin'];

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
  locale: string;
  reduced_motion: boolean;
  haptics: boolean;
  last_seen_at: string | null;
  deactivated_at: string | null;
  /** Staff created from the admin app sign in with a temporary password and must set their own first (migration 0012). */
  must_change_password: boolean;
  password_changed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Outlet {
  id: string;
  code: string;
  name: string;
  address_line: string | null;
  city: string | null;
  province: string | null;
  country: string;
  latitude: number | null;
  longitude: number | null;
  phone: string | null;
  email: string | null;
  timezone: string;
  opening_hours: Record<string, [string, string] | null>;
  slot_minutes: number;
  bay_count: number;
  rating: number | null;
  is_active: boolean;
  /** Legal / billing identity shown on quotation documents (migration 0007). */
  legal_name?: string | null;
  trading_as?: string | null;
  company_registration_no?: string | null;
  vat_number?: string | null;
  registered_office?: string | null;
  bank_details?: OutletBankDetails | null;
}

export interface OutletBankDetails {
  financial_institution?: string | null;
  account_name?: string | null;
  branch?: string | null;
  branch_code?: string | null;
  account_number?: string | null;
  account_type?: string | null;
}

export interface Service {
  id: string;
  code: string;
  name: string;
  description: string | null;
  category: ServiceCategory;
  duration_minutes: number;
  base_price_cents: number;
  is_quote_based: boolean;
  points_per_rand: number;
  icon: string | null;
  checklist_template_id: string | null;
  is_active: boolean;
  sort_order: number;
  /** Catalogue pricing model (migration 0008). */
  group_name: ServiceGroup | string;
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  is_addon: boolean;
  addon_group_name: string | null;
  notes: string | null;
}

/** `outlet_services` row: per-outlet binding with overrides (null = inherit from `services`). */
export interface OutletService {
  outlet_id: string;
  service_id: string;
  /** Legacy single price kept in step for old readers. */
  price_cents: number | null;
  is_available: boolean;
  display_name: string | null;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  pricing_mode: PricingMode | null;
  vat_mode: VatMode | null;
  sort_order: number | null;
  notes: string | null;
}

/** Composite membership: `parent` includes `child`; `outlet_id` null = global default set. */
export interface ServiceComponent {
  id: string;
  parent_service_id: string;
  child_service_id: string;
  outlet_id: string | null;
  quantity: number;
  sort_order: number;
  created_at?: string;
}

/** Input shape for replacing a composition set (admin). */
export interface ServiceComponentInput {
  child_service_id: string;
  quantity?: number;
  sort_order?: number;
}

/** `GET /outlets/:id/services` item — a service as offered (and worded) by one outlet. */
export interface OutletServiceOffer {
  /** Alias of `service_id` so an offer can stand in where a `Service`-like `id` is expected. */
  id: string;
  service_id: string;
  code: string;
  /** Outlet display_name ?? canonical service name. */
  name: string;
  /** Canonical service name (for "also known as"). */
  service_name: string;
  /** Outlet wording override (null = canonical name). */
  display_name: string | null;
  description: string | null;
  group_name: string;
  category: ServiceCategory;
  duration_minutes: number;
  icon: string | null;
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  /** Raw outlet overrides (null = inherit the service default). */
  pricing_mode_override: PricingMode | null;
  vat_mode_override: VatMode | null;
  /** Legacy alias of `pricing_mode === 'by_quote'`. */
  is_quote_based: boolean;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  /** Lowest non-null price; null when by-quote. */
  price_from_cents: number | null;
  /** Price resolved per vehicle size; null when by-quote. */
  price_for: Record<VehicleSize, number | null>;
  /** "From R 150" / "R 400 excl. VAT" / "By quotation". */
  price_label: string;
  is_addon: boolean;
  addon_group_name: string | null;
  includes: Array<{ service_id: string; code: string; name: string; quantity: number }>;
  included_in: string[];
  /** Where `includes` came from: this outlet's own set or the global default. */
  components_source: 'outlet' | 'global' | 'none';
  is_available: boolean;
  sort_order: number;
  notes: string | null;
  points_estimate: number;
}

export interface ChecklistStep {
  key: string;
  title: string;
  type: StepType;
  required?: boolean;
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
}

export interface Booking {
  id: string;
  ref: string;
  customer_id: string;
  vehicle_id: string;
  outlet_id: string;
  service_id: string;
  quotation_id: string | null;
  slot_start: string;
  slot_end: string;
  status: BookingStatus;
  price_cents: number;
  discount_cents: number;
  total_cents: number;
  discount_label: string | null;
  points_pending: number;
  notes: string | null;
  cancel_reason: string | null;
  client_op_id: string | null;
  created_by: string | null;
  /** Staff-created counter booking (migration 0005); starts `confirmed`. */
  walk_in: boolean;
  /** Customer's chosen payment method at booking time; `cash` = pay at the counter on collection. */
  payment_method: 'card' | 'eft' | 'cash' | null;
  /** Pricing basis at booking time (migration 0008). */
  vehicle_size: VehicleSize | null;
  pricing_mode: PricingMode | null;
  vat_mode: VatMode | null;
  addon_service_ids: string[];
  addons_cents: number;
  /** Membership benefit applied at booking time (migration 0010). */
  membership_id: string | null;
  entitlement_id: string | null;
  membership_benefit: MembershipBenefitKind | null;
  created_at: string;
  updated_at: string;
}

export interface WorkOrder {
  id: string;
  ref: string;
  outlet_id: string;
  booking_id: string | null;
  quotation_id: string | null;
  vehicle_id: string;
  customer_id: string;
  service_id: string;
  status: WorkStatus;
  priority: number;
  bay: string | null;
  checklist_template_id: string | null;
  template_version: number | null;
  assignee_id: string | null;
  eta_at: string | null;
  /** Car confirmed on site (booking check-in, or POST /work-orders/:id/checkin). Assignment requires it. */
  checked_in_at: string | null;
  checked_in_by: string | null;
  started_at: string | null;
  blocked_reason: string | null;
  completed_at: string | null;
  verified_at: string | null;
  verified_by: string | null;
  due_at: string | null;
  /** Vehicle-collection OTP (migration 0004): issued on verify, shown to the owning customer only. */
  pickup_otp: string | null;
  pickup_otp_issued_at: string | null;
  pickup_otp_verified_at: string | null;
  pickup_otp_verified_by: string | null;
  collected_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Notification {
  id: string;
  recipient_id: string;
  channel: NotifyChannel;
  template_key: string;
  title: string | null;
  body: string;
  payload: Record<string, unknown> & { vars?: Record<string, unknown> };
  status: NotifyStatus;
  dedupe_key: string | null;
  provider_ref: string | null;
  provider_status: string | null;
  provider_error_code: string | null;
  error: string | null;
  attempts: number;
  sent_at: string | null;
  delivered_at: string | null;
  read_by_recipient_at: string | null;
  read_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Task {
  id: string;
  work_order_id: string;
  outlet_id: string;
  title: string;
  seq: number;
  assignee_id: string | null;
  status: WorkStatus;
  priority: number;
  blocked_reason: string | null;
  due_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  elapsed_seconds: number;
  client_op_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface StepResult {
  id: string;
  work_order_id: string;
  step_key: string;
  status: StepStatus;
  value: unknown;
  attachment_id: string | null;
  actor_id: string | null;
  note: string | null;
  client_op_id: string | null;
  completed_at: string | null;
  updated_at: string;
}

export interface Payment {
  id: string;
  booking_id: string | null;
  quotation_id: string | null;
  customer_id: string;
  provider: string;
  provider_ref: string | null;
  method_id: string | null;
  amount_cents: number;
  currency: string;
  status: PaymentStatus;
  receipt_no: string | null;
  idempotency_key: string;
  failure_reason: string | null;
  verified_at: string | null;
  /** POS attestation (migration 0005): how it was paid and which staff member recorded it. */
  method: PosPaymentMethod | null;
  recorded_by: string | null;
  /** Membership invoice this payment settles (migration 0010); `booking_id` stays null. */
  membership_invoice_id?: string | null;
  created_at: string;
  updated_at: string;
}

export interface LoyaltyTierConfig {
  tier: LoyaltyTier;
  name: string;
  min_points: number;
  max_points: number | null;
  earn_multiplier: number;
  discount_pct: number;
}

export interface LoyaltyRules {
  points_per_rand: number;
  award_on?: string;
  idempotent_award?: boolean;
  expiry_months?: number;
  birthday_bonus?: { enabled: boolean; points: number; reason?: string };
  referral_bonus?: { enabled: boolean; points: number };
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

// ---------------------------------------------------------------------------
// Membership plans (migration 0010, docs/MEMBERSHIPS.md)
// ---------------------------------------------------------------------------

export type MembershipStatus = 'pending' | 'active' | 'past_due' | 'cancelled' | 'expired';
export type MembershipDiscountScope = 'plan_services' | 'other_services' | 'all_services' | 'none';
export type MembershipGroupSelection = 'choose_one' | 'all';
export type MembershipPeriod = 'month' | 'year';
export type MembershipPaymentMethod = 'card' | 'cash' | 'eft' | 'sandbox';
export type MembershipInvoiceStatus = 'pending' | 'paid' | 'failed' | 'void';
export type MembershipBenefitKind = 'included' | 'discount';

export const MEMBERSHIP_LIVE_STATUSES: MembershipStatus[] = ['pending', 'active', 'past_due'];

export interface MembershipEntitlementService {
  id: string;
  code: string;
  name: string;
  is_primary: boolean;
}

export interface MembershipEntitlement {
  id: string;
  group_id: string;
  code: string;
  label: string;
  quantity: number;
  period: MembershipPeriod;
  sort_order: number;
  services: MembershipEntitlementService[];
}

export interface MembershipGroup {
  id: string;
  plan_id: string;
  code: string;
  name: string;
  selection: MembershipGroupSelection;
  sort_order: number;
  entitlements: MembershipEntitlement[];
}

export interface MembershipPlan {
  id: string;
  code: string;
  tier: LoyaltyTier;
  name: string;
  tagline: string | null;
  monthly_fee_cents: number;
  discount_pct: number;
  discount_scope: MembershipDiscountScope;
  discount_note: string | null;
  color: string | null;
  sort_order: number;
  is_active: boolean;
  groups: MembershipGroup[];
}

export interface Membership {
  id: string;
  ref: string;
  customer_id: string;
  plan_id: string;
  status: MembershipStatus;
  started_at: string | null;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  cancelled_at: string | null;
  ended_at: string | null;
  next_plan_id: string | null;
  payment_method: MembershipPaymentMethod;
  client_op_id: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
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
  idempotency_key: string;
  created_at: string;
  updated_at: string;
}

/** Append-only consumption ledger row (+1 redeem, −1 release). */
export interface MembershipUsage {
  id: string;
  membership_id: string;
  entitlement_id: string;
  booking_id: string | null;
  quantity: number;
  period_start: string;
  period_end: string;
  idempotency_key: string;
  created_by: string | null;
  created_at: string;
}

/** Remaining allowance of one entitlement in its current period. */
export interface Allowance {
  entitlement_id: string;
  entitlement_code: string;
  group_code: string;
  label: string;
  quantity: number;
  used: number;
  remaining: number;
  period: MembershipPeriod;
  period_start: string;
  period_end: string;
}

/** Short summary for `/me`, `/loyalty/account` and staff/admin customer views. */
export interface MembershipBrief {
  membership_id: string;
  plan_code: string;
  plan_name: string;
  tier: LoyaltyTier;
  status: MembershipStatus;
  period_end: string | null;
  cancel_at_period_end: boolean;
  allowances: Allowance[];
}

/** `GET /memberships/me` */
export interface MembershipSummary {
  membership: Membership | null;
  plan: MembershipPlan | null;
  next_plan: Pick<MembershipPlan, 'id' | 'code' | 'name' | 'monthly_fee_cents'> | null;
  selections: Record<string, string>;
  allowances: Allowance[];
  open_invoice: MembershipInvoice | null;
  invoices: MembershipInvoice[];
  next_renewal_at: string | null;
  benefits_summary: string;
}

export type QuotationDecisionSource = 'app' | 'public_link' | 'staff';
export type AttachmentKind = 'damage_photo' | 'document';

/** One attention area (dent, scratch, bumper…) optionally tied to an auto-body service. */
export interface QuotationLineItem {
  label: string;
  description?: string | null;
  category?: string | null;
  service_id?: string | null;
  amount_cents: number;
  quantity?: number | null;
  /** Set when a membership entitlement covers this line (recorded at R0). */
  membership_benefit?: MembershipBenefitKind | null;
  entitlement_id?: string | null;
}

export interface Quotation {
  id: string;
  ref: string;
  customer_id: string;
  vehicle_id: string;
  outlet_id: string;
  category: string;
  description: string;
  status: QuotationStatus;
  amount_cents: number | null;
  line_items: QuotationLineItem[];
  assessor_id: string | null;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_by: string | null;
  decision_note: string | null;
  client_op_id: string | null;
  /** Public quote page (migration 0006): link token + provenance of the decision. */
  items_note: string | null;
  public_token: string | null;
  public_token_expires_at: string | null;
  decision_source: QuotationDecisionSource | null;
  decision_by_name: string | null;
  pdf_generated_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Attachment {
  id: string;
  entity_type: string;
  entity_id: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  sha256: string | null;
  uploaded_by: string | null;
  kind: AttachmentKind;
  width: number | null;
  height: number | null;
  caption: string | null;
  created_at: string;
}

export interface Vehicle {
  id: string;
  customer_id: string;
  registration_no: string;
  vin: string | null;
  engine_no: string | null;
  make: string | null;
  model: string | null;
  colour: string | null;
  year: number | null;
  licence_no: string | null;
  disc_expiry: string | null;
  source: 'manual' | 'scan';
  disc_verified: boolean;
  disc_hash: string | null;
  /** Pricing size class (migration 0008); null = unknown → priced as `small`. */
  size_class: VehicleSize | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface InventoryItem {
  id: string;
  outlet_id: string;
  sku: string;
  name: string;
  unit: string;
  on_hand: number;
  reorder_threshold: number;
  pack_size: number | null;
  is_active: boolean;
  updated_at: string;
}

/** Per-request authenticated principal (populated by the auth middleware). */
export interface AuthContext {
  uid: string;
  email: string | null;
  role: UserRole;
  outletIds: string[];
  profile: Profile | null;
  tokenClaims: Record<string, unknown>;
}

/** Context passed to services (auth + request metadata). */
export interface RequestContext {
  auth: AuthContext;
  correlationId: string;
  log: Logger;
  ip?: string;
  userAgent?: string;
}

declare module 'express-serve-static-core' {
  interface Request {
    correlationId: string;
    log: Logger;
    auth?: AuthContext;
    ctx: RequestContext;
  }
}
