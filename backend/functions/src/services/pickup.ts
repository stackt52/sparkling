/**
 * Vehicle collection (hand-over) OTP — replicates the legacy "car pick-up"
 * WhatsApp flow. The OTP is issued when the work order is verified (see
 * workflow.onVerified, which stores it on the work order), shown to the owning customer in the app / WhatsApp,
 * and presented to outlet staff who verify it here.
 */
import { canSeePickupOtp, otpMatches, redactPickupOtp } from '../lib/otp.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { assertOutlet } from '../middleware/auth.js';
import { ApiError } from '../middleware/errors.js';
import type { RequestContext, WorkOrder } from '../types.js';
import { audit } from './audit.js';
import { notify } from './notifications.js';
import { vehicleLabel } from './workflow.js';

export const PICKUP_OTP_MAX_ATTEMPTS = 5;
export const PICKUP_RESEND_INTERVAL_MS = 60_000;

export { canSeePickupOtp, redactPickupOtp };

async function loadForStaff(ctx: RequestContext, workOrderId: string): Promise<WorkOrder> {
  const wo = unwrap<WorkOrder | null>(await getSupabase().from('work_orders').select('*').eq('id', workOrderId).maybeSingle(), 'work order');
  if (!wo) throw ApiError.notFound('Work order');
  assertOutlet(ctx.auth, wo.outlet_id);
  return wo;
}

async function failedAttempts(workOrderId: string): Promise<number> {
  const rows = unwrap<Array<{ id: string }>>(await getSupabase().from('task_events').select('id').eq('work_order_id', workOrderId).eq('event', 'pickup_otp_failed'), 'otp attempts');
  return rows.length;
}

export interface VerifyPickupResult {
  work_order: WorkOrder;
  collected_at: string;
}

/**
 * Staff verify the OTP the customer presents. Wrong OTP → 409 `invalid_otp`
 * with `attempts_remaining`; after PICKUP_OTP_MAX_ATTEMPTS failures the work
 * order is locked (409 `conflict`, `locked:true`) until a manager intervenes.
 */
export async function verifyPickup(ctx: RequestContext, workOrderId: string, otp: string): Promise<VerifyPickupResult> {
  const db = getSupabase();
  const wo = await loadForStaff(ctx, workOrderId);
  if (wo.collected_at) throw ApiError.conflict('Vehicle has already been collected', { collected_at: wo.collected_at });
  if (!wo.pickup_otp) throw ApiError.conflict('No collection OTP has been issued for this work order (it must be verified first)', { status: wo.status });

  const task = await db.from('tasks').select('id').eq('work_order_id', wo.id).order('seq').limit(1).maybeSingle();
  const taskId = (task.data as { id: string } | null)?.id ?? null;
  const attempts = await failedAttempts(wo.id);
  if (attempts >= PICKUP_OTP_MAX_ATTEMPTS) {
    throw ApiError.conflict('OTP attempts exhausted for this work order', { locked: true, attempts, max_attempts: PICKUP_OTP_MAX_ATTEMPTS });
  }

  if (!otpMatches(wo.pickup_otp, otp)) {
    const attempt = attempts + 1;
    const remaining = Math.max(0, PICKUP_OTP_MAX_ATTEMPTS - attempt);
    await db.from('task_events').insert({
      task_id: taskId,
      work_order_id: wo.id,
      actor_id: ctx.auth.uid,
      event: 'pickup_otp_failed',
      metadata: { attempt, attempts_remaining: remaining, max_attempts: PICKUP_OTP_MAX_ATTEMPTS },
    });
    await audit(ctx, { action: 'work_order.pickup_otp_failed', entity_type: 'work_order', entity_id: wo.id, outlet_id: wo.outlet_id, after: { attempt, attempts_remaining: remaining }, outcome: 'failed' });
    throw ApiError.invalidOtp(remaining > 0 ? 'Incorrect OTP' : 'Incorrect OTP; attempts exhausted', { attempts_remaining: remaining, locked: remaining === 0 });
  }

  const now = new Date().toISOString();
  const updated = unwrap<WorkOrder>(
    await db.from('work_orders').update({ pickup_otp_verified_at: now, pickup_otp_verified_by: ctx.auth.uid, collected_at: now }).eq('id', wo.id).select('*').single(),
    'collect work order',
  );
  await db.from('task_events').insert({
    task_id: taskId,
    work_order_id: wo.id,
    actor_id: ctx.auth.uid,
    event: 'collected',
    from_status: wo.status,
    to_status: wo.status,
    metadata: { otp_attempts: attempts + 1 },
  });
  await audit(ctx, { action: 'work_order.collected', entity_type: 'work_order', entity_id: wo.id, outlet_id: wo.outlet_id, after: { collected_at: now, verified_by: ctx.auth.uid } });
  return { work_order: redactPickupOtp(ctx.auth, updated), collected_at: now };
}

