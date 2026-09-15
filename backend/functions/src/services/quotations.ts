/**
 * CUS-030..034 / STF-010/012: repair quotations — customer requests, staff-raised
 * quotes, the public quote page (token link), one-time decisions and the
 * notifications around them.
 */
import { randomUUID } from 'node:crypto';
import { config } from '../config.js';
import { canTransitionQuotation } from '../domain/stateMachines.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { assertOutlet, assertOwner, assertOwnerOrOutletStaff, isStaff } from '../middleware/auth.js';
import { logger } from '../middleware/correlation.js';
import { ApiError } from '../middleware/errors.js';
import type { Attachment, AuthContext, Outlet, Profile, Quotation, QuotationDecisionSource, QuotationLineItem, RequestContext, Vehicle } from '../types.js';
import { audit } from './audit.js';
import { getCustomerOrThrow } from './customers.js';
import { benefitFor, loadContext, postUsage } from './memberships.js';
import { firstName, formatRand, notify, type NotifyOutcome } from './notifications.js';
import { convertQuotation as convertToWorkOrder } from './workflow.js';

export const PUBLIC_TOKEN_TTL_DAYS = 30;
export const SHARE_MIN_INTERVAL_MS = 60_000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Public link helpers
// ---------------------------------------------------------------------------

/** `${PUBLIC_WEB_BASE_URL}/q/<token>`, or null when the base URL or token is missing. */
export function publicQuoteUrl(token: string | null | undefined): string | null {
  const base = config.publicWebBaseUrl;
  if (!base || !token) return null;
  return `${base}/q/${token}`;
}

export function newPublicToken(now = new Date()): { public_token: string; public_token_expires_at: string } {
  return { public_token: randomUUID(), public_token_expires_at: new Date(now.getTime() + PUBLIC_TOKEN_TTL_DAYS * 86_400_000).toISOString() };
}

export function publicTokenExpired(q: Pick<Quotation, 'public_token' | 'public_token_expires_at'>, now = new Date()): boolean {
  if (!q.public_token) return true;
  if (!q.public_token_expires_at) return false;
  return new Date(q.public_token_expires_at).getTime() < now.getTime();
}

/** True once `valid_until` (a date) is behind today's UTC date, or the row is already `expired`. */
export function quoteExpired(q: Pick<Quotation, 'status' | 'valid_until'>, now = new Date()): boolean {
  if (q.status === 'expired') return true;
  if (!q.valid_until) return false;
  const today = now.toISOString().slice(0, 10);
  return q.valid_until.slice(0, 10) < today;
}

export function sumItems(items: Array<Pick<QuotationLineItem, 'amount_cents'>>): number {
  return items.reduce((a, l) => a + l.amount_cents, 0);
}

// ---------------------------------------------------------------------------
// Customer request (unchanged shape: status `requested`)
// ---------------------------------------------------------------------------

export interface CreateQuotationInput {
  vehicleId: string;
  outletId: string;
  category: string;
  description: string;
  clientOpId: string;
  attachmentIds?: string[];
}

export async function createQuotation(ctx: RequestContext, input: CreateQuotationInput): Promise<{ quotation: Quotation; duplicate: boolean }> {
  const db = getSupabase();
  const existing = await db.from('quotations').select('*').eq('client_op_id', input.clientOpId).maybeSingle();
  if (existing.data) return { quotation: existing.data as Quotation, duplicate: true };
  const vehicle = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', input.vehicleId).maybeSingle(), 'vehicle');
  if (!vehicle || !vehicle.is_active) throw ApiError.notFound('Vehicle');
  if (vehicle.customer_id !== ctx.auth.uid) throw ApiError.forbidden('Vehicle belongs to another customer');
  const outlet = await db.from('outlets').select('id').eq('id', input.outletId).eq('is_active', true).maybeSingle();
  if (!outlet.data) throw ApiError.notFound('Outlet');
  const res = await db
    .from('quotations')
    .insert({
      customer_id: ctx.auth.uid,
      vehicle_id: vehicle.id,
      outlet_id: input.outletId,
      category: input.category,
      description: input.description,
      status: 'requested',
      client_op_id: input.clientOpId,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const dup = unwrap<Quotation>(await db.from('quotations').select('*').eq('client_op_id', input.clientOpId).single(), 'quotation');
      return { quotation: dup, duplicate: true };
    }
    throw new DatabaseError(res.error, 'create quotation');
  }
  const quotation = res.data as Quotation;
  if (input.attachmentIds?.length) {
    await db.from('attachments').update({ entity_type: 'quotation', entity_id: quotation.id }).in('id', input.attachmentIds).eq('uploaded_by', ctx.auth.uid);
  }
  await audit(ctx, { action: 'quotation.create', entity_type: 'quotation', entity_id: quotation.id, outlet_id: quotation.outlet_id, after: { ref: quotation.ref } });
  return { quotation, duplicate: false };
}

