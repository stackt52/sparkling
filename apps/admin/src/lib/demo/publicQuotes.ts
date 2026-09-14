/**
 * In-memory public quote store for NEXT_PUBLIC_DEMO_MODE=true — the demo counterpart of
 * `GET|POST /v1/public/quotations/:token`. Serves `/q/demo-quoted`, `/q/demo-accepted`,
 * `/q/demo-expired` and `/q/demo-missing`, plus any quote raised or shared through `DemoApi`
 * (which registers its live quotation objects here). Decisions are one-time and persisted in
 * localStorage so a reload — or the dashboard in another tab — shows the decided state.
 */
import { ApiRequestError } from '../api';
import { QUOTE_TERMS } from '../quoteTerms';
import type { Outlet, PublicDecisionInput, PublicQuotation, Quotation, QuotationStatus } from '../types';
import { DEMO_PROFILES, OUTLETS, QUOTATIONS, VEHICLES, daysAgo, nowIso } from './data';
import { buildQuotePdf, type QuotePdfInput } from './quotePdf';

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const delay = (ms = 160) => new Promise<void>((r) => setTimeout(r, ms));

interface Record_ {
  quotation: Quotation;
  expires_at: string;
}

const records = new Map<string, Record_>();
const SEED_ID = QUOTATIONS[0].id; // QT-2026-0041 · Thabo Nkosi · bumper repair
const DEFAULT_TTL_DAYS = 30;

export interface DemoDecision {
  status: Extract<QuotationStatus, 'accepted' | 'declined'>;
  decided_at: string;
  decision_by_name: string | null;
  note: string | null;
}

const decisionKey = (token: string) => `sparkling.demo.publicQuote.${token}`;

export function readDemoDecision(token: string): DemoDecision | null {
  try {
    const raw = localStorage.getItem(decisionKey(token));
    return raw ? (JSON.parse(raw) as DemoDecision) : null;
  } catch {
    return null;
  }
}
function writeDemoDecision(token: string, d: DemoDecision) {
  try {
    localStorage.setItem(decisionKey(token), JSON.stringify(d));
  } catch {
    /* storage unavailable */
  }
}

/** Applies a decision persisted by the public page to a live quotation object (no-op once decided). */
export function applyDemoDecision(q: Quotation, token: string | null | undefined): Quotation {
  if (!token || q.status !== 'quoted') return q;
  const d = readDemoDecision(token);
  if (!d) return q;
  Object.assign(q, { status: d.status, decided_at: d.decided_at, decision_source: 'public_link', decision_by_name: d.decision_by_name, decision_note: d.note });
  return q;
}

function seed() {
  if (records.size) return;
  const base = clone(QUOTATIONS[0]);
  records.set('demo-quoted', { quotation: base, expires_at: daysAgo(-DEFAULT_TTL_DAYS) });
  records.set('demo-accepted', {
    quotation: { ...clone(base), status: 'accepted', decided_at: daysAgo(0, 9), decision_source: 'public_link', decision_by_name: 'Thabo Nkosi', decision_note: 'Please go ahead — I can drop the car on Monday.' },
    expires_at: daysAgo(-DEFAULT_TTL_DAYS),
  });
  records.set('demo-expired', {
    quotation: { ...clone(base), ref: 'QT-2026-0033', status: 'expired', valid_until: daysAgo(3).slice(0, 10), quoted_at: daysAgo(17) },
    expires_at: daysAgo(3),
  });
}

/* ---- demo photo uploads: served to the public page as data URLs (memory first, then localStorage for other tabs) ---- */
const photoUrls = new Map<string, string>();
const photoKey = (attachmentId: string) => `sparkling.demo.photo.${attachmentId}`;
/** Registers an uploaded demo photo; small ones (≤ 600 KB) are also persisted so a new tab can show them. */
export function registerDemoPhoto(attachmentId: string, dataUrl: string) {
  photoUrls.set(attachmentId, dataUrl);
  if (dataUrl.length <= 600 * 1024) {
    try {
      localStorage.setItem(photoKey(attachmentId), dataUrl);
    } catch {
      /* quota — in-memory only */
    }
  }
}
export function demoPhotoUrl(attachmentId: string, fallback = '/demo/damage-1.svg'): string {
  const mem = photoUrls.get(attachmentId);
  if (mem) return mem;
  try {
    const stored = localStorage.getItem(photoKey(attachmentId));
    if (stored) {
      photoUrls.set(attachmentId, stored);
      return stored;
    }
  } catch {
    /* storage unavailable */
  }
  return fallback;
}

