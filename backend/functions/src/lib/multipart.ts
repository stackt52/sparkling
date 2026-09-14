/**
 * Minimal `multipart/form-data` parsing with busboy for single-file uploads
 * (quotation damage photos). The whole file is buffered (≤ `maxFileBytes`) so
 * it can be type-sniffed before anything touches storage.
 */
import busboy from 'busboy';
import type { Request } from 'express';
import { ApiError } from '../middleware/errors.js';

export interface MultipartResult {
  file: { field: string; buffer: Buffer; filename: string | null; mimeType: string | null } | null;
  fields: Record<string, string>;
}

export interface MultipartOptions {
  /** Field name the file must be sent under. */
  fileField: string;
  maxFileBytes: number;
  maxFields?: number;
}

export function parseMultipart(req: Request, opts: MultipartOptions): Promise<MultipartResult> {
  return new Promise((resolve, reject) => {
    if (!req.is('multipart/form-data')) return reject(ApiError.validation('Expected multipart/form-data'));
    let bb: busboy.Busboy;
    try {
      bb = busboy({ headers: req.headers, limits: { files: 1, fileSize: opts.maxFileBytes, fields: opts.maxFields ?? 10, fieldSize: 2000 } });
    } catch (err) {
      return reject(ApiError.validation(`Malformed multipart request: ${(err as Error).message}`));
    }
    const out: MultipartResult = { file: null, fields: {} };
    let failed: ApiError | null = null;
    const fail = (e: ApiError) => {
      if (failed) return;
      failed = e;
      req.unpipe(bb);
      req.resume();
      reject(e);
    };
    bb.on('field', (name, value) => {
      out.fields[name] = value;
    });
    bb.on('file', (name, stream, info) => {
      if (name !== opts.fileField) {
        stream.resume();
        return fail(ApiError.validation(`Unexpected file field "${name}"; send the file as "${opts.fileField}"`));
      }
      const chunks: Buffer[] = [];
      stream.on('data', (c: Buffer) => chunks.push(c));
      stream.on('limit', () => fail(ApiError.validation(`File exceeds ${Math.round(opts.maxFileBytes / (1024 * 1024))} MB`, { max_bytes: opts.maxFileBytes })));
      stream.on('end', () => {
        if (failed) return;
        out.file = { field: name, buffer: Buffer.concat(chunks), filename: info.filename || null, mimeType: info.mimeType || null };
      });
    });
    bb.on('filesLimit', () => fail(ApiError.validation('Only one file per request')));
    bb.on('error', (err: Error) => fail(ApiError.validation(`Malformed multipart request: ${err.message}`)));
    bb.on('close', () => {
      if (!failed) resolve(out);
    });
    req.pipe(bb);
  });
}