// ---------------------------------------------------------------------------
// Staff-raised quotation (one step → `quoted`, public token, quote_ready)
// ---------------------------------------------------------------------------

export interface RaiseQuotationInput {
  customerId: string;
  vehicleId: string;
  outletId: string;
  category: string;
  description: string;
  items: QuotationLineItem[];
  validUntil: string;
  itemsNote?: string | null;
  clientOpId: string;
  sendToCustomer: boolean;
}

export async function raiseQuotation(ctx: RequestContext, input: RaiseQuotationInput): Promise<{ quotation: Quotation; duplicate: boolean; notification: NotifyOutcome[] }> {
  const db = getSupabase();
  if (!isStaff(ctx.auth.role)) throw ApiError.forbidden('Only staff can raise a quotation');
  const existing = await db.from('quotations').select('*').eq('client_op_id', input.clientOpId).maybeSingle();
  if (existing.data) return { quotation: existing.data as Quotation, duplicate: true, notification: [] };

  assertOutlet(ctx.auth, input.outletId);
  const outlet = await db.from('outlets').select('id').eq('id', input.outletId).eq('is_active', true).maybeSingle();
  if (!outlet.data) throw ApiError.notFound('Outlet');
  const customer = await getCustomerOrThrow(input.customerId);
  const vehicle = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', input.vehicleId).maybeSingle(), 'vehicle');
  if (!vehicle || !vehicle.is_active) throw ApiError.notFound('Vehicle');
  if (vehicle.customer_id !== customer.id) throw ApiError.validation('Vehicle does not belong to this customer', [{ path: 'vehicle_id', message: 'vehicle belongs to another customer' }]);
  const serviceIds = [...new Set(input.items.map((i) => i.service_id).filter((s): s is string => !!s))];
  if (serviceIds.length) {
    const services = unwrap<Array<{ id: string }>>(await db.from('services').select('id').in('id', serviceIds).eq('is_active', true), 'services');
    const known = new Set(services.map((s) => s.id));
    const missing = serviceIds.filter((s) => !known.has(s));
    if (missing.length) throw ApiError.validation('Unknown service_id on items', missing.map((id) => ({ path: 'items.service_id', message: `service ${id} not found` })));
  }

  const now = new Date();
  // Membership coverage (docs/MEMBERSHIPS.md rule 4): a by-quote service with allowance left
  // (Black annual ceramic coating) is recorded at R0 on that line; the allowance is consumed below.
  const membership = await loadContext(customer.id, now);
  const covered = new Map<number, { entitlement_id: string; period_start: string; period_end: string }>();
  const items = input.items.map((raw, idx) => {
    const item = normaliseItem(raw);
    if (!item.service_id || !membership) return item;
    const already = [...covered.values()].map((c) => c.entitlement_id);
    const b = benefitFor(item.service_id, membership);
    if (b?.benefit === 'included' && b.entitlement_id && b.period_start && b.period_end && !already.includes(b.entitlement_id)) {
      covered.set(idx, { entitlement_id: b.entitlement_id, period_start: b.period_start, period_end: b.period_end });
      return { ...item, amount_cents: 0, membership_benefit: 'included' as const, entitlement_id: b.entitlement_id };
    }
    return item;
  });
  const res = await db
    .from('quotations')
    .insert({
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      outlet_id: input.outletId,
      category: input.category,
      description: input.description,
      status: 'quoted',
      amount_cents: sumItems(items),
      line_items: items,
      items_note: input.itemsNote ?? null,
      assessor_id: ctx.auth.uid,
      valid_until: input.validUntil,
      quoted_at: now.toISOString(),
      client_op_id: input.clientOpId,
      ...newPublicToken(now),
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const dup = unwrap<Quotation>(await db.from('quotations').select('*').eq('client_op_id', input.clientOpId).single(), 'quotation');
      return { quotation: dup, duplicate: true, notification: [] };
    }
    throw new DatabaseError(res.error, 'raise quotation');
  }
  const quotation = res.data as Quotation;
  for (const c of covered.values()) {
    await postUsage({ membershipId: membership!.membership.id, entitlementId: c.entitlement_id, bookingId: null, quantity: 1, period: { period_start: c.period_start, period_end: c.period_end }, idempotencyKey: `quotation:${quotation.id}:membership:${c.entitlement_id}`, createdBy: ctx.auth.uid });
  }
  await audit(ctx, {
    action: 'quotation.raise',
    entity_type: 'quotation',
    entity_id: quotation.id,
    outlet_id: quotation.outlet_id,
    after: { ref: quotation.ref, customer_id: customer.id, amount_cents: quotation.amount_cents, items: items.length, valid_until: quotation.valid_until, sent: input.sendToCustomer, membership_covered: covered.size },
  });
  const notification = input.sendToCustomer ? await sendQuoteReady(quotation, customer) : [];
  return { quotation, duplicate: false, notification };
}

