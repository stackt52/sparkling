import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { readDimensions, sniffImage } from '../src/lib/images.js';
import { quotationPhotoPath, setObjectStorageForTests } from '../src/lib/storage.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { setWhatsAppAdapterForTests, type WhatsAppSendInput } from '../src/lib/whatsapp.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { buildQuotationPdf } from '../src/services/quotationPdf.js';
import { MAX_PHOTOS_PER_QUOTATION } from '../src/services/quotationPhotos.js';
import { decide, publicQuoteUrl, PUBLIC_TOKEN_TTL_DAYS, quoteExpired, raiseQuotation } from '../src/services/quotations.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';
import { MemoryObjectStorage } from './helpers/fakeStorage.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const OTHER_OUTLET = 'a0000000-0000-4000-8000-000000000002';
const VEH_1 = 'd0000000-0000-4000-8000-000000000001';
const VEH_2 = 'd0000000-0000-4000-8000-000000000002';
const SVC_BODY = 'b0000000-0000-4000-8000-000000000009';
const BASE_URL = 'https://admin.example.test';
const PNG_1x1 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const JPEG_HEADER = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]), Buffer.from('JFIF\0'), Buffer.alloc(40)]);

let db: FakeSupabase;
let storage: MemoryObjectStorage;
let server: Server;
let base: string;
let waSends: WhatsAppSendInput[] = [];

