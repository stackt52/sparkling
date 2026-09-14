/**
 * Cloud Storage for Firebase behind a tiny interface so services never touch
 * the bucket directly and tests can inject an in-memory fake
 * (`setObjectStorageForTests`). Objects are private: they are only ever served
 * through the API (SEC-010), never via bucket URLs.
 */
import { getStorage } from 'firebase-admin/storage';
import type { Readable } from 'node:stream';
import { getFirebaseApp } from './firebase.js';

export interface PutObjectOptions {
  contentType: string;
  /** Free-form metadata stored with the object (entity ids, uploader). */
  metadata?: Record<string, string>;
}

export interface StoredObjectStream {
  stream: Readable;
  contentType: string | null;
  size: number | null;
}

export interface ObjectStorage {
  putObject(path: string, data: Buffer, opts: PutObjectOptions): Promise<void>;
  /** Streams an object for an HTTP response. Rejects with `ObjectNotFoundError` when missing. */
  streamObject(path: string): Promise<StoredObjectStream>;
  /** Whole object in memory (PDF thumbnails). Rejects with `ObjectNotFoundError` when missing. */
  getObject(path: string): Promise<Buffer>;
  /** Idempotent: a missing object is not an error. */
  deleteObject(path: string): Promise<void>;
}

export class ObjectNotFoundError extends Error {
  constructor(path: string) {
    super(`object not found: ${path}`);
    this.name = 'ObjectNotFoundError';
  }
}

class FirebaseObjectStorage implements ObjectStorage {
  private bucket() {
    return getStorage(getFirebaseApp()).bucket();
  }

  async putObject(path: string, data: Buffer, opts: PutObjectOptions): Promise<void> {
    await this.bucket().file(path).save(data, {
      contentType: opts.contentType,
      resumable: false,
      metadata: { contentType: opts.contentType, cacheControl: 'private, max-age=3600', metadata: opts.metadata ?? {} },
    });
  }

  async streamObject(path: string): Promise<StoredObjectStream> {
    const file = this.bucket().file(path);
    const [exists] = await file.exists();
    if (!exists) throw new ObjectNotFoundError(path);
    const [meta] = await file.getMetadata();
    const size = meta.size === undefined || meta.size === null ? null : Number(meta.size);
    return { stream: file.createReadStream(), contentType: meta.contentType ?? null, size: Number.isFinite(size) ? size : null };
  }

  async getObject(path: string): Promise<Buffer> {
    const file = this.bucket().file(path);
    try {
      const [buf] = await file.download();
      return buf;
    } catch (err) {
      if ((err as { code?: number }).code === 404) throw new ObjectNotFoundError(path);
      throw err;
    }
  }

  async deleteObject(path: string): Promise<void> {
    await this.bucket().file(path).delete({ ignoreNotFound: true });
  }
}

let override: ObjectStorage | null = null;
let instance: ObjectStorage | null = null;

export function getObjectStorage(): ObjectStorage {
  if (override) return override;
  instance ??= new FirebaseObjectStorage();
  return instance;
}

export function setObjectStorageForTests(s: ObjectStorage | null): void {
  override = s;
}

/** Storage path for a quotation damage photo: `quotations/<quotation_id>/<attachment_id>.<ext>`. */
export function quotationPhotoPath(quotationId: string, attachmentId: string, ext: string): string {
  return `quotations/${quotationId}/${attachmentId}.${ext}`;
}