function normaliseItem(i: QuotationLineItem): QuotationLineItem {
  const out: QuotationLineItem = { label: i.label, amount_cents: i.amount_cents };
  if (i.description) out.description = i.description;
  if (i.category) out.category = i.category;
  if (i.service_id) out.service_id = i.service_id;
  if (i.quantity && i.quantity > 0) out.quantity = i.quantity;
  if (i.membership_benefit) out.membership_benefit = i.membership_benefit;
  if (i.entitlement_id) out.entitlement_id = i.entitlement_id;
  return out;
}

/**
 * `quote_ready` push + WhatsApp. Content template variables: `first_name`,
 * `public_token` (button URL `<PUBLIC_WEB_BASE_URL>/q/{{2}}`); the free-form
 * body carries `public_url` (null → omitted when no base URL is configured).
 */
export async function sendQuoteReady(q: Quotation, customer?: Pick<Profile, 'full_name'> | null): Promise<NotifyOutcome[]> {
  const db = getSupabase();
  const profile = customer ?? unwrap<{ full_name: string | null } | null>(await db.from('profiles').select('full_name').eq('id', q.customer_id).maybeSingle(), 'customer');
  const publicUrl = publicQuoteUrl(q.public_token);
  return notify({
    recipientId: q.customer_id,
    templateKey: 'quote_ready',
    vars: {
      first_name: firstName(profile?.full_name),
      ref: q.ref,
      amount: formatRand(q.amount_cents ?? 0),
      public_token: q.public_token,
      public_url: publicUrl,
      quotation_id: q.id,
    },
    dedupeKey: `quote_ready:${q.id}:${q.public_token ?? q.quoted_at}`,
    payload: { type: 'quotation', quotation_id: q.id, ...(publicUrl ? { url: publicUrl } : {}) },
  });
}

// ---------------------------------------------------------------------------
// Lookups & presentation
// ---------------------------------------------------------------------------

export async function getQuotationOrThrow(id: string): Promise<Quotation> {
  const q = unwrap<Quotation | null>(await getSupabase().from('quotations').select('*').eq('id', id).maybeSingle(), 'quotation');
  if (!q) throw ApiError.notFound('Quotation');
  return q;
}

/** Token → quotation. 404 unknown, 410 `gone` (with `{ref,status}`) once the link expired. */
export async function getQuotationByPublicToken(token: string): Promise<Quotation> {
  if (!UUID_RE.test(token)) throw ApiError.notFound('Quotation');
  const q = unwrap<Quotation | null>(await getSupabase().from('quotations').select('*').eq('public_token', token).maybeSingle(), 'quotation by token');
  if (!q) throw ApiError.notFound('Quotation');
  if (publicTokenExpired(q)) throw ApiError.gone('This quotation link has expired', { ref: q.ref, status: q.status });
  return q;
}

export async function loadQuotationAttachments(quotationIds: string[]): Promise<Attachment[]> {
  if (quotationIds.length === 0) return [];
  return unwrap<Attachment[]>(await getSupabase().from('attachments').select('*').eq('entity_type', 'quotation').in('entity_id', quotationIds).order('created_at'), 'attachments');
}

