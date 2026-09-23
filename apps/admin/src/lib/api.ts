/**
 * Typed client for the admin-relevant routes in docs/API.md.
 * `HttpApi` talks to the Cloud Functions REST API; `DemoApi` (lib/demo) is an
 * in-memory implementation of the same interface used when NEXT_PUBLIC_DEMO_MODE=true.
 */
import { env } from './env';
import type {
  ActivityItem,
  ApiError,
  AuditEvent,
  AvailabilitySlot,
  Booking,
  BookingCheckinResult,
  BookingDetail,
  BookingStatus,
  ChecklistTemplate,
  CreateStaffInput,
  CreateStaffResult,
  CustomerDetail,
  CustomerSummary,
  EnrolMembershipInput,
  ExceptionItem,
  FeatureFlag,
  IntegrationStatus,
  InventoryItem,
  Kpis,
  LoyaltyConfig,
  LoyaltyConfigResponse,
  LoyaltyRules,
  LoyaltyTierConfig,
  Membership,
  MembershipPlan,
  MembershipPlanInput,
  MembershipRow,
  MembershipStatus,
  MembershipSummary,
  NotificationRow,
  NotifyChannel,
  NotifyStatus,
  Outlet,
  OutletServiceInput,
  OutletServiceOffer,
  Page,
  Payment,
  Period,
  PickupResendResult,
  PickupVerifyResult,
  PosPayment,
  Profile,
  QuoteLineItem,
  Quotation,
  QuotationAttachment,
  QuotationStatus,
  RaiseQuotationInput,
  RecordMembershipPaymentResult,
  RecordPaymentInput,
  RenewalRunResult,
  ReportKind,
  ReportSummary,
  ResetPasswordResult,
  Service,
  ServiceInput,
  SessionResponse,
  ShareQuotationResult,
  StaffPerformanceRow,
  StaffUser,
  Task,
  UserRole,
  Vehicle,
  VehicleInput,
  VehicleSize,
  WalkInBookingInput,
  WalkInBookingResult,
  WalkInCustomer,
  WalkInCustomerInput,
  WalkInPriority,
  WorkOrder,
  WorkOrderSummary,
  WorkStatus,
} from './types';

export class ApiRequestError extends Error {
  readonly error: ApiError;
  readonly status: number;
  constructor(status: number, error: ApiError) {
    super(error.message);
    this.name = 'ApiRequestError';
    this.status = status;
    this.error = error;
  }
}

/** Reads a keyed value out of a 409 `conflict` payload (`details.existing_customer`, `details.existing_vehicle_id`, …). */
export function conflictDetail<T>(e: unknown, key: string): T | undefined {
  if (!(e instanceof ApiRequestError) || e.status !== 409) return undefined;
  const d = e.error.details;
  if (Array.isArray(d)) {
    const hit = d.find((x) => x && typeof x === 'object' && key in (x as object)) as Record<string, T> | undefined;
    return hit?.[key];
  }
  if (d && typeof d === 'object' && key in d) return (d as Record<string, T>)[key];
  return undefined;
}

export interface OutletScoped {
  outlet_id?: string | null;
}
export interface BookingFilters extends OutletScoped {
  date?: string;
  status?: BookingStatus | 'all';
  search?: string;
  limit?: number;
  cursor?: string | null;
}
export interface QuotationFilters extends OutletScoped {
  status?: QuotationStatus | 'all';
  /** Page size (`GET /quotations` defaults to 25; the grid asks for 200). */
  limit?: number;
}
export interface WorkOrderFilters extends OutletScoped {
  status?: WorkStatus | 'all';
}
export interface AuditFilters {
  entity_type?: string;
  action?: string;
  /** Actor profile id (`actor_id` on the wire). */
  actor?: string;
  limit?: number;
  cursor?: string | null;
}
export interface ReportFilters extends OutletScoped {
  from: string;
  to: string;
}
export interface NotificationFilters {
  status?: NotifyStatus | 'all';
  channel?: NotifyChannel | 'all';
  limit?: number;
  cursor?: string | null;
}
export interface MembershipFilters {
  status?: MembershipStatus | 'all';
  plan_code?: string;
  q?: string;
  limit?: number;
  cursor?: string | null;
}
export interface TeamMember {
  id: string;
  name: string;
  role: UserRole;
  availability: 'available' | 'busy' | 'break' | 'off';
  skills: string[];
  active_tasks: number;
  capacity: number;
}

export type LiveEvent = { table: string; at: string };

export interface OutletOfferFilters {
  /** Adds `price_cents` resolved for this size. */
  vehicleSize?: VehicleSize;
  /** Admin: include unavailable (switched-off) bindings. */
  includeUnavailable?: boolean;
}

