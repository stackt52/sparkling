/** CUS-030..034: repair quotations. */
import { canTransitionQuotation } from '../domain/stateMachines.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { assertOutlet, assertOwner, assertOwnerOrOutletStaff } from '../middleware/auth.js';
import { ApiError } from '../middleware/errors.js';
import type { Quotation, RequestContext, Vehicle } from '../types.js';
import { audit } from './audit.js';
import { firstName, formatRand, notify } from './notifications.js';
import { convertQuotation as convertToWorkOrder } from './workflow.js';

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

export async function getQuotationOrThrow(id: string): Promise<Quotation> {
  const q = unwrap<Quotation | null>(await getSupabase().from('quotations').select('*').eq('id', id).maybeSingle(), 'quotation');
  if (!q) throw ApiError.notFound('Quotation');
  return q;
}

export async function quote(ctx: RequestContext, id: string, input: { amount_cents: number; line_items: Array<{ label: string; amount_cents: number }>; valid_until: string }): Promise<Quotation> {
  const db = getSupabase();
  const q = await getQuotationOrThrow(id);
  assertOutlet(ctx.auth, q.outlet_id);
  if (!canTransitionQuotation(q.status, 'quoted')) throw ApiError.invalidTransition(q.status, 'quoted', 'quotation');
  const sum = input.line_items.reduce((a, l) => a + l.amount_cents, 0);
  if (input.line_items.length && sum !== input.amount_cents) throw ApiError.validation('line_items must sum to amount_cents', { sum, amount_cents: input.amount_cents });
  const updated = unwrap<Quotation>(
    await db
      .from('quotations')
      .update({ status: 'quoted', amount_cents: input.amount_cents, line_items: input.line_items, valid_until: input.valid_until, assessor_id: ctx.auth.uid, quoted_at: new Date().toISOString() })
      .eq('id', id)
      .select('*')
      .single(),
    'quote',
  );
  const customer = unwrap<{ full_name: string | null } | null>(await db.from('profiles').select('full_name').eq('id', q.customer_id).maybeSingle(), 'customer');
  await notify({
    recipientId: q.customer_id,
    templateKey: 'quote_ready',
    // `first_name` + `quotation_id` feed the Twilio quote_ready Content template ({"1":"first_name","2":"quotation_id"}).
    vars: { ref: q.ref, amount: formatRand(input.amount_cents), first_name: firstName(customer?.full_name), quotation_id: q.id },
    dedupeKey: `quote_ready:${q.id}:${updated.quoted_at}`,
    payload: { type: 'quotation', quotation_id: q.id },
  });
  await audit(ctx, { action: 'quotation.quote', entity_type: 'quotation', entity_id: id, outlet_id: q.outlet_id, after: { amount_cents: input.amount_cents } });
  return updated;
}

export async function decide(ctx: RequestContext, id: string, decision: 'accept' | 'decline', note?: string | null): Promise<Quotation> {
  const db = getSupabase();
  const q = await getQuotationOrThrow(id);
  assertOwner(ctx.auth, q);
  const to = decision === 'accept' ? 'accepted' : 'declined';
  if (!canTransitionQuotation(q.status, to)) throw ApiError.invalidTransition(q.status, to, 'quotation');
  if (to === 'accepted' && q.valid_until && new Date(q.valid_until) < new Date(new Date().toDateString())) {
    await db.from('quotations').update({ status: 'expired' }).eq('id', id);
    throw ApiError.invalidTransition('expired', 'accepted', 'quotation');
  }
  const updated = unwrap<Quotation>(
    await db.from('quotations').update({ status: to, decided_at: new Date().toISOString(), decision_by: ctx.auth.uid, decision_note: note ?? null }).eq('id', id).select('*').single(),
    'decision',
  );
  await audit(ctx, { action: `quotation.${to}`, entity_type: 'quotation', entity_id: id, outlet_id: q.outlet_id, after: { note } });
  return updated;
}

export async function convert(ctx: RequestContext, id: string) {
  const q = await getQuotationOrThrow(id);
  assertOutlet(ctx.auth, q.outlet_id);
  if (!canTransitionQuotation(q.status, 'converted')) throw ApiError.invalidTransition(q.status, 'converted', 'quotation');
  return convertToWorkOrder(ctx, q);
}

export function assertCanReadQuotation(ctx: RequestContext, q: Quotation): void {
  assertOwnerOrOutletStaff(ctx.auth, q);
}