export function attachmentView(att: Attachment, baseUrl: string) {
  return {
    id: att.id,
    kind: att.kind ?? 'document',
    mime_type: att.mime_type,
    size_bytes: att.size_bytes,
    width: att.width ?? null,
    height: att.height ?? null,
    caption: att.caption ?? null,
    url: `${baseUrl}/photos/${att.id}`,
    created_at: att.created_at,
  };
}

/** Signed-in view: `public_token` is never exposed; `public_url` only to staff. Embedded `customer` / `assessor` rows are flattened into `*_name`. */
export function presentQuotation(q: Quotation, attachments: Attachment[], auth: AuthContext): Record<string, unknown> {
  const { public_token: _token, ...rest } = q as Quotation & Record<string, unknown>;
  const base = `/v1/quotations/${q.id}`;
  const customer = (rest as { customer?: { full_name?: string } | null }).customer;
  const assessor = (rest as { assessor?: { full_name?: string } | null }).assessor;
  return {
    ...rest,
    customer_name: customer?.full_name ?? null,
    assessor_name: assessor?.full_name ?? null,
    amount_cents: q.amount_cents ?? null,
    valid_until: q.valid_until ?? null,
    quoted_at: q.quoted_at ?? null,
    decided_at: q.decided_at ?? null,
    pdf_generated_at: q.pdf_generated_at ?? null,
    items: q.line_items ?? [],
    items_note: q.items_note ?? null,
    decision_source: q.decision_source ?? null,
    decision_by_name: q.decision_by_name ?? null,
    public_token_expires_at: q.public_token_expires_at ?? null,
    attachments: attachments.map((a) => attachmentView(a, base)),
    pdf_url: `${base}/pdf`,
    terms: QUOTE_TERMS,
    ...(isStaff(auth.role) ? { public_url: publicQuoteUrl(q.public_token) } : {}),
  };
}

/** Public (unauthenticated) view — first name only, no phone / e-mail. */
export async function publicQuotationView(q: Quotation, attachments?: Attachment[]): Promise<Record<string, unknown>> {
  const db = getSupabase();
  const [outlet, customer, vehicle, atts] = await Promise.all([
    db.from('outlets').select(OUTLET_LEGAL_COLUMNS).eq('id', q.outlet_id).maybeSingle(),
    db.from('profiles').select('full_name').eq('id', q.customer_id).maybeSingle(),
    db.from('vehicles').select('registration_no, make, model, colour').eq('id', q.vehicle_id).maybeSingle(),
    attachments ? Promise.resolve(attachments) : loadQuotationAttachments([q.id]),
  ]);
  const o = (outlet.data ?? null) as Pick<Outlet, 'name' | 'phone' | 'address_line' | 'city' | 'legal_name' | 'trading_as' | 'company_registration_no' | 'vat_number' | 'registered_office' | 'bank_details'> | null;
  const v = (vehicle.data ?? null) as Pick<Vehicle, 'registration_no' | 'make' | 'model' | 'colour'> | null;
  const base = `/v1/public/quotations/${q.public_token}`;
  const expired = quoteExpired(q);
  return {
    ref: q.ref,
    status: q.status,
    outlet: o ? { name: o.name, phone: o.phone ?? null, address_line: o.address_line ?? null, city: o.city ?? null, legal_name: o.legal_name ?? null, trading_as: o.trading_as ?? null, company_registration_no: o.company_registration_no ?? null, vat_number: o.vat_number ?? null, registered_office: o.registered_office ?? null, bank_details: o.bank_details ?? null } : null,
    customer: { first_name: firstName((customer.data as { full_name?: string | null } | null)?.full_name) },
    vehicle: v ? { registration_no: v.registration_no, make: v.make ?? null, model: v.model ?? null, colour: v.colour ?? null } : null,
    items: q.line_items ?? [],
    amount_cents: q.amount_cents ?? null,
    currency: 'ZAR',
    valid_until: q.valid_until ?? null,
    quoted_at: q.quoted_at ?? null,
    decided_at: q.decided_at ?? null,
    decision_source: q.decision_source ?? null,
    expired,
    can_decide: q.status === 'quoted' && !q.decided_at && !expired,
    attachments: atts.filter((a) => a.kind === 'damage_photo' || (a.mime_type ?? '').startsWith('image/')).map((a) => ({ id: a.id, url: `${base}/photos/${a.id}`, caption: a.caption ?? null, width: a.width ?? null, height: a.height ?? null })),
    pdf_url: `${base}/pdf`,
    notes: q.items_note ?? null,
    terms: QUOTE_TERMS,
  };
}

