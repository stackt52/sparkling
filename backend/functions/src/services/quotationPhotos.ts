/**
 * Damage photos on quotations (SEC-010): multipart upload → magic-byte sniff →
 * Cloud Storage `quotations/<quotation_id>/<attachment_id>.<ext>` → `attachments`
 * row (`kind:'damage_photo'`). Served only through the API.
 */
import { randomUUID } from 'node:crypto';
import { readDimensions, sniffImage } from '../lib/images.js';
import { getObjectStorage, ObjectNotFoundError, quotationPhotoPath, type StoredObjectStream } from '../lib/storage.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import type { Attachment, Quotation, RequestContext } from '../types.js';
import { audit } from './audit.js';

export const MAX_PHOTO_BYTES = 10 * 1024 * 1024;
export const MAX_PHOTOS_PER_QUOTATION = 10;
export const PHOTO_CACHE_CONTROL = 'private, max-age=3600';

export interface AddPhotoInput {
  buffer: Buffer;
  caption?: string | null;
}

/** Photos may only change before the customer has decided. */
export function assertPhotosMutable(q: Quotation): void {
  if (q.decided_at || !['requested', 'assessing', 'quoted'].includes(q.status)) {
    throw ApiError.conflict('Photos can no longer be changed once the quotation has been decided', { decided_at: q.decided_at, status: q.status });
  }
}

export async function listPhotos(quotationId: string): Promise<Attachment[]> {
  return unwrap<Attachment[]>(await getSupabase().from('attachments').select('*').eq('entity_type', 'quotation').eq('entity_id', quotationId).eq('kind', 'damage_photo').order('created_at'), 'photos');
}

export async function addPhoto(ctx: RequestContext, q: Quotation, input: AddPhotoInput): Promise<Attachment> {
  assertPhotosMutable(q);
  if (input.buffer.length === 0) throw ApiError.validation('Photo is empty');
  if (input.buffer.length > MAX_PHOTO_BYTES) throw ApiError.validation(`Photo exceeds ${MAX_PHOTO_BYTES / (1024 * 1024)} MB`, { max_bytes: MAX_PHOTO_BYTES });
  const type = sniffImage(input.buffer);
  if (!type) throw ApiError.validation('Unsupported image type: send a JPEG, PNG, HEIC or WebP photo', [{ path: 'photo', message: 'unrecognised image signature' }]);
  const existing = await listPhotos(q.id);
  if (existing.length >= MAX_PHOTOS_PER_QUOTATION) throw ApiError.conflict(`A quotation can have at most ${MAX_PHOTOS_PER_QUOTATION} photos`, { count: existing.length, max: MAX_PHOTOS_PER_QUOTATION });

  const id = randomUUID();
  const storagePath = quotationPhotoPath(q.id, id, type.ext);
  const { width, height } = readDimensions(input.buffer);
  await getObjectStorage().putObject(storagePath, input.buffer, { contentType: type.mime, metadata: { quotation_id: q.id, attachment_id: id, uploaded_by: ctx.auth.uid } });
  const db = getSupabase();
  const res = await db
    .from('attachments')
    .insert({
      id,
      entity_type: 'quotation',
      entity_id: q.id,
      storage_path: storagePath,
      mime_type: type.mime,
      size_bytes: input.buffer.length,
      sha256: null,
      uploaded_by: ctx.auth.uid,
      kind: 'damage_photo',
      width,
      height,
      caption: input.caption?.trim() || null,
    })
    .select('*')
    .single();
  if (res.error) {
    await getObjectStorage().deleteObject(storagePath).catch(() => undefined);
    throw ApiError.internal(`Could not record photo: ${res.error.message}`);
  }
  const att = res.data as Attachment;
  await audit(ctx, { action: 'quotation.photo_add', entity_type: 'quotation', entity_id: q.id, outlet_id: q.outlet_id, after: { attachment_id: id, mime_type: type.mime, size_bytes: att.size_bytes, width, height } });
  return att;
}

export async function getPhotoOrThrow(quotationId: string, attachmentId: string): Promise<Attachment> {
  const att = unwrap<Attachment | null>(await getSupabase().from('attachments').select('*').eq('id', attachmentId).eq('entity_type', 'quotation').eq('entity_id', quotationId).maybeSingle(), 'photo');
  if (!att) throw ApiError.notFound('Photo');
  return att;
}

export async function openPhoto(quotationId: string, attachmentId: string): Promise<{ attachment: Attachment; object: StoredObjectStream }> {
  const attachment = await getPhotoOrThrow(quotationId, attachmentId);
  try {
    const object = await getObjectStorage().streamObject(attachment.storage_path);
    return { attachment, object };
  } catch (err) {
    if (err instanceof ObjectNotFoundError) throw ApiError.notFound('Photo');
    throw err;
  }
}

export async function deletePhoto(ctx: RequestContext, q: Quotation, attachmentId: string): Promise<void> {
  assertPhotosMutable(q);
  const att = await getPhotoOrThrow(q.id, attachmentId);
  await getObjectStorage().deleteObject(att.storage_path);
  await getSupabase().from('attachments').delete().eq('id', att.id);
  await audit(ctx, { action: 'quotation.photo_delete', entity_type: 'quotation', entity_id: q.id, outlet_id: q.outlet_id, before: { attachment_id: att.id, storage_path: att.storage_path } });
}
