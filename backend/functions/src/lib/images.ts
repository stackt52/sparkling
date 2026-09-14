/**
 * SEC-010: image uploads are typed by their magic bytes, never by the client's
 * `Content-Type` or file name. Dimensions are read cheaply from the header
 * (`image-size`), no decoding.
 */
import { imageSize } from 'image-size';

export interface SniffedImage {
  mime: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/heic';
  ext: 'jpg' | 'png' | 'webp' | 'heic';
}

const HEIF_BRANDS = new Set(['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'hevm', 'hevs', 'mif1', 'msf1']);

/** Returns the image type for jpeg/png/webp/heic payloads, or null for anything else. */
export function sniffImage(buf: Buffer): SniffedImage | null {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg' };
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return { mime: 'image/png', ext: 'png' };
  if (buf.subarray(0, 4).toString('ascii') === 'RIFF' && buf.subarray(8, 12).toString('ascii') === 'WEBP') return { mime: 'image/webp', ext: 'webp' };
  if (buf.subarray(4, 8).toString('ascii') === 'ftyp' && HEIF_BRANDS.has(buf.subarray(8, 12).toString('ascii').toLowerCase())) return { mime: 'image/heic', ext: 'heic' };
  return null;
}

/** Pixel dimensions from the header, or nulls when the format/header cannot be read. */
export function readDimensions(buf: Buffer): { width: number | null; height: number | null } {
  try {
    const d = imageSize(buf);
    const width = Number.isFinite(d.width) ? Math.round(d.width as number) : null;
    const height = Number.isFinite(d.height) ? Math.round(d.height as number) : null;
    return { width, height };
  } catch {
    return { width: null, height: null };
  }
}