/** Standard terms printed on every quotation (PDF, public page, apps). */
export const QUOTE_TERMS =
  'This quotation does not include hidden or latent defects. Part prices are subject to fluctuations. We are not in any way responsible for loss due to fire, theft or unforeseen circumstances. All glass is removed and fitted at the vehicle owner’s risk. Alarms and immobilizers are vehicle owner’s responsibility. Insurance excess is payable in cash or EFT before the vehicle release. By accepting this quote, the customer hereby acknowledges and agrees that this Sparkling Auto Care Centre has the right to withhold his/her vehicle until payment in full has been made to the outlet. The customer hereby acknowledges that his/her vehicle will not be released if proof of payment cannot be produced.';

export const OUTLET_LEGAL_COLUMNS = 'name, code, phone, email, address_line, city, legal_name, trading_as, company_registration_no, vat_number, registered_office, bank_details';

// ---------------------------------------------------------------------------
// Supervisor quote of a customer request
// ---------------------------------------------------------------------------

export async function quote(ctx: RequestContext, id: string, input: { amount_cents: number; line_items: QuotationLineItem[]; valid_until: string; items_note?: string | null }): Promise<Quotation> {
  const db = getSupabase();
  const q = await getQuotationOrThrow(id);
  assertOutlet(ctx.auth, q.outlet_id);
  if (!canTransitionQuotation(q.status, 'quoted')) throw ApiError.invalidTransition(q.status, 'quoted', 'quotation');
  const sum = sumItems(input.line_items);
  if (input.line_items.length && sum !== input.amount_cents) throw ApiError.validation('line_items must sum to amount_cents', { sum, amount_cents: input.amount_cents });
  const now = new Date();
  const updated = unwrap<Quotation>(
    await db
      .from('quotations')
      .update({
        status: 'quoted',
        amount_cents: input.amount_cents,
        line_items: input.line_items.map(normaliseItem),
        valid_until: input.valid_until,
        ...(input.items_note !== undefined ? { items_note: input.items_note } : {}),
        assessor_id: ctx.auth.uid,
        quoted_at: now.toISOString(),
        ...newPublicToken(now),
      })
      .eq('id', id)
      .select('*')
      .single(),
    'quote',
  );
  await sendQuoteReady(updated);
  await audit(ctx, { action: 'quotation.quote', entity_type: 'quotation', entity_id: id, outlet_id: q.outlet_id, after: { amount_cents: input.amount_cents } });
  return updated;
}

// ---------------------------------------------------------------------------
// Share: rotate the public token and re-send quote_ready (1/min per quotation)
// ---------------------------------------------------------------------------

export async function shareQuotation(ctx: RequestContext, id: string): Promise<{ quotation: Quotation; public_url: string | null; expires_at: string; notification: NotifyOutcome[] }> {
  const db = getSupabase();
  const q = await getQuotationOrThrow(id);
  if (!isStaff(ctx.auth.role)) throw ApiError.forbidden('Only staff can share a quotation');
  assertOutlet(ctx.auth, q.outlet_id);
  if (q.status !== 'quoted') throw ApiError.conflict(`Only quoted quotations can be shared (status is ${q.status})`, { status: q.status, decided_at: q.decided_at });

  const since = new Date(Date.now() - SHARE_MIN_INTERVAL_MS).toISOString();
  const recent = unwrap<Array<{ created_at: string; payload: Record<string, unknown> | null }>>(
    await db.from('notifications').select('created_at, payload').eq('recipient_id', q.customer_id).eq('template_key', 'quote_ready').gte('created_at', since),
    'recent quote_ready',
  );
  const last = recent.filter((n) => n.payload?.quotation_id === q.id).sort((a, b) => (a.created_at < b.created_at ? 1 : -1))[0];
  if (last) {
    const retryAfter = Math.max(1, Math.ceil((SHARE_MIN_INTERVAL_MS - (Date.now() - new Date(last.created_at).getTime())) / 1000));
    throw new ApiError('rate_limited', `quote_ready was sent ${Math.round((Date.now() - new Date(last.created_at).getTime()) / 1000)}s ago; retry in ${retryAfter}s`, { retry_after_seconds: retryAfter });
  }

  const token = newPublicToken();
  const updated = unwrap<Quotation>(await db.from('quotations').update(token).eq('id', id).select('*').single(), 'share quotation');
  const notification = await sendQuoteReady(updated);
  await audit(ctx, {
    action: 'quotation.share',
    entity_type: 'quotation',
    entity_id: id,
    outlet_id: q.outlet_id,
    before: { public_token_expires_at: q.public_token_expires_at },
    after: { public_token_expires_at: updated.public_token_expires_at, notification: notification.map((n) => `${n.channel}:${n.status}`) },
  });
  return { quotation: updated, public_url: publicQuoteUrl(updated.public_token), expires_at: updated.public_token_expires_at as string, notification };
}

