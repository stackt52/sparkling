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
  Booking,
  BookingDetail,
  BookingStatus,
  ChecklistTemplate,
  CustomerDetail,
  CustomerSummary,
  ExceptionItem,
  FeatureFlag,
  IntegrationStatus,
  InventoryItem,
  Kpis,
  LoyaltyConfig,
  LoyaltyConfigResponse,
  LoyaltyRules,
  LoyaltyTierConfig,
  NotificationRow,
  NotifyChannel,
  NotifyStatus,
  Outlet,
  OutletService,
  Page,
  Payment,
  Period,
  QuoteLineItem,
  Quotation,
  QuotationStatus,
  ReportKind,
  ReportSummary,
  Service,
  SessionResponse,
  StaffPerformanceRow,
  StaffUser,
  UserRole,
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
  submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string }): Promise<Quotation>;
  convertQuotation(id: string): Promise<Quotation>;
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
  /* catalogue */
  listOutlets(): Promise<Outlet[]>;
  createOutlet(body: Partial<Outlet>): Promise<Outlet>;
  updateOutlet(id: string, patch: Partial<Outlet>): Promise<Outlet>;
  listServices(): Promise<Service[]>;
  createService(body: Partial<Service>): Promise<Service>;
  updateService(id: string, patch: Partial<Service>): Promise<Service>;
  listOutletServices(): Promise<OutletService[]>;
  setOutletService(outletId: string, serviceId: string, patch: Partial<OutletService>): Promise<OutletService>;
  /* templates */
  listTemplates(): Promise<ChecklistTemplate[]>;
  createTemplate(body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'>): Promise<ChecklistTemplate>;
  updateTemplate(id: string, body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'> & { publish: boolean }): Promise<ChecklistTemplate>;
  /* loyalty */
  loyaltyConfig(): Promise<LoyaltyConfigResponse>;
  saveLoyaltyDraft(body: { tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string }): Promise<LoyaltyConfig>;
  publishLoyalty(): Promise<LoyaltyConfig>;
  discardLoyalty(): Promise<void>;
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

function uuid(): string {
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
    if (!res.ok) {
      let err: ApiError = { code: 'internal', message: `HTTP ${res.status}` };
      try {
        const json = (await res.json()) as { error?: ApiError };
        if (json.error) err = json.error;
      } catch {
        /* non-JSON error body */
      }
      throw new ApiRequestError(res.status, err);
    }
    if (raw) return (await res.text()) as unknown as T;
    if (res.status === 204) return undefined as T;
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
  submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string }) {
    return this.request<Quotation>('POST', `/quotations/${id}/quote`, body);
  }
  convertQuotation(id: string) {
    return this.request<Quotation>('POST', `/quotations/${id}/convert`, {});
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
  createService(body: Partial<Service>) {
    return this.request<Service>('POST', '/admin/services', body);
  }
  updateService(id: string, patch: Partial<Service>) {
    return this.request<Service>('PATCH', `/admin/services/${id}`, patch);
  }
  listOutletServices() {
    return this.list<OutletService>('/admin/outlet-services');
  }
  setOutletService(outletId: string, serviceId: string, patch: Partial<OutletService>) {
    return this.request<OutletService>('PUT', `/admin/outlets/${outletId}/services/${serviceId}`, patch);
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