export interface AdminApi {
  readonly mode: 'http' | 'demo';
  /* auth */
  session(body: { app: 'admin'; full_name?: string }): Promise<SessionResponse>;
  /* ops */
  kpis(params: OutletScoped & { period: Period }): Promise<Kpis>;
  exceptions(params: OutletScoped): Promise<ExceptionItem[]>;
  activity(params: OutletScoped & { limit?: number }): Promise<ActivityItem[]>;
  /* bookings */
  listBookings(filters: BookingFilters): Promise<Page<Booking>>;
  getBooking(id: string): Promise<BookingDetail>;
  cancelBooking(id: string, reason: string): Promise<Booking>;
  /**
   * Explicit "car checked in" for a `pending` / `confirmed` booking (`POST /bookings/:id/checkin { bay?, priority? }`):
   * stamps `checked_in_at` on the work order the booking already has (created when it was confirmed; `created:false`),
   * moves the booking to `in_service` and auto-assigns it when the `auto_assignment` flag is on.
   */
  checkinBooking(id: string, body: { bay?: string | null; priority?: WalkInPriority }): Promise<BookingCheckinResult>;
  /* quotations */
  listQuotations(filters: QuotationFilters): Promise<Quotation[]>;
  getQuotation(id: string): Promise<Quotation>;
  submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string; items_note?: string | null }): Promise<Quotation>;
  /**
   * "Check in & start" for an accepted quotation (`POST /quotations/:id/convert`): the work order already exists since
   * acceptance, so this confirms the car on site (same effect as `checkinWorkOrder`) and marks the quotation `converted`.
   */
  convertQuotation(id: string): Promise<Quotation>;
  /** Staff-raised quote (`POST /quotations`, staff shape) → status `quoted` with a fresh public link. */
  raiseQuotation(input: RaiseQuotationInput): Promise<Quotation>;
  /** Rotates / creates the public token and re-sends the `quote_ready` WhatsApp + push (1/min). */
  shareQuotation(id: string): Promise<ShareQuotationResult>;
  /** `multipart/form-data` upload of one damage photo (jpeg/png/heic ≤ 10 MB, ≤ 10 per quote). */
  uploadQuotationPhoto(id: string, file: File, caption?: string): Promise<QuotationAttachment>;
  deleteQuotationPhoto(id: string, attachmentId: string): Promise<void>;
  /** Signed-in image fetch (bearer token) — callers turn the Blob into an object URL. */
  fetchQuotationPhoto(id: string, attachmentId: string): Promise<Blob>;
  /** Signed-in PDF fetch (`GET /quotations/:id/pdf`). */
  fetchQuotationPdf(id: string): Promise<Blob>;
  /* work orders */
  listWorkOrders(filters: WorkOrderFilters): Promise<WorkOrder[]>;
  getWorkOrder(id: string): Promise<WorkOrder>;
  /** Refused with 409 `validation_error` `{ reason: 'not_checked_in', work_order_id }` while `checked_in_at` is null. */
  assignTask(taskId: string, body: { assignee_id: string; reason?: string }): Promise<WorkOrder>;
  transitionTask(taskId: string, body: { to: WorkStatus; reason?: string }): Promise<WorkOrder>;
  /**
   * Confirms the car is on site (`POST /work-orders/:id/checkin { bay? }`): records `checked_in_at` / `checked_in_by`
   * and runs auto-assignment when the flag is on and the work order is unassigned. Idempotent (200 `already: true`).
   */
  checkinWorkOrder(id: string, body: { bay?: string | null }): Promise<WorkOrder>;
  /**
   * Vehicle hand-over (`POST /work-orders/:id/pickup/verify { otp }`): the customer presents the 5-digit collection OTP
   * issued when the work order was verified. 409 `invalid_otp` `{ attempts_remaining, locked }` on a wrong code (5
   * attempts, then locked), 409 `conflict` once collected (`details.collected_at`) or before an OTP was issued, and 409
   * `validation_error` `{ reason: 'payment_due', amount_cents, booking_id, method: 'cash' }` while a cash-on-collection
   * booking is unpaid (record the payment first).
   */
  verifyPickup(id: string, otp: string): Promise<PickupVerifyResult>;
  /** Re-sends the same collection OTP (push + WhatsApp); 429 `rate_limited` within a minute of the last send, 409 once collected. */
  resendPickupOtp(id: string): Promise<PickupResendResult>;
  team(params: OutletScoped): Promise<TeamMember[]>;
  /* users */
  listUsers(): Promise<StaffUser[]>;
  /** `POST /admin/users` — creates the Firebase user with a temporary password (ADM-010). */
  inviteUser(body: CreateStaffInput): Promise<CreateStaffResult>;
  updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; skills?: string[]; is_active?: boolean; phone?: string | null }): Promise<StaffUser>;
  /** `POST /admin/users/:id/reset-password` — new temporary password, refresh tokens revoked, `must_change_password` re-flagged. */
  resetUserPassword(id: string): Promise<ResetPasswordResult>;
  /** `POST /auth/password-changed` — clears `must_change_password` after the client set a new password (fresh `auth_time` required). */
  confirmPasswordChanged(): Promise<Profile>;
  staffPerformance(params: OutletScoped & { period: Period }): Promise<StaffPerformanceRow[]>;
  /* customers */
  searchCustomers(search: string): Promise<CustomerSummary[]>;
  getCustomer(id: string): Promise<CustomerDetail>;
  /* walk-in (staff on behalf of a customer; STF-010/012) */
  searchWalkInCustomers(search: string): Promise<WalkInCustomer[]>;
  createWalkInCustomer(input: WalkInCustomerInput): Promise<WalkInCustomer>;
  createCustomerVehicle(customerId: string, input: VehicleInput, force?: boolean): Promise<{ vehicle: Vehicle; duplicate: boolean }>;
  /** `GET /outlets/:id/services` — available offers with resolved prices (customer / walk-in view). */
  listOutletServicesFor(outletId: string, vehicleSize?: VehicleSize): Promise<OutletServiceOffer[]>;
  availability(outletId: string, serviceId: string, dateISO: string): Promise<AvailabilitySlot[]>;
  createWalkInBooking(input: WalkInBookingInput): Promise<WalkInBookingResult>;
  /**
   * Counter payment attestation (`POST /payments/record`, staff / manager / admin) for a booking (`booking_id`) or an
   * accepted quotation (`quotation_id`). The idempotency key is generated client-side (`pos-<uuid>`) unless given.
   */
  recordPayment(input: RecordPaymentInput): Promise<PosPayment>;
  /* catalogue */
  listOutlets(): Promise<Outlet[]>;
  createOutlet(body: Partial<Outlet>): Promise<Outlet>;
  updateOutlet(id: string, patch: Partial<Outlet>): Promise<Outlet>;
  /** `GET /admin/services` — canonical catalogue with global `components`. */
  listServices(): Promise<Service[]>;
  createService(body: ServiceInput): Promise<Service>;
  updateService(id: string, patch: ServiceInput): Promise<Service>;
  /** `GET /admin/outlets/:id/services` — the outlet's offers with resolved composition (admin matrix). */
  listOutletOffers(outletId: string, filters?: OutletOfferFilters): Promise<OutletServiceOffer[]>;
  /** `PUT /admin/outlets/:id/services/:serviceId` — bind / update an outlet offer (`components: null` = use global). */
  upsertOutletService(outletId: string, serviceId: string, body: OutletServiceInput): Promise<OutletServiceOffer>;
  /** `DELETE /admin/outlets/:id/services/:serviceId` — unbind. */
  removeOutletService(outletId: string, serviceId: string): Promise<void>;
  /* templates */
  listTemplates(): Promise<ChecklistTemplate[]>;
  createTemplate(body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'>): Promise<ChecklistTemplate>;
  updateTemplate(id: string, body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'> & { publish: boolean }): Promise<ChecklistTemplate>;
  /* loyalty */
  loyaltyConfig(): Promise<LoyaltyConfigResponse>;
  saveLoyaltyDraft(body: { tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string }): Promise<LoyaltyConfig>;
  publishLoyalty(): Promise<LoyaltyConfig>;
  discardLoyalty(): Promise<void>;
  /* memberships (docs/MEMBERSHIPS.md; managerPlus) */
  /** `GET /admin/memberships/plans` — plans with `member_count` / `mrr_cents`. */
  membershipPlans(): Promise<MembershipPlan[]>;
  /** `PUT /admin/memberships/plans/:code` — full replace of groups / entitlements by code. */
  saveMembershipPlan(code: string, body: MembershipPlanInput): Promise<MembershipPlan>;
  /** `GET /admin/memberships?status&plan_code&q&limit&cursor`. */
  listMemberships(params: MembershipFilters): Promise<Page<MembershipRow>>;
  /** `GET /staff/customers/:id/membership` — same shape as `/memberships/me` for that customer. */
  customerMembership(customerId: string): Promise<MembershipSummary>;
  /** `POST /admin/customers/:id/membership` — enrol at the counter (active immediately, invoice paid). */
  enrolMembership(customerId: string, body: EnrolMembershipInput): Promise<MembershipSummary>;
  /** `POST /admin/memberships/:id/cancel` — `at_period_end` (default) or immediate. */
  cancelMembership(id: string, body: { at_period_end: boolean; reason?: string }): Promise<MembershipSummary>;
  /** `POST /admin/memberships/:id/invoices/:invoiceId/record-payment` — pays a pending renewal (rolls the period). */
  recordMembershipPayment(id: string, invoiceId: string, body: { method: 'cash' | 'card_terminal' | 'eft'; client_op_id: string }): Promise<RecordMembershipPaymentResult>;
  /** `POST /admin/memberships/run-renewals` — the daily job, on demand. */
  runMembershipRenewals(): Promise<RenewalRunResult>;
  /* inventory */
  listInventory(params: OutletScoped & { alerts_first?: boolean }): Promise<InventoryItem[]>;
  updateInventoryItem(id: string, patch: { reorder_threshold?: number; name?: string; unit?: string }): Promise<InventoryItem>;
  addMovement(id: string, body: { delta: number; reason: 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count'; note?: string }): Promise<InventoryItem>;
  /* payments, reports, audit, flags */
  listPayments(params: OutletScoped): Promise<Payment[]>;
  reportSummary(filters: ReportFilters): Promise<ReportSummary>;
  exportCsv(report: ReportKind, filters: Record<string, string | undefined>): Promise<string>;
  listAudit(filters: AuditFilters): Promise<Page<AuditEvent>>;
  listFlags(): Promise<FeatureFlag[]>;
  updateFlag(key: string, enabled: boolean): Promise<FeatureFlag>;
  integrations(): Promise<IntegrationStatus[]>;
  /* notifications (manager/admin; finance read-only) */
  listNotifications(filters: NotificationFilters): Promise<Page<NotificationRow>>;
  resendNotification(id: string): Promise<NotificationRow>;
  /** Live updates: demo emits synthetic ticks; http resolves to a no-op (Supabase realtime handles it). */
  subscribe(listener: (e: LiveEvent) => void): () => void;
}

/* ------------------------------------------------------------------ */
/* HTTP implementation                                                 */
/* ------------------------------------------------------------------ */

type TokenGetter = () => Promise<string | null>;

export function uuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

function qs(params: object): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params as Record<string, unknown>)) {
    if (v === undefined || v === null || v === '' || v === 'all') continue;
    sp.set(k, String(v));
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
}

/** Turns a non-2xx response into an `ApiRequestError` carrying the API error envelope. */
async function throwFromResponse(res: Response): Promise<never> {
  let err: ApiError = { code: 'internal', message: `HTTP ${res.status}` };
  try {
    const json = (await res.json()) as { error?: ApiError };
    if (json.error) err = json.error;
  } catch {
    /* non-JSON error body */
  }
  throw new ApiRequestError(res.status, err);
}

/**
 * Absolute URL for an API-relative path returned by the server (`/v1/...`).
 * Already-absolute URLs and same-origin assets (demo `/demo/...`) are returned unchanged.
 */
export function resolveApiUrl(path: string | null | undefined): string {
  if (!path) return '';
  if (/^(https?:)?\/\//.test(path) || path.startsWith('blob:') || path.startsWith('data:')) return path;
  if (path.startsWith('/v1/')) return `${env.apiBaseUrl}${path}`;
  return path;
}

/**
 * Unauthenticated request against `NEXT_PUBLIC_API_BASE_URL` for the token-scoped public
 * endpoints (`/v1/public/...`). No Firebase token, no auth provider — safe to call from the
 * standalone `/q/[token]` page. `path` is relative to `/v1`.
 */
export async function publicFetch<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'X-Client-App': 'public-web',
    'X-Client-Version': env.clientVersion,
    'X-Correlation-Id': uuid(),
  };
  if (method !== 'GET') {
    headers['Idempotency-Key'] = uuid();
    headers['Content-Type'] = 'application/json';
  }
  let res: Response;
  try {
    res = await fetch(`${env.apiBaseUrl}/v1${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch (e) {
    throw new ApiRequestError(0, { code: 'network', message: (e as Error).message });
  }
  if (!res.ok) await throwFromResponse(res);
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/** `GET /admin/customers/:id` envelope → the flat `CustomerDetail` the drawer renders. */
interface CustomerEnvelope {
  customer: Profile;
  vehicle_count: number;
  booking_count: number;
  loyalty: CustomerSummary['loyalty'] | null;
  vehicles: Vehicle[];
  bookings: Booking[];
  ledger: CustomerDetail['ledger'];
  membership: MembershipSummary | null;
}

/** `GET /admin/memberships` row (`{ membership, customer, plan, … }`) → the flat grid row. */
interface MemberRowEnvelope extends Omit<MembershipRow, keyof Membership | 'customer'> {
  membership: Membership;
  customer: MembershipRow['customer'] | null;
}
function flattenMemberRow(r: MemberRowEnvelope): MembershipRow {
  const { membership, customer, ...rest } = r;
  return { ...membership, ...rest, customer: customer ?? { id: membership.customer_id, full_name: 'Unknown customer', email: null, phone: null } };
}

/** `POST /admin/memberships/run-renewals` → the four counters the toast shows. */
interface RenewalRunEnvelope { expired: number; invoices_created: number; past_due: number; rolled: number }

/** Form values arrive as '' for "not set"; the API wants null. Read-only columns are dropped. */
function outletBody(o: Partial<Outlet>): Record<string, unknown> {
  const readOnly = new Set(['id', 'created_at', 'updated_at']);
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(o)) if (!readOnly.has(k)) out[k] = typeof v === 'string' && v.trim() === '' ? null : v;
  if (o.bank_details) out.bank_details = Object.fromEntries(Object.entries(o.bank_details).map(([k, v]) => [k, typeof v === 'string' && v.trim() === '' ? null : v]));
  return out;
}

export class HttpApi implements AdminApi {
  readonly mode = 'http' as const;
  constructor(private readonly getToken: TokenGetter, private readonly baseUrl = env.apiBaseUrl) {}

  /** GET a collection. The API wraps collections as `{ data: [...] }`; bare arrays are accepted too. */
  private async list<T>(path: string): Promise<T[]> {
    const res = await this.request<T[] | { data: T[] }>('GET', path);
    return Array.isArray(res) ? res : (res?.data ?? []);
  }

  private async request<T>(method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE', path: string, body?: unknown, raw = false): Promise<T> {
    const headers: Record<string, string> = {
      Accept: raw ? 'text/csv' : 'application/json',
      'X-Client-App': 'admin',
      'X-Client-Version': env.clientVersion,
      'X-Correlation-Id': uuid(),
    };
    const token = await this.getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
    if (method !== 'GET') {
      headers['Idempotency-Key'] = uuid();
      headers['Content-Type'] = 'application/json';
    }
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}/v1${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (e) {
      throw new ApiRequestError(0, { code: 'network', message: (e as Error).message });
    }
    if (!res.ok) await throwFromResponse(res);
    if (raw) return (await res.text()) as unknown as T;
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  /** Authenticated binary GET (images, PDFs) — returns the response body as a Blob. */
  private async blob(path: string, accept: string): Promise<Blob> {
    const headers: Record<string, string> = { Accept: accept, 'X-Client-App': 'admin', 'X-Client-Version': env.clientVersion, 'X-Correlation-Id': uuid() };
    const token = await this.getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}/v1${path}`, { headers });
    } catch (e) {
      throw new ApiRequestError(0, { code: 'network', message: (e as Error).message });
    }
    if (!res.ok) await throwFromResponse(res);
    return res.blob();
  }

  /** Authenticated `multipart/form-data` POST (the browser sets the boundary). */
  private async upload<T>(path: string, form: FormData): Promise<T> {
    const headers: Record<string, string> = { Accept: 'application/json', 'X-Client-App': 'admin', 'X-Client-Version': env.clientVersion, 'X-Correlation-Id': uuid(), 'Idempotency-Key': uuid() };
    const token = await this.getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}/v1${path}`, { method: 'POST', headers, body: form });
    } catch (e) {
      throw new ApiRequestError(0, { code: 'network', message: (e as Error).message });
    }
    if (!res.ok) await throwFromResponse(res);
    return (await res.json()) as T;
  }

  session(body: { app: 'admin'; full_name?: string }) {
    return this.request<SessionResponse>('POST', '/auth/session', body);
  }
  /** `GET /admin/kpis?period=` — the API derives the calendar range; a null trend (no previous revenue) reads as 0 %. */
  async kpis(p: OutletScoped & { period: Period }) {
    const k = await this.request<Kpis & { revenue_trend_pct: number | null }>('GET', `/admin/kpis${qs(p)}`);
    return { ...k, revenue_trend_pct: k.revenue_trend_pct ?? 0 };
  }
  exceptions(p: OutletScoped) {
    return this.list<ExceptionItem>(`/admin/exceptions${qs(p)}`);
  }
  activity(p: OutletScoped & { limit?: number }) {
    return this.list<ActivityItem>(`/admin/activity${qs(p)}`);
  }
  listBookings(f: BookingFilters) {
    return this.request<Page<Booking>>('GET', `/admin/bookings${qs(f)}`);
  }
  getBooking(id: string) {
    return this.request<BookingDetail>('GET', `/bookings/${id}`);
  }
  async cancelBooking(id: string, reason: string) {
    return (await this.request<{ booking: Booking }>('POST', `/bookings/${id}/cancel`, { reason })).booking;
  }
  /** `POST /bookings/:id/checkin` → `{ booking, work_order, task, created }`; the bare `work_orders` row is mapped onto the summary shape. */
  async checkinBooking(id: string, body: { bay?: string | null; priority?: WalkInPriority }) {
    const res = await this.request<{ booking: Booking; work_order: (Partial<WorkOrderSummary> & { id: string; ref: string; status: WorkStatus }) | null; created?: boolean }>('POST', `/bookings/${id}/checkin`, body);
    const w = res.work_order;
    const work_order: WorkOrderSummary | null = w
      ? { id: w.id, ref: w.ref, status: w.status, stage: w.stage ?? 0, stage_count: w.stage_count ?? 0, progress_pct: w.progress_pct ?? 0, assignee_id: w.assignee_id ?? null, assignee_name: w.assignee_name ?? null, bay: w.bay ?? body.bay ?? null, eta_at: w.eta_at ?? null, blocked_reason: w.blocked_reason ?? null, checked_in_at: w.checked_in_at ?? new Date().toISOString() }
      : null;
    return { booking: res.booking, work_order, created: res.created ?? false };
  }
  listQuotations(f: QuotationFilters) {
    return this.list<Quotation>(`/quotations${qs({ limit: 200, ...f })}`);
  }
  getQuotation(id: string) {
    return this.request<Quotation>('GET', `/quotations/${id}`);
  }
  async submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string; items_note?: string | null }) {
    return (await this.request<{ quotation: Quotation }>('POST', `/quotations/${id}/quote`, body)).quotation;
  }
  /** `POST /quotations/:id/convert` → `{ quotation, work_order, task }`; the quotation carries `work_order` / `work_order_ref`. */
  async convertQuotation(id: string) {
    const res = await this.request<{ quotation: Quotation; work_order: { id: string; ref: string; status: WorkStatus; checked_in_at?: string | null } | null }>('POST', `/quotations/${id}/convert`, {});
    const wo = res.quotation.work_order ?? (res.work_order ? { id: res.work_order.id, ref: res.work_order.ref, status: res.work_order.status, checked_in_at: res.work_order.checked_in_at ?? null } : null);
    return { ...res.quotation, work_order: wo, work_order_ref: res.quotation.work_order_ref ?? wo?.ref ?? null };
  }
  async raiseQuotation(input: RaiseQuotationInput) {
    const res = await this.request<{ quotation: Quotation } | Quotation>('POST', '/quotations', input);
    return 'quotation' in res ? res.quotation : res;
  }
  shareQuotation(id: string) {
    return this.request<ShareQuotationResult>('POST', `/quotations/${id}/share`, {});
  }
  async uploadQuotationPhoto(id: string, file: File, caption?: string) {
    const form = new FormData();
    form.append('photo', file, file.name);
    if (caption) form.append('caption', caption);
    return (await this.upload<{ attachment: QuotationAttachment }>(`/quotations/${id}/photos`, form)).attachment;
  }
  deleteQuotationPhoto(id: string, attachmentId: string) {
    return this.request<void>('DELETE', `/quotations/${id}/photos/${attachmentId}`);
  }
  fetchQuotationPhoto(id: string, attachmentId: string) {
    return this.blob(`/quotations/${id}/photos/${attachmentId}`, 'image/*');
  }
  fetchQuotationPdf(id: string) {
    return this.blob(`/quotations/${id}/pdf`, 'application/pdf');
  }
  /** `GET /admin/work-orders` — the board shape (active + finished today; `status` narrows to one column). */
  listWorkOrders(f: WorkOrderFilters) {
    return this.list<WorkOrder>(`/admin/work-orders${qs(f)}`);
  }
  async getWorkOrder(id: string) {
    return (await this.request<{ work_order: WorkOrder }>('GET', `/admin/work-orders/${id}`)).work_order;
  }
  /** `POST /tasks/:id/assign` answers with the task; the board card is re-read from `/admin/work-orders/:id`. */
  async assignTask(taskId: string, body: { assignee_id: string; reason?: string }) {
    const { task } = await this.request<{ task: Task }>('POST', `/tasks/${taskId}/assign`, body);
    return this.getWorkOrder(task.work_order_id);
  }
  /** `POST /work-orders/:id/checkin` answers `{ work_order, task, already }`; the board card is re-read from `/admin/work-orders/:id`. */
  async checkinWorkOrder(id: string, body: { bay?: string | null }) {
    await this.request<{ work_order: { id: string }; task: Task | null; already: boolean }>('POST', `/work-orders/${id}/checkin`, body);
    return this.getWorkOrder(id);
  }
  /** `POST /work-orders/:id/pickup/verify` answers with the bare row; the board card is re-read and `collected_at` overlaid (the admin shape may not carry it). */
  async verifyPickup(id: string, otp: string) {
    const res = await this.request<{ work_order: { id: string; collected_at?: string | null; pickup_otp_verified_at?: string | null }; collected_at: string; collected: boolean }>('POST', `/work-orders/${id}/pickup/verify`, { otp });
    const row = await this.getWorkOrder(id);
    const collected_at = row.collected_at ?? res.collected_at ?? res.work_order.collected_at ?? new Date().toISOString();
    return { work_order: { ...row, collected_at, pickup_otp_verified_at: row.pickup_otp_verified_at ?? res.work_order.pickup_otp_verified_at ?? collected_at }, collected_at, collected: true as const };
  }
  async resendPickupOtp(id: string) {
    const res = await this.request<{ work_order: { id: string }; notification?: PickupResendResult['notification']; retry_after_seconds?: number }>('POST', `/work-orders/${id}/pickup/resend`, {});
    return { work_order: await this.getWorkOrder(id), notification: res.notification ?? [], retry_after_seconds: res.retry_after_seconds ?? 60 };
  }
  /** Verifying with incomplete required steps needs a supervisor `override.reason` — the drawer's reason doubles as that. */
  async transitionTask(taskId: string, body: { to: WorkStatus; reason?: string }) {
    const override = body.to === 'verified' && body.reason ? { override: { reason: body.reason } } : {};
    const { work_order } = await this.request<{ task: Task; work_order: { id: string } }>('POST', `/tasks/${taskId}/transition`, { ...body, ...override, client_op_id: uuid() });
    return this.getWorkOrder(work_order.id);
  }
  team(p: OutletScoped) {
    return this.list<TeamMember>(`/staff/team${qs(p)}`);
  }
  listUsers() {
    return this.list<StaffUser>('/admin/users?limit=500');
  }
  inviteUser(body: CreateStaffInput) {
    return this.request<CreateStaffResult>('POST', '/admin/users', body);
  }
  resetUserPassword(id: string) {
    return this.request<ResetPasswordResult>('POST', `/admin/users/${id}/reset-password`);
  }
  async confirmPasswordChanged() {
    const res = await this.request<{ profile: Profile }>('POST', '/auth/password-changed');
    return res.profile;
  }
  async updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; skills?: string[]; is_active?: boolean; phone?: string | null }) {
    const res = await this.request<{ profile: Profile; outlet_ids: string[] }>('PATCH', `/admin/users/${id}`, patch);
    return { ...res.profile, outlet_ids: res.outlet_ids ?? [], outlet_names: [], skills: patch.skills ?? [] } as StaffUser;
  }
  /** Rows without completed tasks have null cycle / compliance figures; the grid shows them as 0. */
  async staffPerformance(p: OutletScoped & { period: Period }) {
    const rows = await this.list<StaffPerformanceRow & { avg_cycle_minutes: number | null; checklist_compliance_pct: number | null }>(`/admin/staff/performance${qs(p)}`);
    return rows.map((r) => ({ ...r, avg_cycle_minutes: r.avg_cycle_minutes ?? 0, checklist_compliance_pct: r.checklist_compliance_pct ?? 0 }));
  }
  async searchCustomers(search: string) {
    const rows = await this.list<CustomerSummary & { loyalty: CustomerSummary['loyalty'] | null }>(`/admin/customers${qs({ search, limit: 200 })}`);
    return rows.map((r) => ({ ...r, loyalty: r.loyalty ?? undefined }));
  }
  async getCustomer(id: string) {
    const r = await this.request<CustomerEnvelope>('GET', `/admin/customers/${id}`);
    return { ...r.customer, vehicle_count: r.vehicle_count, booking_count: r.booking_count, loyalty: r.loyalty ?? undefined, vehicles: r.vehicles, bookings: r.bookings, ledger: r.ledger, membership: r.membership } as CustomerDetail;
  }
  searchWalkInCustomers(search: string) {
    return this.list<WalkInCustomer>(`/staff/customers${qs({ search, limit: 20 })}`);
  }
  async createWalkInCustomer(input: WalkInCustomerInput) {
    const res = await this.request<{ customer: WalkInCustomer }>('POST', '/staff/customers', input);
    return res.customer;
  }
  createCustomerVehicle(customerId: string, input: VehicleInput, force = false) {
    return this.request<{ vehicle: Vehicle; duplicate: boolean }>('POST', `/staff/customers/${customerId}/vehicles`, force ? { ...input, force: true } : input);
  }
  listOutletServicesFor(outletId: string, vehicleSize?: VehicleSize) {
    return this.list<OutletServiceOffer>(`/outlets/${outletId}/services${qs({ vehicle_size: vehicleSize })}`);
  }
  availability(outletId: string, serviceId: string, dateISO: string) {
    return this.list<AvailabilitySlot>(`/availability${qs({ outlet_id: outletId, service_id: serviceId, date: dateISO })}`);
  }
  createWalkInBooking(input: WalkInBookingInput) {
    return this.request<WalkInBookingResult>('POST', '/bookings', input);
  }
  /** 201 `{ payment, duplicate:false }` (200 `duplicate:true` on an idempotent replay) — the dashboard keeps the payment. */
  async recordPayment(input: RecordPaymentInput) {
    const body: RecordPaymentInput = { ...input, idempotency_key: input.idempotency_key ?? `pos-${uuid()}` };
    if (!body.booking_id) delete body.booking_id;
    if (!body.quotation_id) delete body.quotation_id;
    const res = await this.request<{ payment: PosPayment; duplicate?: boolean }>('POST', '/payments/record', body);
    return res.payment;
  }
  listOutlets() {
    return this.list<Outlet>('/admin/outlets');
  }
  async createOutlet(body: Partial<Outlet>) {
    return (await this.request<{ outlet: Outlet }>('POST', '/admin/outlets', outletBody(body))).outlet;
  }
  async updateOutlet(id: string, patch: Partial<Outlet>) {
    return (await this.request<{ outlet: Outlet }>('PATCH', `/admin/outlets/${id}`, outletBody(patch))).outlet;
  }
  listServices() {
    return this.list<Service>('/admin/services');
  }
  async createService(body: ServiceInput) {
    return (await this.request<{ service: Service }>('POST', '/admin/services', body)).service;
  }
  async updateService(id: string, patch: ServiceInput) {
    return (await this.request<{ service: Service }>('PUT', `/admin/services/${id}`, patch)).service;
  }
  /** The admin route always includes unavailable bindings and prices every size (`price_for`), so the filters need no query params. */
  listOutletOffers(outletId: string) {
    return this.list<OutletServiceOffer>(`/admin/outlets/${outletId}/services`);
  }
  async upsertOutletService(outletId: string, serviceId: string, body: OutletServiceInput) {
    return (await this.request<{ outlet_service: OutletServiceOffer }>('PUT', `/admin/outlets/${outletId}/services/${serviceId}`, body)).outlet_service;
  }
  removeOutletService(outletId: string, serviceId: string) {
    return this.request<void>('DELETE', `/admin/outlets/${outletId}/services/${serviceId}`);
  }
  listTemplates() {
    return this.list<ChecklistTemplate>('/admin/templates');
  }
  async createTemplate(body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'>) {
    return (await this.request<{ template: ChecklistTemplate }>('POST', '/admin/templates', body)).template;
  }
  /** `PUT` always creates a new version; `publish: false` keeps it a draft. */
  async updateTemplate(id: string, body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'> & { publish: boolean }) {
    return (await this.request<{ template: ChecklistTemplate }>('PUT', `/admin/templates/${id}`, body)).template;
  }
  loyaltyConfig() {
    return this.request<LoyaltyConfigResponse>('GET', '/admin/loyalty/config');
  }
  async saveLoyaltyDraft(body: { tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string }) {
    return (await this.request<{ draft: LoyaltyConfig }>('PUT', '/admin/loyalty/config/draft', body)).draft;
  }
  async publishLoyalty() {
    return (await this.request<{ published: LoyaltyConfig }>('POST', '/admin/loyalty/config/publish', {})).published;
  }
  async discardLoyalty() {
    await this.request<{ discarded: { id: string; version: number } }>('POST', '/admin/loyalty/config/discard', {});
  }
  membershipPlans() {
    return this.list<MembershipPlan>('/admin/memberships/plans');
  }
  async saveMembershipPlan(code: string, body: MembershipPlanInput) {
    return (await this.request<{ plan: MembershipPlan }>('PUT', `/admin/memberships/plans/${code}`, body)).plan;
  }
  async listMemberships(p: MembershipFilters) {
    const page = await this.request<Page<MemberRowEnvelope>>('GET', `/admin/memberships${qs(p)}`);
    return { data: page.data.map(flattenMemberRow), next_cursor: page.next_cursor };
  }
  customerMembership(customerId: string) {
    return this.request<MembershipSummary>('GET', `/staff/customers/${customerId}/membership`);
  }
  /** `POST /admin/customers/:id/membership` → `{ membership, invoice, payment, summary }`; the drawer wants the summary. */
  async enrolMembership(customerId: string, body: EnrolMembershipInput) {
    return (await this.request<{ summary: MembershipSummary }>('POST', `/admin/customers/${customerId}/membership`, body)).summary;
  }
  /** Cancels, then re-reads the customer's summary (the API answers with the bare membership row). */
  async cancelMembership(id: string, body: { at_period_end: boolean; reason?: string }) {
    const { membership } = await this.request<{ membership: Membership }>('POST', `/admin/memberships/${id}/cancel`, body);
    return this.customerMembership(membership.customer_id);
  }
  recordMembershipPayment(id: string, invoiceId: string, body: { method: 'cash' | 'card_terminal' | 'eft'; client_op_id: string }) {
    return this.request<RecordMembershipPaymentResult>('POST', `/admin/memberships/${id}/invoices/${invoiceId}/record-payment`, body);
  }
  /** Maps the job's counters (`invoices_created`, `rolled`, …) onto the toast's four figures. */
  async runMembershipRenewals(): Promise<RenewalRunResult> {
    const r = await this.request<RenewalRunEnvelope>('POST', '/admin/memberships/run-renewals', {});
    return { expired: r.expired, invoiced: r.invoices_created, past_due: r.past_due, renewed: r.rolled };
  }
  listInventory(p: OutletScoped & { alerts_first?: boolean }) {
    return this.list<InventoryItem>(`/admin/inventory${qs({ outlet_id: p.outlet_id, alerts_first: p.alerts_first === undefined ? undefined : String(p.alerts_first) })}`);
  }
  /** The staff route answers with the bare item; `outlet_name` / `capacity` come back on the next list. */
  async updateInventoryItem(id: string, patch: { reorder_threshold?: number; name?: string; unit?: string }) {
    return (await this.request<{ item: InventoryItem }>('PATCH', `/inventory/${id}`, patch)).item;
  }
  async addMovement(id: string, body: { delta: number; reason: 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count'; note?: string }) {
    return (await this.request<{ item: InventoryItem }>('POST', `/inventory/${id}/movements`, { ...body, client_op_id: uuid() })).item;
  }
  listPayments(p: OutletScoped) {
    return this.list<Payment>(`/admin/payments${qs({ ...p, limit: 200 })}`);
  }
  reportSummary(f: ReportFilters) {
    return this.request<ReportSummary>('GET', `/admin/reports/summary${qs(f)}`);
  }
  /** Exports take `from`/`to` (whole days); a single `date` filter becomes that one day. Other UI-only filters are dropped server-side. */
  exportCsv(report: ReportKind, filters: Record<string, string | undefined>) {
    const { date, ...rest } = filters;
    const range = date ? { from: date, to: date } : {};
    return this.request<string>('GET', `/admin/exports/${report}.csv${qs({ ...rest, ...range })}`, undefined, true);
  }
  listAudit(f: AuditFilters) {
    const { actor, ...rest } = f;
    return this.request<Page<AuditEvent>>('GET', `/admin/audit${qs({ ...rest, actor_id: actor })}`);
  }
  listFlags() {
    return this.list<FeatureFlag>('/admin/flags');
  }
  async updateFlag(key: string, enabled: boolean) {
    return (await this.request<{ flag: FeatureFlag }>('PATCH', `/admin/flags/${key}`, { enabled })).flag;
  }
  integrations() {
    return this.list<IntegrationStatus>('/admin/integrations');
  }
  listNotifications(f: NotificationFilters) {
    return this.request<Page<NotificationRow>>('GET', `/admin/notifications${qs(f)}`);
  }
  /** `{ notification, outcome }` → the row (recipient name is not on the bare row; the page falls back to the id). */
  async resendNotification(id: string) {
    const { notification } = await this.request<{ notification: NotificationRow & { recipient_name?: string | null } }>('POST', `/admin/notifications/${id}/resend`, {});
    return { ...notification, recipient_name: notification.recipient_name ?? null };
  }
  subscribe() {
    return () => {};
  }
}