// ---------------------------------------------------------------------------
// Decisions (one-time; app, public link)
// ---------------------------------------------------------------------------

export interface DecisionInput {
  decision: 'accept' | 'decline';
  note?: string | null;
  source: QuotationDecisionSource;
  /** Profile id recorded as `decision_by`. */
  byId: string | null;
  byName: string | null;
}

/** Guards shared by every decision path: one-time, `quoted` only, not past `valid_until`. */
export function assertDecidable(q: Quotation, decision: 'accept' | 'decline'): void {
  if (q.decided_at) throw ApiError.conflict('Quotation has already been decided', { decided_at: q.decided_at, status: q.status });
  if (q.status !== 'quoted') throw ApiError.invalidTransition(q.status, decision === 'accept' ? 'accepted' : 'declined', 'quotation');
}

async function applyDecision(q: Quotation, input: DecisionInput): Promise<Quotation> {
  const db = getSupabase();
  assertDecidable(q, input.decision);
  const to = input.decision === 'accept' ? 'accepted' : 'declined';
  if (to === 'accepted' && quoteExpired(q)) {
    await db.from('quotations').update({ status: 'expired' }).eq('id', q.id);
    throw ApiError.gone('This quotation has expired and can no longer be accepted', { ref: q.ref, status: 'expired', valid_until: q.valid_until });
  }
  const updated = unwrap<Quotation>(
    await db
      .from('quotations')
      .update({ status: to, decided_at: new Date().toISOString(), decision_by: input.byId, decision_note: input.note ?? null, decision_source: input.source, decision_by_name: input.byName })
      .eq('id', q.id)
      .is('decided_at', null)
      .select('*')
      .single(),
    'decision',
  );
  return updated;
}

/** In-app decision by the owning customer (`decision_source:'app'`). */
export async function decide(ctx: RequestContext, id: string, decision: 'accept' | 'decline', note?: string | null): Promise<Quotation> {
  const q = await getQuotationOrThrow(id);
  assertOwner(ctx.auth, q);
  const updated = await applyDecision(q, { decision, note, source: 'app', byId: ctx.auth.uid, byName: ctx.auth.profile?.full_name ?? null });
  await audit(ctx, { action: `quotation.${updated.status}`, entity_type: 'quotation', entity_id: id, outlet_id: q.outlet_id, after: { note, decision_source: 'app' } });
  await notifyDecision(updated, ctx.auth.profile?.full_name ?? null);
  return updated;
}

export interface PublicDecisionMeta {
  ip?: string;
  userAgent?: string;
  correlationId: string;
  log: import('pino').Logger;
}

