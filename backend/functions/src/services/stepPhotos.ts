/**
 * Checklist step photo proof (STF-006): staff upload a photo for a work-order step, then submit the
 * step with its `attachment_id`. Objects are private (served through the API only).
 */
import { randomUUID } from 'node:crypto';
import { readDimensions, sniffImage } from '../lib/images.js';
import { getObjectStorage, ObjectNotFoundError, workOrderPhotoPath, type StoredObjectStream } from '../lib/storage.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import type { Attachment, RequestContext, WorkOrder } from '../types.js';
import { audit } from './audit.js';

export const MAX_STEP_PHOTO_BYTES = 10 * 1024 * 1024;
export const MAX_PHOTOS_PER_WORK_ORDER = 40;
export const STEP_PHOTO_ENTITY = 'checklist_step';

export async function listStepPhotos(workOrderId: string): Promise<Attachment[]> {
  return unwrap<Attachment[]>(await getSupabase().from('attachments').select('*').eq('entity_type', STEP_PHOTO_ENTITY).eq('entity_id', workOrderId).order('created_at'), 'photos');
}

export async function addStepPhoto(ctx: RequestContext, wo: WorkOrder, input: { buffer: Buffer; stepKey?: string | null }): Promise<Attachment> {
  if (['verified', 'cancelled'].includes(wo.status)) throw ApiError.conflict('Work order is closed', { status: wo.status });
  if (input.buffer.length === 0) throw ApiError.validation('Photo is empty');
  if (input.buffer.length > MAX_STEP_PHOTO_BYTES) throw ApiError.validation(`Photo exceeds ${MAX_STEP_PHOTO_BYTES / (1024 * 1024)} MB`, { max_bytes: MAX_STEP_PHOTO_BYTES });
  const type = sniffImage(input.buffer);
  if (!type) throw ApiError.validation('Unsupported image type: send a JPEG, PNG, HEIC or WebP photo', [{ path: 'photo', message: 'unrecognised image signature' }]);
  const existing = await listStepPhotos(wo.id);
  if (existing.length >= MAX_PHOTOS_PER_WORK_ORDER) throw ApiError.conflict(`A work order can have at most ${MAX_PHOTOS_PER_WORK_ORDER} photos`, { count: existing.length, max: MAX_PHOTOS_PER_WORK_ORDER });

  const id = randomUUID();
  const storagePath = workOrderPhotoPath(wo.id, id, type.ext);
  const { width, height } = readDimensions(input.buffer);
  await getObjectStorage().putObject(storagePath, input.buffer, { contentType: type.mime, metadata: { work_order_id: wo.id, attachment_id: id, uploaded_by: ctx.auth.uid, ...(input.stepKey ? { step_key: input.stepKey } : {}) } });
  const res = await getSupabase()
    .from('attachments')
    .insert({ id, entity_type: STEP_PHOTO_ENTITY, entity_id: wo.id, storage_path: storagePath, mime_type: type.mime, size_bytes: input.buffer.length, sha256: null, uploaded_by: ctx.auth.uid, kind: 'step_photo', width, height, caption: input.stepKey ?? null })
    .select('*')
    .single();
  if (res.error) {
    await getObjectStorage().deleteObject(storagePath).catch(() => undefined);
    throw ApiError.internal(`Could not record photo: ${res.error.message}`);
  }
  const att = res.data as Attachment;
  await audit(ctx, { action: 'work_order.photo_add', entity_type: 'work_order', entity_id: wo.id, outlet_id: wo.outlet_id, after: { attachment_id: id, step_key: input.stepKey ?? null, mime_type: type.mime, size_bytes: att.size_bytes, width, height } });
  return att;
}

export async function openStepPhoto(workOrderId: string, attachmentId: string): Promise<{ attachment: Attachment; object: StoredObjectStream }> {
  const attachment = unwrap<Attachment | null>(await getSupabase().from('attachments').select('*').eq('id', attachmentId).eq('entity_type', STEP_PHOTO_ENTITY).eq('entity_id', workOrderId).maybeSingle(), 'photo');
  if (!attachment) throw ApiError.notFound('Photo');
  try {
    const object = await getObjectStorage().streamObject(attachment.storage_path);
    return { attachment, object };
  } catch (err) {
    if (err instanceof ObjectNotFoundError) throw ApiError.notFound('Photo');
    throw err;
  }
}

export function stepPhotoView(att: Attachment, baseUrl: string) {
  return { id: att.id, kind: att.kind ?? 'step_photo', step_key: att.caption ?? null, mime_type: att.mime_type, size_bytes: att.size_bytes, width: att.width ?? null, height: att.height ?? null, url: `${baseUrl}/photos/${att.id}`, created_at: att.created_at };
}