export interface ResendPickupResult {
  work_order: WorkOrder;
  notification: Awaited<ReturnType<typeof notify>>;
  retry_after_seconds: number;
}

/** Re-sends the *same* OTP (push + WhatsApp `pickup_otp` template); at most once per minute per work order. */
export async function resendPickupOtp(ctx: RequestContext, workOrderId: string): Promise<ResendPickupResult> {
  const db = getSupabase();
  const wo = await loadForStaff(ctx, workOrderId);
  if (wo.collected_at) throw ApiError.conflict('Vehicle has already been collected', { collected_at: wo.collected_at });
  if (!wo.pickup_otp) throw ApiError.conflict('No collection OTP has been issued for this work order (it must be verified first)', { status: wo.status });

  const events = unwrap<Array<{ created_at: string }>>(
    await db.from('task_events').select('created_at').eq('work_order_id', wo.id).eq('event', 'pickup_otp_resent').order('created_at', { ascending: false }).limit(1),
    'otp resend events',
  );
  const lastSent = Math.max(events[0] ? new Date(events[0].created_at).getTime() : 0, wo.pickup_otp_issued_at ? new Date(wo.pickup_otp_issued_at).getTime() : 0);
  const elapsed = Date.now() - lastSent;
  if (elapsed < PICKUP_RESEND_INTERVAL_MS) {
    throw ApiError.rateLimited(`OTP was sent ${Math.round(elapsed / 1000)}s ago; try again in ${Math.ceil((PICKUP_RESEND_INTERVAL_MS - elapsed) / 1000)}s`);
  }

  const [outlet, task] = await Promise.all([
    db.from('outlets').select('name').eq('id', wo.outlet_id).maybeSingle(),
    db.from('tasks').select('id').eq('work_order_id', wo.id).order('seq').limit(1).maybeSingle(),
  ]);
  const stamp = new Date().toISOString();
  const notification = await notify({
    recipientId: wo.customer_id,
    templateKey: 'pickup_otp',
    vars: { otp: wo.pickup_otp, vehicle: await vehicleLabel(wo.vehicle_id), outlet: (outlet.data as { name: string } | null)?.name ?? '', ref: wo.ref },
    dedupeKey: `pickup_otp:${wo.id}:${stamp}`,
    payload: { type: 'work_order', work_order_id: wo.id, booking_id: wo.booking_id },
  });
  await db.from('task_events').insert({
    task_id: (task.data as { id: string } | null)?.id ?? null,
    work_order_id: wo.id,
    actor_id: ctx.auth.uid,
    event: 'pickup_otp_resent',
    metadata: { channels: notification.map((n) => `${n.channel}:${n.status}`) },
    created_at: stamp,
  });
  await audit(ctx, { action: 'work_order.pickup_otp_resend', entity_type: 'work_order', entity_id: wo.id, outlet_id: wo.outlet_id, after: { channels: notification.map((n) => `${n.channel}:${n.status}`) } });
  return { work_order: redactPickupOtp(ctx.auth, wo), notification, retry_after_seconds: PICKUP_RESEND_INTERVAL_MS / 1000 };
}
