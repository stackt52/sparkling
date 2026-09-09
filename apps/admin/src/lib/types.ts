/**
 * Domain types mirroring backend/supabase/migrations/0001_schema.sql and the
 * admin routes in docs/API.md. All money is integer cents (ZAR), timestamps ISO-8601.
 */

export type UserRole = 'customer' | 'technician' | 'supervisor' | 'manager' | 'admin' | 'finance';
export const ADMIN_ROLES: UserRole[] = ['manager', 'admin', 'finance', 'supervisor'];

export type ServiceCategory = 'car_wash' | 'auto_body';
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
export type LoyaltyTier = 'silver' | 'gold' | 'platinum';
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
    | 'internal'
    | 'network';
  message: string;
  details?: unknown[];
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
}

export interface SessionResponse {
  profile: Profile & { outlet_ids: string[] };
  claims_updated: boolean;
}

export interface StaffUser extends Profile {
  outlet_ids: string[];
  outlet_names: string[];
  skills: string[];
  availability?: 'available' | 'busy' | 'break' | 'off';
}

/* ---------- catalogue ---------- */
export type OpeningHours = Record<'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun', [string, string] | null>;

export interface Outlet {
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
  icon: string;
  checklist_template_id: string | null;
  is_active: boolean;
  sort_order: number;
}

export interface OutletService {
  outlet_id: string;
  service_id: string;
  price_cents: number | null;
  is_available: boolean;
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
}

export interface LoyaltyAccount {
  customer_id: string;
  tier: LoyaltyTier;
  balance_points: number;
  lifetime_points: number;
  tier_since: string;
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
  loyalty?: LoyaltyAccount;
}

export interface CustomerDetail extends CustomerSummary {
  vehicles: Vehicle[];
  bookings: Booking[];
  ledger: LedgerEntry[];
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
  payment: { id: string; status: PaymentStatus; receipt_no: string | null; amount_cents: number } | null;
  quotation_id: string | null;
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

export interface QuoteLineItem {
  label: string;
  amount_cents: number;
}

export interface Quotation {
  id: string;
  ref: string;
  customer_id: string;
  customer_name: string;
  vehicle: { id: string; registration_no: string; make: string | null; model: string | null };
  outlet: { id: string; name: string };
  category: string;
  description: string;
  status: QuotationStatus;
  amount_cents: number | null;
  line_items: QuoteLineItem[];
  assessor_id: string | null;
  assessor_name: string | null;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_note: string | null;
  attachments: { id: string; storage_path: string; mime_type: string }[];
  created_at: string;
  work_order_ref?: string | null;
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
  task_id: string;
  events: TaskEvent[];
  updated_at: string;
}

/* ---------- payments ---------- */
export interface Payment {
  id: string;
  booking_ref: string | null;
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
}

export type ReportKind = 'bookings' | 'payments' | 'inventory' | 'staff_performance' | 'loyalty';

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