beforeAll(async () => {
  process.env.PUBLIC_WEB_BASE_URL = BASE_URL;
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { cust: 'cust_1', other: 'cust_2', sup: 'sup_1', sup2: 'sup_2', tech: 'tech_1', outsider: 'sup_other' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
});
afterAll(() => {
  server.close();
  delete process.env.PUBLIC_WEB_BASE_URL;
  setWhatsAppAdapterForTests(null);
  setObjectStorageForTests(null);
});

beforeEach(() => {
  process.env.PUBLIC_WEB_BASE_URL = BASE_URL;
  db = fakeSupabase();
  storage = new MemoryObjectStorage();
  waSends = [];
  db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: true }, { key: 'auto_assignment', enabled: false }]);
  const p = (id: string, role: string, full_name: string, extra: Record<string, unknown> = {}) => ({ id, role, full_name, email: `${id}@example.com`, phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false, ...extra });
  db.seed('profiles', [
    p('sup_1', 'supervisor', 'Johan Botha'),
    p('sup_2', 'supervisor', 'Lerato Dube'),
    p('tech_1', 'technician', 'Pieter van der Merwe'),
    p('sup_other', 'supervisor', 'Elsewhere Person'),
    p('cust_1', 'customer', 'naledi mokoena', { phone: '+27831112222' }),
    p('cust_2', 'customer', 'Someone Else', { phone: '+27839998888' }),
    p('cust_inactive', 'customer', 'Gone Customer', { is_active: false }),
  ]);
  db.seed('staff_outlets', [
    { profile_id: 'sup_1', outlet_id: OUTLET },
    { profile_id: 'sup_2', outlet_id: OUTLET },
    { profile_id: 'tech_1', outlet_id: OUTLET },
    { profile_id: 'sup_other', outlet_id: OTHER_OUTLET },
  ]);
  db.seed('outlets', [
    { id: OUTLET, name: 'Sparkling Sandton', phone: '+27 11 000 0000', address_line: '12 Rivonia Rd', city: 'Sandton', email: 'sandton@sparkling.co.za', is_active: true },
    { id: OTHER_OUTLET, name: 'Sparkling Rosebank', is_active: true },
  ]);
  db.seed('services', [{ id: SVC_BODY, name: 'Panel beating', category: 'auto_body', is_active: true, is_quote_based: true }]);
  db.seed('vehicles', [
    { id: VEH_1, customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', colour: 'Red', vin: 'JS1234567890ABCDE', year: 2021, is_active: true },
    { id: VEH_2, customer_id: 'cust_2', registration_no: 'CA 123 456', make: 'VW', model: 'Polo', is_active: true },
  ]);
  db.seed('notification_templates', [
    { key: 'quote_ready', channel: 'push', title: 'Your quotation is ready', body: '{{ref}}: R {{amount}}. Review it in the app.', is_promotional: false, is_active: true, provider: null, provider_template_sid: null, provider_variables: {} },
    { key: 'quote_ready', channel: 'whatsapp', title: null, body: 'Hi {{first_name}}, your Sparkling quotation {{ref}} is ready: {{public_url}}', is_promotional: false, is_active: true, provider: 'twilio', provider_template_sid: 'HX011c7f1b31697f8e21d36ff6b4d02b06', provider_variables: { '1': 'first_name', '2': 'public_token' } },
    { key: 'quote_decided', channel: 'push', title: 'Quotation {{decision}}', body: '{{ref}} {{decision}} by {{customer}}', is_promotional: false, is_active: true },
    { key: 'quote_decision_receipt', channel: 'push', title: 'Quotation {{decision}}', body: 'Thanks {{first_name}}, quotation {{ref}} was {{decision}}.', is_promotional: false, is_active: true },
    { key: 'quote_decision_receipt', channel: 'whatsapp', title: null, body: 'Thanks {{first_name}}, quotation {{ref}} was {{decision}}.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [{ profile_id: 'cust_1', token: 'tok_c1', platform: 'android', app: 'customer' }, { profile_id: 'sup_1', token: 'tok_s1', platform: 'ios', app: 'staff' }, { profile_id: 'sup_2', token: 'tok_s2', platform: 'ios', app: 'staff' }]);
  setSupabaseClient(db as any);
  setObjectStorageForTests(storage);
  setWhatsAppAdapterForTests({
    name: 'fake',
    send: async (input) => {
      waSends.push(input);
      return { provider_ref: `SM${waSends.length}`, status: 'sent', provider_status: 'queued' };
    },
  });
  invalidateFlags();
  resetRateLimits();
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});

async function call(path: string, token: string | null, init: RequestInit = {}) {
  const headers: Record<string, string> = { ...(init.headers as Record<string, string> | undefined) };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (init.body && typeof init.body === 'string') headers['Content-Type'] = 'application/json';
  const res = await fetch(`${base}${path}`, { ...init, headers });
  const ct = res.headers.get('content-type') ?? '';
  const body = ct.includes('application/json') ? await res.json() : Buffer.from(await res.arrayBuffer());
  return { status: res.status, headers: res.headers, body: body as any };
}

function raiseBody(overrides: Record<string, unknown> = {}) {
  return {
    customer_id: 'cust_1',
    vehicle_id: VEH_1,
    outlet_id: OUTLET,
    category: 'Bumper',
    description: 'Rear bumper scuffed and cracked on the left corner.',
    items: [
      { label: 'Bumper repair & respray', description: 'Left corner', category: 'Bumper', service_id: SVC_BODY, amount_cents: 120000 },
      { label: 'Blend to quarter panel', amount_cents: 30000 },
    ],
    valid_until: futureDate(14),
    items_note: 'Excludes hidden damage found on strip-down.',
    client_op_id: `op-${Math.random().toString(36).slice(2)}`,
    ...overrides,
  };
}

function futureDate(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

async function raise(overrides: Record<string, unknown> = {}, token = 'sup') {
  const r = await call('/v1/quotations', token, { method: 'POST', body: JSON.stringify(raiseBody(overrides)) });
  expect(r.status).toBe(201);
  return r.body.quotation as Record<string, any>;
}

function dbQuote(id: string) {
  return db.rows('quotations').find((q) => q.id === id)!;
}

async function uploadPhoto(quotationId: string, token: string, bytes: Buffer, opts: { caption?: string; field?: string; type?: string } = {}) {
  const fd = new FormData();
  fd.append(opts.field ?? 'photo', new Blob([bytes], { type: opts.type ?? 'image/png' }), 'damage.png');
  if (opts.caption) fd.append('caption', opts.caption);
  return call(`/v1/quotations/${quotationId}/photos`, token, { method: 'POST', body: fd });
}

// ---------------------------------------------------------------------------

describe('image sniffing', () => {
  it('detects jpeg/png/webp/heic by magic bytes and rejects everything else', () => {
    expect(sniffImage(PNG_1x1)).toEqual({ mime: 'image/png', ext: 'png' });
    expect(sniffImage(JPEG_HEADER)).toEqual({ mime: 'image/jpeg', ext: 'jpg' });
    expect(sniffImage(Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WEBPVP8 ')]))).toEqual({ mime: 'image/webp', ext: 'webp' });
    expect(sniffImage(Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypheic'), Buffer.alloc(8)]))).toEqual({ mime: 'image/heic', ext: 'heic' });
    expect(sniffImage(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'))).toBeNull();
    expect(sniffImage(Buffer.from('%PDF-1.4 ...........'))).toBeNull();
    expect(sniffImage(Buffer.alloc(3))).toBeNull();
    expect(readDimensions(PNG_1x1)).toEqual({ width: 1, height: 1 });
    expect(readDimensions(Buffer.from('not an image at all'))).toEqual({ width: null, height: null });
  });

  it('quoteExpired compares valid_until against today (UTC date)', () => {
    expect(quoteExpired({ status: 'quoted', valid_until: futureDate(1) })).toBe(false);
    expect(quoteExpired({ status: 'quoted', valid_until: new Date().toISOString().slice(0, 10) })).toBe(false);
    expect(quoteExpired({ status: 'quoted', valid_until: futureDate(-1) })).toBe(true);
    expect(quoteExpired({ status: 'expired', valid_until: futureDate(5) })).toBe(true);
    expect(quoteExpired({ status: 'quoted', valid_until: null })).toBe(false);
  });
});

describe('POST /quotations — staff raise', () => {
  it('creates a quoted quotation with the item sum, a public token and sends quote_ready (push + Content template) with the public link', async () => {
    const before = Date.now();
    const q = await raise();
    expect(q.status).toBe('quoted');
    expect(q.amount_cents).toBe(150000);
    expect(q.items).toHaveLength(2);
    expect(q.items[0]).toEqual({ label: 'Bumper repair & respray', description: 'Left corner', category: 'Bumper', service_id: SVC_BODY, amount_cents: 120000 });
    expect(q.line_items).toEqual(q.items);
    expect(q.assessor_id).toBe('sup_1');
    expect(q.customer_id).toBe('cust_1');
    expect(q.items_note).toBe('Excludes hidden damage found on strip-down.');
    expect(typeof q.quoted_at).toBe('string');
    expect(q.public_token).toBeUndefined(); // never listed
    expect(q.attachments).toEqual([]);
    expect(q.pdf_url).toBe(`/v1/quotations/${q.id}/pdf`);
    expect(q.decision_source).toBeNull();

    const row = dbQuote(q.id);
    expect(row.public_token).toMatch(/^[0-9a-f-]{36}$/);
    expect(q.public_url).toBe(`${BASE_URL}/q/${row.public_token}`);
    const ttl = new Date(row.public_token_expires_at).getTime() - before;
    expect(ttl).toBeGreaterThan((PUBLIC_TOKEN_TTL_DAYS - 1) * 86_400_000);
    expect(ttl).toBeLessThanOrEqual(PUBLIC_TOKEN_TTL_DAYS * 86_400_000 + 5000);

    // notifications: push body + whatsapp Content variables {1: first_name, 2: public_token}
    const notes = db.rows('notifications').filter((n) => n.template_key === 'quote_ready');
    expect(notes.map((n) => [n.channel, n.status]).sort()).toEqual([['push', 'sent'], ['whatsapp', 'sent']]);
    const push = notes.find((n) => n.channel === 'push')!;
    expect(push.body).toBe(`${q.ref}: R 1 500.00. Review it in the app.`);
    expect(push.payload.vars).toMatchObject({ first_name: 'Naledi', ref: q.ref, amount: '1 500.00', public_token: row.public_token, public_url: q.public_url, quotation_id: q.id });
    expect(push.payload.url).toBe(q.public_url);
    const wa = notes.find((n) => n.channel === 'whatsapp')!;
    expect(wa.body).toBe(`Hi Naledi, your Sparkling quotation ${q.ref} is ready: ${q.public_url}`);
    expect(waSends).toHaveLength(1);
    expect(waSends[0].contentSid).toBe('HX011c7f1b31697f8e21d36ff6b4d02b06');
    expect(waSends[0].contentVariables).toEqual({ '1': 'Naledi', '2': row.public_token });

    const audit = db.rows('audit_events').find((a) => a.action === 'quotation.raise')!;
    expect(audit).toMatchObject({ actor_id: 'sup_1', entity_id: q.id, outlet_id: OUTLET, after: { amount_cents: 150000, items: 2, customer_id: 'cust_1', sent: true } });
  });

  it('omits the public link when PUBLIC_WEB_BASE_URL is empty', async () => {
    process.env.PUBLIC_WEB_BASE_URL = '';
    expect(publicQuoteUrl('abc')).toBeNull();
    const q = await raise();
    expect(q.public_url).toBeNull();
    const push = db.rows('notifications').find((n) => n.template_key === 'quote_ready' && n.channel === 'push')!;
    expect(push.payload.vars.public_url).toBeNull();
    expect(push.payload.url).toBeUndefined();
    const wa = db.rows('notifications').find((n) => n.template_key === 'quote_ready' && n.channel === 'whatsapp')!;
    expect(wa.body).toBe(`Hi Naledi, your Sparkling quotation ${q.ref} is ready: `);
    expect(waSends[0].contentVariables?.['2']).toBe(dbQuote(q.id).public_token);
  });

  it('send_to_customer:false skips the notification; the service is idempotent on client_op_id', async () => {
    const ctx = makeCtx('supervisor', 'sup_1', [OUTLET]);
    const input = { customerId: 'cust_1', vehicleId: VEH_1, outletId: OUTLET, category: 'Dent', description: 'Door ding on the driver door.', items: [{ label: 'PDR', amount_cents: 85000 }], validUntil: futureDate(7), clientOpId: 'op-fixed-1', sendToCustomer: false };
    const first = await raiseQuotation(ctx, input);
    expect(first.duplicate).toBe(false);
    expect(first.notification).toEqual([]);
    expect(db.rows('notifications')).toHaveLength(0);
    const again = await raiseQuotation(ctx, input);
    expect(again.duplicate).toBe(true);
    expect(again.quotation.id).toBe(first.quotation.id);
    expect(db.rows('quotations')).toHaveLength(1);
  });

  it('validates items, valid_until, customer, vehicle ownership and outlet scope', async () => {
    const post = (body: Record<string, unknown>, token = 'sup') => call('/v1/quotations', token, { method: 'POST', body: JSON.stringify(raiseBody(body)) });
    expect((await post({ items: [] })).status).toBe(400);
    expect((await post({ items: Array.from({ length: 21 }, () => ({ label: 'x', amount_cents: 1 })) })).status).toBe(400);
    expect((await post({ items: [{ label: 'x', amount_cents: -1 }] })).status).toBe(400);
    const past = await post({ valid_until: futureDate(-1) });
    expect(past.status).toBe(400);
    expect(JSON.stringify(past.body.error.details)).toContain('valid_until');
    expect((await post({ valid_until: 'tomorrow' })).status).toBe(400);
    expect((await post({ customer_id: 'nobody' })).status).toBe(404);
    expect((await post({ customer_id: 'cust_inactive' })).status).toBe(404);
    expect((await post({ customer_id: 'sup_2' })).status).toBe(404); // staff are not customers
    const wrongVehicle = await post({ vehicle_id: VEH_2 });
    expect(wrongVehicle.status).toBe(400);
    expect(wrongVehicle.body.error.details[0].path).toBe('vehicle_id');
    expect((await post({ outlet_id: OTHER_OUTLET })).status).toBe(403);
    expect((await post({}, 'outsider')).status).toBe(403);
    expect((await post({ items: [{ label: 'x', amount_cents: 1, service_id: 'b0000000-0000-4000-8000-0000000000ff' }] })).status).toBe(400);
    expect(db.rows('quotations')).toHaveLength(0);
  });

  it('keeps the customer request shape unchanged (status requested, no public link)', async () => {
    const r = await call('/v1/quotations', 'cust', { method: 'POST', body: JSON.stringify({ vehicle_id: VEH_1, outlet_id: OUTLET, category: 'Dent', description: 'Door ding on driver door.', client_op_id: 'op-cust-1' }) });
    expect(r.status).toBe(201);
    expect(r.body.quotation.status).toBe('requested');
    expect(r.body.quotation.amount_cents).toBeNull();
    expect(r.body.quotation.public_url).toBeUndefined();
    expect(r.body.quotation.public_token).toBeUndefined();
    expect(r.body.quotation.items).toEqual([]);
    expect(dbQuote(r.body.quotation.id).public_token ?? null).toBeNull();
    expect(db.rows('notifications')).toHaveLength(0);
    // a customer sending the staff shape is treated as a request (items ignored, customer_id ignored)
    const staffShape = await call('/v1/quotations', 'cust', { method: 'POST', body: JSON.stringify(raiseBody({ customer_id: 'cust_2', client_op_id: 'op-cust-2' })) });
    expect(staffShape.status).toBe(201);
    expect(staffShape.body.quotation.status).toBe('requested');
    expect(staffShape.body.quotation.customer_id).toBe('cust_1');
  });
});

describe('GET /quotations and /quotations/:id', () => {
  it('exposes items, attachments, decision fields, pdf_url; public_url to staff only; never the token', async () => {
    const q = await raise();
    await uploadPhoto(q.id, 'sup', PNG_1x1, { caption: 'Left corner' });
    const staff = await call(`/v1/quotations/${q.id}`, 'sup');
    expect(staff.status).toBe(200);
    expect(staff.body.public_url).toBe(q.public_url);
    expect(staff.body.public_token).toBeUndefined();
    expect(staff.body.items).toHaveLength(2);
    expect(staff.body.attachments).toHaveLength(1);
    expect(staff.body.attachments[0]).toMatchObject({ kind: 'damage_photo', caption: 'Left corner', width: 1, height: 1, mime_type: 'image/png', url: `/v1/quotations/${q.id}/photos/${staff.body.attachments[0].id}` });
    expect(staff.body.pdf_url).toBe(`/v1/quotations/${q.id}/pdf`);
    expect(staff.body.decision_source).toBeNull();
    expect(staff.body.decision_by_name).toBeNull();
    expect(staff.body.work_order).toBeNull();

    const mine = await call(`/v1/quotations/${q.id}`, 'cust');
    expect(mine.status).toBe(200);
    expect(mine.body.public_url).toBeUndefined();
    expect(mine.body.public_token).toBeUndefined();
    expect(mine.body.attachments).toHaveLength(1);
    expect((await call(`/v1/quotations/${q.id}`, 'other')).status).toBe(403);

    const list = await call('/v1/quotations', 'sup');
    expect(list.status).toBe(200);
    expect(list.body.data[0].items).toHaveLength(2);
    expect(list.body.data[0].attachments).toHaveLength(1);
    expect(list.body.data[0].public_url).toBe(q.public_url);
    expect(list.body.data[0].public_token).toBeUndefined();
    const custList = await call('/v1/quotations', 'cust');
    expect(custList.body.data[0].public_url).toBeUndefined();
  });
});

describe('damage photos', () => {
  it('uploads a sniffed image to storage, records the attachment and streams it back privately', async () => {
    const q = await raise();
    const up = await uploadPhoto(q.id, 'cust', PNG_1x1, { caption: 'Scuff', type: 'application/octet-stream' });
    expect(up.status).toBe(201);
    const att = up.body.attachment;
    expect(att).toMatchObject({ kind: 'damage_photo', mime_type: 'image/png', size_bytes: PNG_1x1.length, width: 1, height: 1, caption: 'Scuff', url: `/v1/quotations/${q.id}/photos/${att.id}` });
    const path = quotationPhotoPath(q.id, att.id, 'png');
    expect(storage.objects.get(path)?.contentType).toBe('image/png');
    expect(storage.objects.get(path)?.data.equals(PNG_1x1)).toBe(true);
    const row = db.rows('attachments').find((a) => a.id === att.id)!;
    expect(row).toMatchObject({ entity_type: 'quotation', entity_id: q.id, storage_path: path, kind: 'damage_photo', uploaded_by: 'cust_1', width: 1, height: 1 });
    expect(db.rows('audit_events').some((a) => a.action === 'quotation.photo_add' && a.entity_id === q.id)).toBe(true);

    const get = await call(att.url, 'sup');
    expect(get.status).toBe(200);
    expect(get.headers.get('content-type')).toBe('image/png');
    expect(get.headers.get('cache-control')).toBe('private, max-age=3600');
    expect(Buffer.from(get.body).equals(PNG_1x1)).toBe(true);
    expect((await call(att.url, 'cust')).status).toBe(200);
    expect((await call(att.url, 'other')).status).toBe(403);
    expect((await call(att.url, 'outsider')).status).toBe(403);
    expect((await call(att.url, null)).status).toBe(401);
    expect((await call(`/v1/quotations/${q.id}/photos/00000000-0000-4000-8000-000000000000`, 'sup')).status).toBe(404);
  });

  it('rejects non-image payloads, wrong fields, other people and refuses once decided', async () => {
    const q = await raise();
    const bad = await uploadPhoto(q.id, 'sup', Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'), { type: 'image/png' });
    expect(bad.status).toBe(400);
    expect(bad.body.error.message).toMatch(/Unsupported image type/);
    expect(storage.objects.size).toBe(0);
    expect((await uploadPhoto(q.id, 'sup', PNG_1x1, { field: 'file' })).status).toBe(400);
    const noFile = await call(`/v1/quotations/${q.id}/photos`, 'sup', { method: 'POST', body: JSON.stringify({ caption: 'x' }) });
    expect(noFile.status).toBe(400);
    expect((await uploadPhoto(q.id, 'other', PNG_1x1)).status).toBe(403);
    expect((await uploadPhoto(q.id, 'outsider', PNG_1x1)).status).toBe(403);
    expect(db.rows('attachments')).toHaveLength(0);

    await decide(makeCtx('customer', 'cust_1'), q.id, 'accept');
    const after = await uploadPhoto(q.id, 'sup', PNG_1x1);
    expect(after.status).toBe(409);
    expect(after.body.error.details.status).toBe('accepted');
  });

  it('caps a quotation at 10 photos', async () => {
    const q = await raise();
    for (let i = 0; i < MAX_PHOTOS_PER_QUOTATION; i++) expect((await uploadPhoto(q.id, 'sup', PNG_1x1)).status).toBe(201);
    const eleventh = await uploadPhoto(q.id, 'sup', PNG_1x1);
    expect(eleventh.status).toBe(409);
    expect(eleventh.body.error.details).toEqual({ count: 10, max: 10 });
    expect(storage.objects.size).toBe(10);
  });

  it('DELETE removes the object and the row (staff, before decision)', async () => {
    const q = await raise();
    const att = (await uploadPhoto(q.id, 'sup', PNG_1x1)).body.attachment;
    expect((await call(att.url, 'cust', { method: 'DELETE' })).status).toBe(403);
    expect((await call(att.url, 'outsider', { method: 'DELETE' })).status).toBe(403);
    const del = await call(att.url, 'tech', { method: 'DELETE' });
    expect(del.status).toBe(204);
    expect(storage.objects.size).toBe(0);
    expect(db.rows('attachments')).toHaveLength(0);
    expect(db.rows('audit_events').some((a) => a.action === 'quotation.photo_delete')).toBe(true);
    expect((await call(att.url, 'sup', { method: 'DELETE' })).status).toBe(404);

    const att2 = (await uploadPhoto(q.id, 'sup', PNG_1x1)).body.attachment;
    await decide(makeCtx('customer', 'cust_1'), q.id, 'decline');
    expect((await call(att2.url, 'sup', { method: 'DELETE' })).status).toBe(409);
    expect(storage.objects.size).toBe(1);
  });
});

describe('POST /quotations/:id/share', () => {
  it('rotates the token, re-sends quote_ready, audits and is limited to once a minute', async () => {
    const q = await raise();
    const oldToken = dbQuote(q.id).public_token;
    const tooSoon = await call(`/v1/quotations/${q.id}/share`, 'sup', { method: 'POST' });
    expect(tooSoon.status).toBe(429);
    expect(tooSoon.body.error.code).toBe('rate_limited');
    expect(dbQuote(q.id).public_token).toBe(oldToken);

    for (const n of db.rows('notifications')) n.created_at = new Date(Date.now() - 90_000).toISOString();
    const share = await call(`/v1/quotations/${q.id}/share`, 'sup', { method: 'POST' });
    expect(share.status).toBe(200);
    const newToken = dbQuote(q.id).public_token;
    expect(newToken).not.toBe(oldToken);
    expect(share.body.public_url).toBe(`${BASE_URL}/q/${newToken}`);
    expect(new Date(share.body.expires_at).getTime()).toBeGreaterThan(Date.now() + 29 * 86_400_000);
    expect(share.body.notification.map((n: any) => [n.channel, n.status]).sort()).toEqual([['push', 'sent'], ['whatsapp', 'sent']]);
    expect(share.body.quotation.public_token).toBeUndefined();
    expect(db.rows('notifications').filter((n) => n.template_key === 'quote_ready')).toHaveLength(4);
    expect(waSends[1].contentVariables?.['2']).toBe(newToken);
    expect(db.rows('audit_events').filter((a) => a.action === 'quotation.share')).toHaveLength(1);

    expect((await call(`/v1/quotations/${q.id}/share`, 'sup', { method: 'POST' })).status).toBe(429);
    // the old link is dead, the new one works
    expect((await call(`/v1/public/quotations/${oldToken}`, null)).status).toBe(404);
    expect((await call(`/v1/public/quotations/${newToken}`, null)).status).toBe(200);
  });

  it('is staff-only, outlet-scoped and refuses non-quoted quotations', async () => {
    const q = await raise();
    expect((await call(`/v1/quotations/${q.id}/share`, 'cust', { method: 'POST' })).status).toBe(403);
    expect((await call(`/v1/quotations/${q.id}/share`, 'outsider', { method: 'POST' })).status).toBe(403);
    await decide(makeCtx('customer', 'cust_1'), q.id, 'accept');
    const decided = await call(`/v1/quotations/${q.id}/share`, 'sup', { method: 'POST' });
    expect(decided.status).toBe(409);
    expect(decided.body.error.details.status).toBe('accepted');
  });
});

describe('PDF', () => {
  it('GET /quotations/:id/pdf returns a PDF attachment for owner and staff and stamps pdf_generated_at once', async () => {
    const q = await raise();
    await uploadPhoto(q.id, 'sup', PNG_1x1, { caption: 'Scuff' });
    expect(dbQuote(q.id).pdf_generated_at ?? null).toBeNull();
    const r = await call(`/v1/quotations/${q.id}/pdf`, 'cust');
    expect(r.status).toBe(200);
    expect(r.headers.get('content-type')).toBe('application/pdf');
    expect(r.headers.get('content-disposition')).toBe(`attachment; filename="${q.ref}.pdf"`);
    expect(Buffer.from(r.body).subarray(0, 5).toString()).toBe('%PDF-');
    expect(Number(r.headers.get('content-length'))).toBe(Buffer.from(r.body).length);
    const stamped = dbQuote(q.id).pdf_generated_at;
    expect(typeof stamped).toBe('string');
    expect(storage.calls.some((c) => c.op === 'get')).toBe(true); // thumbnail fetched

    expect((await call(`/v1/quotations/${q.id}/pdf`, 'sup')).status).toBe(200);
    expect(dbQuote(q.id).pdf_generated_at).toBe(stamped);
    expect((await call(`/v1/quotations/${q.id}/pdf`, 'other')).status).toBe(403);
    expect((await call(`/v1/quotations/${q.id}/pdf`, null)).status).toBe(401);
  });

  it('builder tolerates missing photos, missing base URL and every status', async () => {
    const q = { ...dbQuote((await raise()).id) } as any;
    const broken = { id: 'x', entity_type: 'quotation', entity_id: q.id, storage_path: 'nope', mime_type: 'image/jpeg', size_bytes: 1, sha256: null, uploaded_by: null, kind: 'damage_photo', width: 1, height: 1, caption: null, created_at: '' } as any;
    for (const status of ['quoted', 'accepted', 'declined', 'expired', 'converted']) {
      const pdf = await buildQuotationPdf({
        quotation: { ...q, status, decided_at: status === 'accepted' ? new Date().toISOString() : null, decision_by_name: 'Naledi', decision_source: 'public_link', decision_note: 'ok' },
        outlet: null,
        customer: null,
        vehicle: null,
        attachments: [broken],
        publicUrl: status === 'quoted' ? null : `${BASE_URL}/q/${q.public_token}`,
        loadPhoto: async () => {
          throw new Error('boom');
        },
      });
      expect(pdf.subarray(0, 5).toString()).toBe('%PDF-');
    }
  });
});

describe('public quote page', () => {
  it('GET /public/quotations/:token returns the documented view without PII', async () => {
    const q = await raise();
    const att = (await uploadPhoto(q.id, 'sup', PNG_1x1, { caption: 'Scuff' })).body.attachment;
    const token = dbQuote(q.id).public_token;
    const r = await call(`/v1/public/quotations/${token}`, null, { headers: { Origin: 'https://admin.example.test' } });
    expect(r.status).toBe(200);
    expect(r.headers.get('access-control-allow-origin')).toBe('https://admin.example.test');
    expect(r.headers.get('cache-control')).toBe('private, no-store');
    expect(r.body).toEqual({
      ref: q.ref,
      status: 'quoted',
      outlet: { name: 'Sparkling Sandton', phone: '+27 11 000 0000', address_line: '12 Rivonia Rd', city: 'Sandton', legal_name: null, trading_as: null, company_registration_no: null, vat_number: null, registered_office: null, bank_details: null },
      customer: { first_name: 'Naledi' },
      vehicle: { registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', colour: 'Red' },
      items: q.items,
      amount_cents: 150000,
      currency: 'ZAR',
      valid_until: q.valid_until,
      quoted_at: q.quoted_at,
      decided_at: null,
      decision_source: null,
      expired: false,
      can_decide: true,
      attachments: [{ id: att.id, url: `/v1/public/quotations/${token}/photos/${att.id}`, caption: 'Scuff', width: 1, height: 1 }],
      pdf_url: `/v1/public/quotations/${token}/pdf`,
      notes: 'Excludes hidden damage found on strip-down.',
      terms: expect.stringContaining('hidden or latent defects'),
    });
    const text = JSON.stringify(r.body);
    expect(text).not.toContain('mokoena');
    expect(text).not.toContain('+27831112222');
    expect(text).not.toContain('cust_1@example.com');
    expect(text).not.toContain('sup_1');
    expect(text).not.toContain(q.id);

    // preflight from the admin origin
    const pre = await fetch(`${base}/v1/public/quotations/${token}/decision`, { method: 'OPTIONS', headers: { Origin: 'https://admin.example.test', 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'content-type' } });
    expect(pre.status).toBe(204);
    expect(pre.headers.get('access-control-allow-methods')).toContain('POST');

    // photo + pdf through the token
    const photo = await call(r.body.attachments[0].url, null);
    expect(photo.status).toBe(200);
    expect(photo.headers.get('content-type')).toBe('image/png');
    expect(photo.headers.get('cache-control')).toBe('private, max-age=3600');
    const pdf = await call(r.body.pdf_url, null);
    expect(pdf.status).toBe(200);
    expect(pdf.headers.get('content-type')).toBe('application/pdf');
    expect(Buffer.from(pdf.body).subarray(0, 4).toString()).toBe('%PDF');
    expect((await call(`/v1/public/quotations/${token}/photos/00000000-0000-4000-8000-000000000000`, null)).status).toBe(404);
    expect((await call(`/v1/public/quotations/${token}/nope`, null)).status).toBe(404);
  });

  it('404 for unknown tokens, 410 with {ref,status} once the link expired', async () => {
    const q = await raise();
    expect((await call('/v1/public/quotations/00000000-0000-4000-8000-00000000dead', null)).status).toBe(404);
    expect((await call('/v1/public/quotations/not-a-token', null)).status).toBe(404);
    expect((await call('/v1/public/quotations/QT-2026-0041', null)).status).toBe(404);
    const token = dbQuote(q.id).public_token;
    dbQuote(q.id).public_token_expires_at = new Date(Date.now() - 1000).toISOString();
    const gone = await call(`/v1/public/quotations/${token}`, null);
    expect(gone.status).toBe(410);
    expect(gone.body.error).toMatchObject({ code: 'gone', details: { ref: q.ref, status: 'quoted' } });
    expect((await call(`/v1/public/quotations/${token}/pdf`, null)).status).toBe(410);
    expect((await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'accept' }) })).status).toBe(410);
  });

  it('accepts once via the link: sets decision fields, audits IP + UA, notifies outlet leads and the customer; later decisions conflict', async () => {
    const q = await raise();
    const token = dbQuote(q.id).public_token;
    waSends = [];
    const r = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'accept', note: 'Go ahead', accepted_by_name: 'Naledi Mokoena' }), headers: { 'User-Agent': 'QuotePage/1.0' } });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ref: q.ref, status: 'accepted', decision_source: 'public_link', can_decide: false, expired: false });
    expect(typeof r.body.decided_at).toBe('string');
    const row = dbQuote(q.id);
    expect(row).toMatchObject({ status: 'accepted', decision_source: 'public_link', decision_by_name: 'Naledi Mokoena', decision_by: 'cust_1', decision_note: 'Go ahead' });

    const audit = db.rows('audit_events').find((a) => a.action === 'quotation.decision_public')!;
    expect(audit).toMatchObject({ actor_id: 'cust_1', actor_role: 'customer', entity_id: q.id, outlet_id: OUTLET, ip: expect.stringMatching(/127\.0\.0\.1$/), user_agent: 'QuotePage/1.0', outcome: 'ok' });
    expect(audit.after).toMatchObject({ decision: 'accept', status: 'accepted', accepted_by_name: 'Naledi Mokoena', ip: expect.stringMatching(/127\.0\.0\.1$/), user_agent: 'QuotePage/1.0' });

    const decided = db.rows('notifications').filter((n) => n.template_key === 'quote_decided');
    expect(decided.map((n) => n.recipient_id).sort()).toEqual(['sup_1', 'sup_2']); // assessor + outlet supervisor; technician excluded
    expect(decided[0].body).toBe(`${q.ref} accepted by naledi mokoena`);
    expect(decided.every((n) => n.status === 'sent')).toBe(true);
    const receipts = db.rows('notifications').filter((n) => n.template_key === 'quote_decision_receipt');
    expect(receipts.map((n) => [n.channel, n.status]).sort()).toEqual([['push', 'sent'], ['whatsapp', 'sent']]);
    expect(receipts[0].body).toBe(`Thanks Naledi, quotation ${q.ref} was accepted.`);
    expect(waSends).toHaveLength(1);
    expect(waSends[0].contentSid).toBeNull();

    // one-time: link again, then the app
    const again = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'decline' }) });
    expect(again.status).toBe(409);
    expect(again.body.error).toMatchObject({ code: 'conflict', details: { decided_at: row.decided_at, status: 'accepted' } });
    const inApp = await call(`/v1/quotations/${q.id}/decision`, 'cust', { method: 'POST', body: JSON.stringify({ decision: 'decline' }) });
    expect(inApp.status).toBe(409);
    expect(inApp.body.error.details).toEqual({ decided_at: row.decided_at, status: 'accepted' });
    expect(dbQuote(q.id).status).toBe('accepted');
    expect(db.rows('audit_events').filter((a) => a.action === 'quotation.decision_public')).toHaveLength(2);
    expect(db.rows('audit_events').filter((a) => a.action === 'quotation.decision_public')[1].outcome).toBe('refused');
    expect(db.rows('notifications').filter((n) => n.template_key === 'quote_decided')).toHaveLength(2);

    // still viewable
    const view = await call(`/v1/public/quotations/${token}`, null);
    expect(view.body.status).toBe('accepted');
    expect(view.body.can_decide).toBe(false);
  });

  it('declines via the link without a name; validates the body', async () => {
    const q = await raise();
    const token = dbQuote(q.id).public_token;
    expect((await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'maybe' }) })).status).toBe(400);
    expect((await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: '{bad json', headers: { 'Content-Type': 'application/json' } })).status).toBe(400);
    const r = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'decline' }) });
    expect(r.status).toBe(200);
    expect(r.body.status).toBe('declined');
    expect(dbQuote(q.id)).toMatchObject({ status: 'declined', decision_source: 'public_link', decision_by_name: 'naledi mokoena' });
    expect(db.rows('notifications').find((n) => n.template_key === 'quote_decided')?.body).toBe(`${q.ref} declined by naledi mokoena`);
  });

  it('in-app decision first → public link conflicts; app decision records decision_source app', async () => {
    const q = await raise();
    const token = dbQuote(q.id).public_token;
    const r = await call(`/v1/quotations/${q.id}/decision`, 'cust', { method: 'POST', body: JSON.stringify({ decision: 'accept' }) });
    expect(r.status).toBe(200);
    expect(r.body.quotation).toMatchObject({ status: 'accepted', decision_source: 'app', decision_by_name: 'naledi mokoena' });
    expect(r.body.quotation.public_token).toBeUndefined();
    const pub = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'accept' }) });
    expect(pub.status).toBe(409);
    expect(pub.body.error.details.status).toBe('accepted');
    expect((await call(`/v1/quotations/${q.id}/decision`, 'other', { method: 'POST', body: JSON.stringify({ decision: 'accept' }) })).status).toBe(403);
    expect(db.rows('notifications').filter((n) => n.template_key === 'quote_decided')).toHaveLength(2);
  });

  it('accepting after valid_until → 410 gone (status expired); declining a requested quotation → 409 invalid_transition', async () => {
    const q = await raise();
    const token = dbQuote(q.id).public_token;
    dbQuote(q.id).valid_until = futureDate(-2);
    const view = await call(`/v1/public/quotations/${token}`, null);
    expect(view.body).toMatchObject({ expired: true, can_decide: false, status: 'quoted' });
    const r = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'accept' }) });
    expect(r.status).toBe(410);
    expect(r.body.error).toMatchObject({ code: 'gone', details: { ref: q.ref, status: 'expired' } });
    expect(dbQuote(q.id).status).toBe('expired');
    expect(dbQuote(q.id).decided_at ?? null).toBeNull();
    const inApp = await call(`/v1/quotations/${q.id}/decision`, 'cust', { method: 'POST', body: JSON.stringify({ decision: 'accept' }) });
    expect(inApp.status).toBe(409);
    expect(inApp.body.error.code).toBe('invalid_transition');

    const req = await call('/v1/quotations', 'cust', { method: 'POST', body: JSON.stringify({ vehicle_id: VEH_1, outlet_id: OUTLET, category: 'Dent', description: 'Door ding on driver door.', client_op_id: 'op-cust-9' }) });
    const dec = await call(`/v1/quotations/${req.body.quotation.id}/decision`, 'cust', { method: 'POST', body: JSON.stringify({ decision: 'decline' }) });
    expect(dec.status).toBe(409);
    expect(dec.body.error.code).toBe('invalid_transition');
  });

  it('rate-limits per IP + token (60/min)', async () => {
    const q = await raise();
    const token = dbQuote(q.id).public_token;
    let limited = 0;
    for (let i = 0; i < 61; i++) {
      const r = await call(`/v1/public/quotations/${token}`, null);
      if (r.status === 429) limited++;
    }
    expect(limited).toBe(1);
    // a different token is a different bucket
    const q2 = await raise();
    expect((await call(`/v1/public/quotations/${dbQuote(q2.id).public_token}`, null)).status).toBe(200);
  });
});

