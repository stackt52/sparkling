/** CUS-010..016: vehicles (manual + licence-disc scan). */
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import type { RequestContext, Vehicle } from '../types.js';
import { audit } from './audit.js';

export interface CreateVehicleInput {
  registration_no: string;
  vin?: string | null;
  make?: string | null;
  model?: string | null;
  colour?: string | null;
  year?: number | null;
  licence_no?: string | null;
  disc_expiry?: string | null;
  source: 'manual' | 'scan';
  disc_hash?: string | null;
  engine_no?: string | null;
  force?: boolean;
  client_op_id?: string | null;
}

export function normaliseReg(reg: string): string {
  return reg.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
}

export async function createVehicle(ctx: RequestContext, input: CreateVehicleInput): Promise<{ vehicle: Vehicle; duplicate: boolean }> {
  const db = getSupabase();
  const uid = ctx.auth.uid;
  const mine = unwrap<Vehicle[]>(await db.from('vehicles').select('*').eq('customer_id', uid).eq('is_active', true), 'vehicles');
  const reg = normaliseReg(input.registration_no);
  const dupReg = mine.find((v) => normaliseReg(v.registration_no) === reg);
  const dupVin = input.vin ? mine.find((v) => v.vin && v.vin.toUpperCase() === input.vin!.toUpperCase()) : undefined;
  const dup = dupReg ?? dupVin;
  if (dup) {
    // Same client op replay → return existing; otherwise 409 unless forced.
    if (input.client_op_id && dup.disc_hash && input.disc_hash && dup.disc_hash === input.disc_hash) return { vehicle: dup, duplicate: true };
    if (!input.force) {
      throw ApiError.conflict('A vehicle with this registration or VIN already exists', { existing_vehicle_id: dup.id, field: dupReg ? 'registration_no' : 'vin' });
    }
    if (dupReg) {
      // Registration is unique per customer (partial index) — update in place instead.
      const updated = unwrap<Vehicle>(
        await db.from('vehicles').update(sanitize(input)).eq('id', dupReg.id).select('*').single(),
        'vehicle update',
      );
      return { vehicle: updated, duplicate: true };
    }
  }
  const res = await db
    .from('vehicles')
    .insert({ customer_id: uid, ...sanitize(input), registration_no: input.registration_no.trim().toUpperCase(), source: input.source })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const existing = mine.find((v) => normaliseReg(v.registration_no) === reg);
      throw ApiError.conflict('A vehicle with this registration already exists', { existing_vehicle_id: existing?.id ?? null });
    }
    throw new DatabaseError(res.error, 'create vehicle');
  }
  const vehicle = res.data as Vehicle;
  await audit(ctx, { action: 'vehicle.create', entity_type: 'vehicle', entity_id: vehicle.id, after: { registration_no: vehicle.registration_no, source: vehicle.source } });
  return { vehicle, duplicate: false };
}

function sanitize(input: CreateVehicleInput): Partial<Vehicle> {
  const out: Partial<Vehicle> = {};
  if (input.vin !== undefined) out.vin = input.vin ? input.vin.toUpperCase() : null;
  if (input.make !== undefined) out.make = input.make;
  if (input.model !== undefined) out.model = input.model;
  if (input.colour !== undefined) out.colour = input.colour;
  if (input.year !== undefined) out.year = input.year;
  if (input.licence_no !== undefined) out.licence_no = input.licence_no;
  if (input.disc_expiry !== undefined) out.disc_expiry = input.disc_expiry;
  if (input.engine_no !== undefined) out.engine_no = input.engine_no;
  if (input.disc_hash !== undefined) out.disc_hash = input.disc_hash;
  if (input.source === 'scan') out.disc_verified = true;
  return out;
}
