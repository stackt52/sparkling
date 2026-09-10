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
export type LoyaltyTier = 'silver' | 'gold' | 'platinum';
export type LedgerType = 'earn' | 'redeem' | 'adjust' | 'expire' | 'bonus';
export type InventoryReason = 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count';
export type NotifyChannel = 'push' | 'whatsapp' | 'sms' | 'email';
export type NotifyStatus = 'queued' | 'sent' | 'delivered' | 'failed' | 'suppressed';
export type ConfigStatus = 'draft' | 'published' | 'archived';
export type SyncStatus = 'pending' | 'applied' | 'conflict' | 'rejected';

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
  line_items: Array<{ label: string; amount_cents: number }>;
  assessor_id: string | null;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_by: string | null;
  decision_note: string | null;
  client_op_id: string | null;
  created_at: string;
  updated_at: string;
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