/* ---- raised / shared quotes are persisted so "Open link" in a new tab (fresh memory) still resolves ---- */
const recordKey = (token: string) => `sparkling.demo.publicQuote.record.${token}`;
function persistRecord(token: string, rec: Record_) {
  try {
    localStorage.setItem(recordKey(token), JSON.stringify(rec));
  } catch {
    /* storage unavailable */
  }
}
function restoreRecord(token: string): Record_ | null {
  try {
    const raw = localStorage.getItem(recordKey(token));
    return raw ? (JSON.parse(raw) as Record_) : null;
  } catch {
    return null;
  }
}

/** Called by DemoApi so a raised / shared quotation's public link resolves to its live object. */
export function registerDemoPublicQuote(token: string, quotation: Quotation, expiresAt = daysAgo(-DEFAULT_TTL_DAYS)) {
  seed();
  const rec = { quotation, expires_at: expiresAt };
  records.set(token, rec);
  if (!demoSeedToken(quotation.id)) persistRecord(token, rec);
}
/** Keeps the persisted copy in sync after photos are added / removed on a raised quote. */
export function syncDemoPublicQuote(quotation: Quotation) {
  for (const [token, rec] of records) if (rec.quotation === quotation && !demoSeedToken(quotation.id)) persistRecord(token, rec);
}

/** The token DemoApi hands out for the seed quotation (so the dashboard link opens `/q/demo-quoted`). */
export const demoSeedToken = (quotationId: string) => (quotationId === SEED_ID ? 'demo-quoted' : null);

/** Merges the outlet's legal / billing identity (migration 0007) into a quotation's embedded outlet. */
export function withOutletLegal<T extends Quotation['outlet']>(o: T, full: Outlet | undefined = OUTLETS.find((x) => x.id === o.id)): T {
  return {
    ...o,
    code: o.code ?? full?.code ?? null,
    phone: o.phone ?? full?.phone ?? null,
    email: o.email ?? full?.email ?? null,
    address_line: o.address_line ?? full?.address_line ?? null,
    city: o.city ?? full?.city ?? null,
    legal_name: o.legal_name ?? full?.legal_name ?? null,
    trading_as: o.trading_as ?? full?.trading_as ?? null,
    company_registration_no: o.company_registration_no ?? full?.company_registration_no ?? null,
    vat_number: o.vat_number ?? full?.vat_number ?? null,
    registered_office: o.registered_office ?? full?.registered_office ?? null,
    bank_details: o.bank_details ?? full?.bank_details ?? null,
  };
}

function toPublicView(q: Quotation, token: string, expiresAt: string): PublicQuotation {
  const outlet = withOutletLegal(q.outlet);
  const vehicle = VEHICLES.find((v) => v.id === q.vehicle.id);
  const today = new Date().toISOString().slice(0, 10);
  const expired = q.status === 'expired' || expiresAt < nowIso() || Boolean(q.valid_until && q.valid_until < today);
  const items = q.items ?? q.line_items;
  return {
    ref: q.ref,
    status: q.status,
    outlet: { name: outlet.name, code: outlet.code, phone: outlet.phone ?? null, email: outlet.email, address_line: outlet.address_line ?? null, city: outlet.city, legal_name: outlet.legal_name, trading_as: outlet.trading_as, company_registration_no: outlet.company_registration_no, vat_number: outlet.vat_number, registered_office: outlet.registered_office, bank_details: outlet.bank_details },
    customer: { first_name: q.customer_name.split(' ')[0] },
    vehicle: { registration_no: q.vehicle.registration_no, make: q.vehicle.make, model: q.vehicle.model, colour: q.vehicle.colour ?? vehicle?.colour ?? null },
    items,
    amount_cents: q.amount_cents ?? items.reduce((s, i) => s + i.amount_cents * (i.quantity ?? 1), 0),
    currency: 'ZAR',
    valid_until: q.valid_until,
    quoted_at: q.quoted_at,
    decided_at: q.decided_at,
    decision_source: q.decision_source ?? null,
    decision_by_name: q.decision_by_name ?? null,
    expired,
    can_decide: q.status === 'quoted' && !expired,
    attachments: q.attachments.map((a) => ({ id: a.id, url: a.url && !a.url.startsWith('/v1/') ? a.url : demoPhotoUrl(a.id), caption: a.caption ?? null, width: a.width ?? null, height: a.height ?? null })),
    pdf_url: `/demo/quotations/${token}.pdf`,
    notes: q.items_note ?? null,
    terms: QUOTE_TERMS,
  };
}