/** Decision from the public link (`decision_source:'public_link'`); audited with IP + user agent. */
export async function decidePublic(token: string, body: { decision: 'accept' | 'decline'; note?: string | null; accepted_by_name?: string | null }, meta: PublicDecisionMeta): Promise<Quotation> {
  const q = await getQuotationByPublicToken(token);
  const db = getSupabase();
  const customer = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', q.customer_id).maybeSingle(), 'customer');
  const byName = body.accepted_by_name?.trim() || customer?.full_name || null;
  const ctx: RequestContext = {
    auth: { uid: q.customer_id, role: 'customer', outletIds: [], profile: customer, email: customer?.email ?? null, tokenClaims: { via: 'public_link' } },
    correlationId: meta.correlationId,
    log: meta.log,
    ip: meta.ip,
    userAgent: meta.userAgent,
  };
  let updated: Quotation;
  try {
    updated = await applyDecision(q, { decision: body.decision, note: body.note, source: 'public_link', byId: q.customer_id, byName });
  } catch (err) {
    await audit(ctx, {
      action: 'quotation.decision_public',
      entity_type: 'quotation',
      entity_id: q.id,
      outlet_id: q.outlet_id,
      after: { decision: body.decision, accepted_by_name: byName, ip: meta.ip ?? null, user_agent: meta.userAgent ?? null, error: (err as ApiError).code ?? 'error' },
      outcome: 'refused',
    });
    throw err;
  }
  await audit(ctx, {
    action: 'quotation.decision_public',
    entity_type: 'quotation',
    entity_id: q.id,
    outlet_id: q.outlet_id,
    after: { decision: body.decision, status: updated.status, note: body.note ?? null, accepted_by_name: byName, ip: meta.ip ?? null, user_agent: meta.userAgent ?? null },
  });
  await notifyDecision(updated, customer?.full_name ?? null);
  return updated;
}

/** `quote_decided` push to the assessor + outlet supervisors/managers; `quote_decision_receipt` to the customer. */
export async function notifyDecision(q: Quotation, customerName: string | null): Promise<{ staff: NotifyOutcome[]; customer: NotifyOutcome[] }> {
  const db = getSupabase();
  const decision = q.status === 'accepted' ? 'accepted' : 'declined';
  const staffIds = new Set<string>();
  if (q.assessor_id) staffIds.add(q.assessor_id);
  try {
    const members = unwrap<Array<{ profile_id: string }>>(await db.from('staff_outlets').select('profile_id').eq('outlet_id', q.outlet_id), 'outlet staff');
    const ids = members.map((m) => m.profile_id).filter((id) => id !== q.assessor_id);
    if (ids.length) {
      const leads = unwrap<Array<{ id: string }>>(await db.from('profiles').select('id').in('id', ids).in('role', ['supervisor', 'manager']).eq('is_active', true), 'outlet leads');
      for (const l of leads) staffIds.add(l.id);
    }
  } catch (err) {
    logger.warn({ err, quotation_id: q.id }, 'could not resolve outlet staff for quote_decided');
  }
  const outlet = await db.from('outlets').select('name').eq('id', q.outlet_id).maybeSingle();
  const vars = { ref: q.ref, decision, customer: customerName ?? 'the customer', quotation_id: q.id, outlet: (outlet.data as { name?: string } | null)?.name ?? '', amount: formatRand(q.amount_cents ?? 0) };
  const staff: NotifyOutcome[] = [];
  for (const id of staffIds) {
    staff.push(...(await notify({ recipientId: id, templateKey: 'quote_decided', vars, dedupeKey: `quote_decided:${q.id}:${id}`, payload: { type: 'quotation', quotation_id: q.id }, channels: ['push'] })));
  }
  const customer = await notify({
    recipientId: q.customer_id,
    templateKey: 'quote_decision_receipt',
    vars: { ref: q.ref, decision, quotation_id: q.id, amount: vars.amount },
    dedupeKey: `quote_decision_receipt:${q.id}`,
    payload: { type: 'quotation', quotation_id: q.id },
  });
  return { staff, customer };
}

// ---------------------------------------------------------------------------
// Convert & access
// ---------------------------------------------------------------------------

export async function convert(ctx: RequestContext, id: string) {
  const q = await getQuotationOrThrow(id);
  assertOutlet(ctx.auth, q.outlet_id);
  if (!canTransitionQuotation(q.status, 'converted')) throw ApiError.invalidTransition(q.status, 'converted', 'quotation');
  return convertToWorkOrder(ctx, q);
}

export function assertCanReadQuotation(ctx: RequestContext, q: Quotation): void {
  assertOwnerOrOutletStaff(ctx.auth, q);
}

/** Mark the first PDF render (idempotent). */
export async function markPdfGenerated(q: Quotation): Promise<void> {
  if (q.pdf_generated_at) return;
  await getSupabase().from('quotations').update({ pdf_generated_at: new Date().toISOString() }).eq('id', q.id).is('pdf_generated_at', null);
}
