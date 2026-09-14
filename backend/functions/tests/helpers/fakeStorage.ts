import { Readable } from 'node:stream';
import { ObjectNotFoundError, type ObjectStorage, type PutObjectOptions, type StoredObjectStream } from '../../src/lib/storage.js';

/** In-memory `ObjectStorage` for tests (no Cloud Storage calls). */
export class MemoryObjectStorage implements ObjectStorage {
  objects = new Map<string, { data: Buffer; contentType: string; metadata: Record<string, string> }>();
  calls: Array<{ op: string; path: string }> = [];

  async putObject(path: string, data: Buffer, opts: PutObjectOptions): Promise<void> {
    this.calls.push({ op: 'put', path });
    this.objects.set(path, { data: Buffer.from(data), contentType: opts.contentType, metadata: opts.metadata ?? {} });
  }
  async streamObject(path: string): Promise<StoredObjectStream> {
    this.calls.push({ op: 'stream', path });
    const o = this.objects.get(path);
    if (!o) throw new ObjectNotFoundError(path);
    return { stream: Readable.from([o.data]), contentType: o.contentType, size: o.data.length };
  }
  async getObject(path: string): Promise<Buffer> {
    this.calls.push({ op: 'get', path });
    const o = this.objects.get(path);
    if (!o) throw new ObjectNotFoundError(path);
    return o.data;
  }
  async deleteObject(path: string): Promise<void> {
    this.calls.push({ op: 'delete', path });
    this.objects.delete(path);
  }
}
