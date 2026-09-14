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
  BookingDetail,
  BookingStatus,
  ChecklistTemplate,
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
  MembershipInvoice,
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
  PosPayment,
  QuoteLineItem,
  Quotation,
  QuotationAttachment,
  QuotationStatus,
  RaiseQuotationInput,
  RecordPaymentInput,
  RenewalRunResult,
  ReportKind,
  ReportSummary,
  Service,
  ServiceInput,
  SessionResponse,
  ShareQuotationResult,
  StaffPerformanceRow,
  StaffUser,
  UserRole,
  Vehicle,
  VehicleInput,
  VehicleSize,
  WalkInBookingInput,
  WalkInBookingResult,
  WalkInCustomer,
  WalkInCustomerInput,
  WorkOrder,
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
}
export interface WorkOrderFilters extends OutletScoped {
  status?: WorkStatus | 'all';
}
export interface AuditFilters {
  entity_type?: string;
  action?: string;
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
  /* quotations */
  listQuotations(filters: QuotationFilters): Promise<Quotation[]>;
  getQuotation(id: string): Promise<Quotation>;
  submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string; items_note?: string | null }): Promise<Quotation>;
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
  assignTask(taskId: string, body: { assignee_id: string; reason?: string }): Promise<WorkOrder>;
  transitionTask(taskId: string, body: { to: WorkStatus; reason?: string }): Promise<WorkOrder>;
  team(params: OutletScoped): Promise<TeamMember[]>;
  /* users */
  listUsers(): Promise<StaffUser[]>;
  inviteUser(body: { email: string; full_name: string; role: UserRole; outlet_ids: string[] }): Promise<StaffUser>;
  updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; is_active?: boolean }): Promise<StaffUser>;
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
  recordMembershipPayment(id: string, invoiceId: string, body: { method: 'cash' | 'card_terminal' | 'eft'; client_op_id: string }): Promise<{ invoice: MembershipInvoice; membership: MembershipSummary }>;
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
  kpis(p: OutletScoped & { period: Period }) {
    return this.request<Kpis>('GET', `/admin/kpis${qs(p)}`);
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
  cancelBooking(id: string, reason: string) {
    return this.request<Booking>('POST', `/bookings/${id}/cancel`, { reason });
  }
  listQuotations(f: QuotationFilters) {
    return this.list<Quotation>(`/quotations${qs(f)}`);
  }
  getQuotation(id: string) {
    return this.request<Quotation>('GET', `/quotations/${id}`);
  }
  submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string; items_note?: string | null }) {
    return this.request<Quotation>('POST', `/quotations/${id}/quote`, body);
  }
  convertQuotation(id: string) {
    return this.request<Quotation>('POST', `/quotations/${id}/convert`, {});
  }
  async raiseQuotation(input: RaiseQuotationInput) {
    const res = await this.request<{ quotation: Quotation } | Quotation>('POST', '/quotations', input);
    return 'quotation' in res ? res.quotation : res;
  }
  shareQuotation(id: string) {
    return this.request<ShareQuotationResult>('POST', `/quotations/${id}/share`, {});
  }
  uploadQuotationPhoto(id: string, file: File, caption?: string) {
    const form = new FormData();
    form.append('photo', file, file.name);
    if (caption) form.append('caption', caption);
    return this.upload<QuotationAttachment>(`/quotations/${id}/photos`, form);
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
  listWorkOrders(f: WorkOrderFilters) {
    return this.list<WorkOrder>(`/tasks${qs({ scope: 'queue', ...f })}`);
  }
  getWorkOrder(id: string) {
    return this.request<WorkOrder>('GET', `/work-orders/${id}`);
  }
  assignTask(taskId: string, body: { assignee_id: string; reason?: string }) {
    return this.request<WorkOrder>('POST', `/tasks/${taskId}/assign`, body);
  }
  transitionTask(taskId: string, body: { to: WorkStatus; reason?: string }) {
    return this.request<WorkOrder>('POST', `/tasks/${taskId}/transition`, { ...body, client_op_id: uuid() });
  }
  team(p: OutletScoped) {
    return this.list<TeamMember>(`/staff/team${qs(p)}`);
  }
  listUsers() {
    return this.list<StaffUser>('/admin/users');
  }
  inviteUser(body: { email: string; full_name: string; role: UserRole; outlet_ids: string[] }) {
    return this.request<StaffUser>('POST', '/admin/users', body);
  }
  updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; is_active?: boolean }) {
    return this.request<StaffUser>('PATCH', `/admin/users/${id}`, patch);
  }
  staffPerformance(p: OutletScoped & { period: Period }) {
    return this.list<StaffPerformanceRow>(`/admin/staff/performance${qs(p)}`);
  }
  searchCustomers(search: string) {
    return this.list<CustomerSummary>(`/admin/customers${qs({ search })}`);
  }
  getCustomer(id: string) {
    return this.request<CustomerDetail>('GET', `/admin/customers/${id}`);
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
  async recordPayment(input: RecordPaymentInput) {
    const res = await this.request<{ payment: PosPayment }>('POST', '/payments/record', input);
    return res.payment;
  }
  listOutlets() {
    return this.list<Outlet>('/admin/outlets');
  }
  createOutlet(body: Partial<Outlet>) {
    return this.request<Outlet>('POST', '/admin/outlets', body);
  }
  updateOutlet(id: string, patch: Partial<Outlet>) {
    return this.request<Outlet>('PATCH', `/admin/outlets/${id}`, patch);
  }
  listServices() {
    return this.list<Service>('/admin/services');
  }
  createService(body: ServiceInput) {
    return this.request<Service>('POST', '/admin/services', body);
  }
  updateService(id: string, patch: ServiceInput) {
    return this.request<Service>('PUT', `/admin/services/${id}`, patch);
  }
  listOutletOffers(outletId: string, f: OutletOfferFilters = {}) {
    return this.list<OutletServiceOffer>(`/admin/outlets/${outletId}/services${qs({ vehicle_size: f.vehicleSize, include_unavailable: f.includeUnavailable ? 'true' : undefined })}`);
  }
  upsertOutletService(outletId: string, serviceId: string, body: OutletServiceInput) {
    return this.request<OutletServiceOffer>('PUT', `/admin/outlets/${outletId}/services/${serviceId}`, body);
  }
  removeOutletService(outletId: string, serviceId: string) {
    return this.request<void>('DELETE', `/admin/outlets/${outletId}/services/${serviceId}`);
  }
  listTemplates() {
    return this.list<ChecklistTemplate>('/admin/templates');
  }
  createTemplate(body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'>) {
    return this.request<ChecklistTemplate>('POST', '/admin/templates', body);
  }
  updateTemplate(id: string, body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'> & { publish: boolean }) {
    return this.request<ChecklistTemplate>('PUT', `/admin/templates/${id}`, body);
  }
  loyaltyConfig() {
    return this.request<LoyaltyConfigResponse>('GET', '/admin/loyalty/config');
  }
  saveLoyaltyDraft(body: { tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string }) {
    return this.request<LoyaltyConfig>('PUT', '/admin/loyalty/config/draft', body);
  }
  publishLoyalty() {
    return this.request<LoyaltyConfig>('POST', '/admin/loyalty/config/publish', {});
  }
  discardLoyalty() {
    return this.request<void>('POST', '/admin/loyalty/config/discard', {});
  }
  membershipPlans() {
    return this.list<MembershipPlan>('/admin/memberships/plans');
  }
  saveMembershipPlan(code: string, body: MembershipPlanInput) {
    return this.request<MembershipPlan>('PUT', `/admin/memberships/plans/${code}`, body);
  }
  listMemberships(p: MembershipFilters) {
    return this.request<Page<MembershipRow>>('GET', `/admin/memberships${qs(p)}`);
  }
  customerMembership(customerId: string) {
    return this.request<MembershipSummary>('GET', `/staff/customers/${customerId}/membership`);
  }
  enrolMembership(customerId: string, body: EnrolMembershipInput) {
    return this.request<MembershipSummary>('POST', `/admin/customers/${customerId}/membership`, body);
  }
  cancelMembership(id: string, body: { at_period_end: boolean; reason?: string }) {
    return this.request<MembershipSummary>('POST', `/admin/memberships/${id}/cancel`, body);
  }
  recordMembershipPayment(id: string, invoiceId: string, body: { method: 'cash' | 'card_terminal' | 'eft'; client_op_id: string }) {
    return this.request<{ invoice: MembershipInvoice; membership: MembershipSummary }>('POST', `/admin/memberships/${id}/invoices/${invoiceId}/record-payment`, body);
  }
  runMembershipRenewals() {
    return this.request<RenewalRunResult>('POST', '/admin/memberships/run-renewals', {});
  }
  listInventory(p: OutletScoped & { alerts_first?: boolean }) {
    return this.list<InventoryItem>(`/admin/inventory${qs(p)}`);
  }
  updateInventoryItem(id: string, patch: { reorder_threshold?: number; name?: string; unit?: string }) {
    return this.request<InventoryItem>('PATCH', `/inventory/${id}`, patch);
  }
  addMovement(id: string, body: { delta: number; reason: 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count'; note?: string }) {
    return this.request<InventoryItem>('POST', `/inventory/${id}/movements`, { ...body, client_op_id: uuid() });
  }
  listPayments(p: OutletScoped) {
    return this.list<Payment>(`/admin/payments${qs(p)}`);
  }
  reportSummary(f: ReportFilters) {
    return this.request<ReportSummary>('GET', `/admin/reports/summary${qs(f)}`);
  }
  exportCsv(report: ReportKind, filters: Record<string, string | undefined>) {
    return this.request<string>('GET', `/admin/exports/${report}.csv${qs(filters)}`, undefined, true);
  }
  listAudit(f: AuditFilters) {
    return this.request<Page<AuditEvent>>('GET', `/admin/audit${qs(f)}`);
  }
  listFlags() {
    return this.list<FeatureFlag>('/admin/flags');
  }
  updateFlag(key: string, enabled: boolean) {
    return this.request<FeatureFlag>('PATCH', `/admin/flags/${key}`, { enabled });
  }
  integrations() {
    return this.list<IntegrationStatus>('/admin/integrations');
  }
  listNotifications(f: NotificationFilters) {
    return this.request<Page<NotificationRow>>('GET', `/admin/notifications${qs(f)}`);
  }
  resendNotification(id: string) {
    return this.request<NotificationRow>('POST', `/admin/notifications/${id}/resend`, {});
  }
  subscribe() {
    return () => {};
  }
}
