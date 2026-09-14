import type { Metadata } from 'next';
import PublicQuotePage from '@/components/public/PublicQuotePage';

/**
 * Public quotation page — `<admin origin>/q/<token>` is the link customers receive on WhatsApp
 * (docs/API.md "Staff-raised quotations, damage photos & public quote page"). It lives outside the
 * `(dashboard)` route group on purpose: no Firebase sign-in, no nav rail, token-scoped API only.
 * The final `<title>` ("Quotation <ref> · Sparkling") is set client-side once the quote loads.
 */
export const metadata: Metadata = {
  title: { absolute: 'Quotation · Sparkling' },
  robots: { index: false, follow: false },
};

export default async function Page({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return <PublicQuotePage token={token} />;
}