function lookup(token: string): Record_ {
  seed();
  let rec = records.get(token);
  if (!rec) {
    const restored = restoreRecord(token);
    if (restored) records.set(token, (rec = restored));
  }
  if (!rec) throw new ApiRequestError(404, { code: 'not_found', message: 'This quotation link is not valid' });
  applyDemoDecision(rec.quotation, token);
  const decided = ['accepted', 'declined', 'converted'].includes(rec.quotation.status);
  const view = toPublicView(rec.quotation, token, rec.expires_at);
  if (view.expired && !decided) throw new ApiRequestError(410, { code: 'gone', message: 'This quotation has expired', details: { ref: view.ref, status: rec.quotation.status } });
  return rec;
}

export async function getDemoPublicQuote(token: string): Promise<PublicQuotation> {
  await delay();
  const rec = lookup(token);
  return toPublicView(rec.quotation, token, rec.expires_at);
}

export async function decideDemoPublicQuote(token: string, body: PublicDecisionInput): Promise<PublicQuotation> {
  await delay(260);
  const rec = lookup(token);
  const q = rec.quotation;
  if (q.status !== 'quoted') throw new ApiRequestError(409, { code: 'conflict', message: 'This quotation has already been decided', details: { decided_at: q.decided_at, status: q.status } });
  const decision: DemoDecision = {
    status: body.decision === 'accept' ? 'accepted' : 'declined',
    decided_at: nowIso(),
    decision_by_name: body.accepted_by_name?.trim() || q.customer_name,
    note: body.note?.trim() || null,
  };
  Object.assign(q, { status: decision.status, decided_at: decision.decided_at, decision_source: 'public_link', decision_by_name: decision.decision_by_name, decision_note: decision.note });
  writeDemoDecision(token, decision);
  if (!demoSeedToken(q.id)) persistRecord(token, rec);
  return toPublicView(q, token, rec.expires_at);
}

export function pdfInputFromQuotation(q: Quotation, publicUrl?: string | null, outlets: Outlet[] = OUTLETS): QuotePdfInput {
  const vehicle = VEHICLES.find((v) => v.id === q.vehicle.id);
  const items = q.items ?? q.line_items;
  return {
    ref: q.ref,
    status: q.status,
    outlet: withOutletLegal(q.outlet, outlets.find((o) => o.id === q.outlet.id)),
    customer_name: q.customer_name,
    customer_phone: DEMO_PROFILES.find((p) => p.id === q.customer_id)?.phone ?? null,
    vehicle: { registration_no: q.vehicle.registration_no, make: q.vehicle.make, model: q.vehicle.model, colour: q.vehicle.colour ?? vehicle?.colour },
    items,
    amount_cents: q.amount_cents ?? items.reduce((s, i) => s + i.amount_cents * (i.quantity ?? 1), 0),
    valid_until: q.valid_until,
    quoted_at: q.quoted_at,
    decided_at: q.decided_at,
    decision_source: q.decision_source,
    decision_by_name: q.decision_by_name,
    notes: q.items_note,
    terms: q.terms ?? QUOTE_TERMS,
    public_url: publicUrl ?? q.public_url,
  };
}

export async function demoPublicPdf(token: string): Promise<Blob> {
  seed();
  const rec = records.get(token) ?? restoreRecord(token);
  if (!rec) throw new ApiRequestError(404, { code: 'not_found', message: 'This quotation link is not valid' });
  applyDemoDecision(rec.quotation, token);
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  return buildQuotePdf(pdfInputFromQuotation(rec.quotation, `${origin}/q/${token}`));
}
