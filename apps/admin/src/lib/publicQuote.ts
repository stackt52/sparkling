/**
 * Data access for the standalone public quote page (`/q/[token]`).
 * No Firebase, no AuthProvider: live mode uses `publicFetch` against the unauthenticated
 * `/v1/public/quotations/:token` routes; demo mode routes to the in-memory demo store
 * (loaded lazily so it stays out of the production bundle).
 */
import { publicFetch, resolveApiUrl } from './api';
import { isDemo } from './env';
import type { PublicDecisionInput, PublicQuotation } from './types';

const demoStore = () => import('./demo/publicQuotes');

export async function getPublicQuotation(token: string): Promise<PublicQuotation> {
  if (isDemo()) return (await demoStore()).getDemoPublicQuote(token);
  return publicFetch<PublicQuotation>('GET', `/public/quotations/${encodeURIComponent(token)}`);
}

export async function decidePublicQuotation(token: string, body: PublicDecisionInput): Promise<PublicQuotation> {
  if (isDemo()) return (await demoStore()).decideDemoPublicQuote(token, body);
  return publicFetch<PublicQuotation>('POST', `/public/quotations/${encodeURIComponent(token)}/decision`, body);
}

/** Absolute URL of a public photo (`attachments[].url` is API-relative in live mode). */
export const publicPhotoUrl = (url: string) => resolveApiUrl(url);

/** Absolute PDF URL in live mode (used as the `<a download>` href); null in demo, where the PDF is built client-side. */
export function publicPdfHref(view: PublicQuotation): string | null {
  return isDemo() ? null : resolveApiUrl(view.pdf_url);
}

/** Demo-only: build the PDF client-side. */
export async function publicPdfBlob(token: string): Promise<Blob> {
  if (isDemo()) return (await demoStore()).demoPublicPdf(token);
  const res = await fetch(`${resolveApiUrl(`/v1/public/quotations/${encodeURIComponent(token)}/pdf`)}`);
  if (!res.ok) throw new Error(`Could not download the PDF (HTTP ${res.status})`);
  return res.blob();
}