describe('POST /quotations/:id/quote (supervisor quoting a request) also issues a public token', () => {
  it('sends quote_ready with public_token and the customer can decide via the link', async () => {
    const req = await call('/v1/quotations', 'cust', { method: 'POST', body: JSON.stringify({ vehicle_id: VEH_1, outlet_id: OUTLET, category: 'Dent', description: 'Door ding on driver door.', client_op_id: 'op-cust-5' }) });
    const id = req.body.quotation.id;
    const r = await call(`/v1/quotations/${id}/quote`, 'sup', { method: 'POST', body: JSON.stringify({ amount_cents: 85000, line_items: [{ label: 'PDR', amount_cents: 85000 }], valid_until: futureDate(10) }) });
    expect(r.status).toBe(200);
    expect(r.body.quotation.status).toBe('quoted');
    const token = dbQuote(id).public_token;
    expect(token).toMatch(/^[0-9a-f-]{36}$/);
    expect(r.body.quotation.public_url).toBe(`${BASE_URL}/q/${token}`);
    expect(waSends[0].contentVariables).toEqual({ '1': 'Naledi', '2': token });
    const pub = await call(`/v1/public/quotations/${token}/decision`, null, { method: 'POST', body: JSON.stringify({ decision: 'accept', accepted_by_name: 'N. Mokoena' }) });
    expect(pub.status).toBe(200);
    expect(pub.body.status).toBe('accepted');
  });
});
