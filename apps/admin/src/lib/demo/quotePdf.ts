/**
 * Demo-only PDF rendering of a quotation (mirrors what `GET /quotations/:id/pdf` returns
 * from the API in live mode). Layout follows the printed Sparkling quote: logo top-right,
 * "QUOTE" heading + outlet code, date/reference and legal blocks, customer block, an
 * items table with VAT-exclusive unit prices, right-aligned totals, standard terms,
 * signature line and banking details, with the company registration footer on every page.
 * `jspdf` is imported lazily so it never lands in the production bundle unless demo mode
 * is on and the button is pressed.
 */
import type { jsPDF } from 'jspdf';
import { QUOTE_TERMS } from '../quoteTerms';
import { formatPhone } from '../phone';
import type { OutletLegal, QuoteLineItem, QuotationDecisionSource, QuotationStatus } from '../types';

export interface QuotePdfInput {
  ref: string;
  status: QuotationStatus;
  outlet: { name: string; code?: string | null; phone?: string | null; email?: string | null; address_line?: string | null; city?: string | null } & Partial<OutletLegal>;
  customer_name: string;
  customer_phone?: string | null;
  vehicle: { registration_no: string; make?: string | null; model?: string | null; colour?: string | null };
  items: QuoteLineItem[];
  amount_cents: number;
  valid_until: string | null;
  quoted_at: string | null;
  decided_at: string | null;
  decision_source?: QuotationDecisionSource | null;
  decision_by_name?: string | null;
  notes?: string | null;
  terms?: string | null;
  public_url?: string | null;
}

const INK: [number, number, number] = [0x16, 0x21, 0x2b];
const MUTED: [number, number, number] = [0x5f, 0x6b, 0x77];
const LINE: [number, number, number] = [0xd5, 0xdc, 0xe3];
const VAT_RATE = 0.15;

/* A4 geometry (mm) */
const W = 210;
const H = 297;
const M = 16;
const FOOTER_Y = H - 12;
const BODY_BOTTOM = FOOTER_Y - 10;
const LOGO_W = 45;
const LOGO_RATIO = 81 / 231; // public/logo-light.png

/** "3,347.83" — 2 decimals with thousands separators, as on the printed quote. */
const amount = (rands: number) => rands.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
/** Stored amounts are VAT-inclusive; the quote prints exclusive values. */
const excl = (cents: number) => cents / 100 / (1 + VAT_RATE);
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const plate = (reg: string) => reg.replace(/[\s-]+/g, '').toUpperCase();
const surname = (name: string) => name.trim().split(/\s+/).slice(-1)[0] ?? '';
const firstName = (name: string) => name.trim().split(/\s+/)[0] ?? '';
const nonEmpty = (v: string | null | undefined) => (v && v.trim() ? v.trim() : null);

async function loadLogo(): Promise<string | null> {
  if (typeof window === 'undefined') return null;
  try {
    const res = await fetch('/logo-light.png');
    if (!res.ok) return null;
    const blob = await res.blob();
    return await new Promise<string>((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result));
      r.onerror = () => reject(r.error);
      r.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

export async function buildQuotePdf(q: QuotePdfInput): Promise<Blob> {
  const [{ jsPDF }, logo] = await Promise.all([import('jspdf'), loadLogo()]);
  const doc: jsPDF = new jsPDF({ unit: 'mm', format: 'a4' });
  const o = q.outlet;
  const legalName = nonEmpty(o.legal_name) ?? o.name;
  const tradingAs = nonEmpty(o.trading_as);
  const bank = o.bank_details;
  let y = 0;

  const font = (style: 'normal' | 'bold', size: number, colour: [number, number, number] = INK) => {
    doc.setFont('helvetica', style);
    doc.setFontSize(size);
    doc.setTextColor(...colour);
  };
  const rule = (yy: number, x0 = M, x1 = W - M, weight = 0.2) => {
    doc.setDrawColor(...LINE);
    doc.setLineWidth(weight);
    doc.line(x0, yy, x1, yy);
  };
  /** Starts a new page when `h` mm would run into the footer zone. */
  const ensure = (h: number) => {
    if (y + h <= BODY_BOTTOM) return;
    doc.addPage();
    y = M + 4;
  };

  /* ---- header: logo top-right, QUOTE + outlet code left ---- */
  const logoX = W - M - LOGO_W;
  if (logo) {
    try {
      doc.addImage(logo, 'PNG', logoX, 12, LOGO_W, LOGO_W * LOGO_RATIO);
    } catch {
      /* fall through to text mark */
      font('bold', 16);
      doc.text('SPARKLING', W - M, 22, { align: 'right' });
    }
  } else {
    font('bold', 16);
    doc.text('SPARKLING', W - M, 22, { align: 'right' });
  }
  font('bold', 28);
  doc.text('QUOTE', M, 26);
  font('normal', 11, MUTED);
  doc.text(o.code ?? o.name, M, 33);

  /* ---- two right-hand columns under the logo ---- */
  const col1 = 98;
  const col2 = 152;
  y = 40;
  const meta: [string, string][] = [
    ['Date', day(q.quoted_at)],
    ['Expiry', day(q.valid_until)],
    ['Quote Number', q.ref],
    ['Reference', `${plate(q.vehicle.registration_no)}-${surname(q.customer_name).toUpperCase()}`],
    ['VAT Number', nonEmpty(o.vat_number) ?? '—'],
  ];
  const legalLines = [
    legalName,
    tradingAs ? `T/A ${tradingAs}` : null,
    nonEmpty(o.address_line),
    nonEmpty(o.city),
    nonEmpty(o.phone) ? `Tel: ${formatPhone(o.phone)}` : null,
    nonEmpty(o.email) ? `email: ${o.email}` : null,
  ].filter((l): l is string => Boolean(l));
  meta.forEach(([label, value], i) => {
    const yy = y + i * 4.6;
    font('bold', 8.5);
    doc.text(label, col1, yy);
    font('normal', 8.5);
    doc.text(value, col1 + 23, yy);
  });
  let legalRows = 0;
  legalLines.forEach((l, i) => {
    font(i === 0 ? 'bold' : 'normal', 8.5);
    const wrapped = doc.splitTextToSize(l, W - M - col2) as string[];
    wrapped.forEach((w) => {
      doc.text(w, col2, y + legalRows * 4.6);
      legalRows += 1;
    });
  });
  y += Math.max(meta.length, legalRows) * 4.6 + 6;

  /* ---- customer block ---- */
  font('bold', 10);
  doc.text(`${firstName(q.customer_name)}-${plate(q.vehicle.registration_no)}`, M, y);
  y += 4.8;
  font('normal', 9);
  const customerLines = [
    q.customer_name,
    nonEmpty(q.customer_phone) ? formatPhone(q.customer_phone) : null,
    [q.vehicle.make, q.vehicle.model].filter(Boolean).join(' ') || null,
    q.vehicle.registration_no,
    nonEmpty(q.vehicle.colour),
  ].filter((l): l is string => Boolean(l));
  customerLines.forEach((l) => {
    doc.text(l, M, y);
    y += 4.4;
  });
  y += 4;

  /* ---- items table ---- */
  const cDesc = M;
  const cQty = 122;
  const cUnit = 148;
  const cVat = 164;
  const cAmt = W - M;
  const descW = cQty - 14 - cDesc;
  const tableHead = () => {
    font('bold', 8.5);
    doc.text('Description', cDesc, y);
    doc.text('Quantity', cQty, y, { align: 'right' });
    doc.text('Unit Price', cUnit, y, { align: 'right' });
    doc.text('VAT', cVat, y, { align: 'right' });
    doc.text('Amount ZAR', cAmt, y, { align: 'right' });
    y += 2.2;
    rule(y, M, W - M, 0.4);
    y += 5;
  };
  ensure(30);
  tableHead();
  for (const it of q.items) {
    const qty = it.quantity ?? 1;
    const unit = excl(it.amount_cents);
    const label = doc.splitTextToSize(it.label, descW) as string[];
    const desc = it.description ? (doc.splitTextToSize(it.description, descW) as string[]) : [];
    const rowH = label.length * 4.2 + desc.length * 3.8 + 3.4;
    if (y + rowH > BODY_BOTTOM) {
      doc.addPage();
      y = M + 4;
      tableHead();
    }
    font('normal', 9);
    label.forEach((l, i) => doc.text(l, cDesc, y + i * 4.2));
    doc.text(String(qty), cQty, y, { align: 'right' });
    doc.text(amount(unit), cUnit, y, { align: 'right' });
    doc.text('15%', cVat, y, { align: 'right' });
    doc.text(amount(unit * qty), cAmt, y, { align: 'right' });
    if (desc.length) {
      font('normal', 8, MUTED);
      desc.forEach((l, i) => doc.text(l, cDesc, y + label.length * 4.2 + i * 3.8));
    }
    y += rowH;
    rule(y - 1.8);
    y += 3.2;
  }

  /* ---- totals (right-aligned) ---- */
  const totalRands = q.amount_cents / 100;
  const subtotal = totalRands / (1 + VAT_RATE);
  const vat = totalRands - subtotal;
  const tLabel = 120;
  ensure(30);
  y += 2;
  font('normal', 9);
  doc.text('Subtotal', tLabel, y);
  doc.text(amount(subtotal), cAmt, y, { align: 'right' });
  y += 5.2;
  doc.text('TOTAL VAT (15%)', tLabel, y);
  doc.text(amount(vat), cAmt, y, { align: 'right' });
  y += 3;
  rule(y, tLabel, W - M, 0.4);
  y += 5.2;
  font('bold', 10.5);
  doc.text('TOTAL ZAR', tLabel, y);
  doc.text(amount(totalRands), cAmt, y, { align: 'right' });
  y += 3;
  rule(y, tLabel, W - M, 0.4);
  y += 6;

  /* ---- status line ---- */
  const statusLine =
    q.status === 'accepted' || q.status === 'converted'
      ? `Accepted on ${day(q.decided_at)}${q.decision_source === 'public_link' ? ' via link' : q.decision_source === 'app' ? ' in the app' : q.decision_source === 'staff' ? ' at the counter' : ''}${q.decision_by_name ? ` by ${q.decision_by_name}` : ''}.`
      : q.status === 'declined'
        ? `Declined on ${day(q.decided_at)}${q.decision_by_name ? ` by ${q.decision_by_name}` : ''}.`
        : q.status === 'expired'
          ? 'This quotation has expired.'
          : `Awaiting your decision — valid until ${day(q.valid_until)}.`;
  ensure(10);
  font('normal', 8.5, MUTED);
  doc.text(statusLine, M, y);
  y += 5;
  if (q.notes) {
    const lines = doc.splitTextToSize(`Notes: ${q.notes}`, W - 2 * M) as string[];
    ensure(lines.length * 4 + 2);
    lines.forEach((l, i) => doc.text(l, M, y + i * 4));
    y += lines.length * 4 + 2;
  }
  y += 3;

  /* ---- terms ---- */
  ensure(24);
  font('bold', 10);
  doc.text('Terms', M, y);
  y += 2;
  rule(y, M, W - M, 0.4);
  y += 5;
  font('normal', 8.5);
  const termLines = doc.splitTextToSize(nonEmpty(q.terms) ?? QUOTE_TERMS, W - 2 * M) as string[];
  for (const l of termLines) {
    ensure(4.2);
    doc.text(l, M, y);
    y += 4.2;
  }
  y += 6;
  ensure(8);
  doc.text('________________ Signature', M, y);
  y += 8;

  /* ---- banking details ---- */
  const bankLines: [string, string | null | undefined][] = [
    ['Financial Institution', bank?.financial_institution],
    ['Account Name', bank?.account_name],
    ['Branch', bank?.branch],
    ['Branch code', bank?.branch_code],
    ['Account Number', bank?.account_number],
    ['Account Type', bank?.account_type],
  ];
  const bankPresent = bankLines.filter(([, v]) => nonEmpty(v));
  if (bankPresent.length) {
    ensure(5 + 2 * 4.2); // keep the heading with at least two lines
    font('bold', 9);
    doc.text('OUR BANKING DETAILS:', M, y);
    y += 5;
    font('normal', 8.5);
    for (const [label, value] of bankPresent) {
      ensure(4.2);
      doc.text(`${label}: ${value}`, M, y);
      y += 4.2;
    }
  }

  /* ---- footer on every page ---- */
  const footer = [
    nonEmpty(o.company_registration_no) ? `Company Registration No: ${o.company_registration_no}.` : null,
    nonEmpty(o.registered_office) ? `Registered Office: ${o.registered_office}.` : null,
  ]
    .filter(Boolean)
    .join('  ');
  const pages = doc.getNumberOfPages();
  for (let p = 1; p <= pages; p++) {
    doc.setPage(p);
    rule(FOOTER_Y - 8);
    font('normal', 7.5, MUTED);
    if (q.public_url) doc.text(`View or accept this quote online: ${q.public_url}`, M, FOOTER_Y - 4);
    doc.text(`${q.ref} · page ${p} of ${pages}`, W - M, FOOTER_Y - 4, { align: 'right' });
    const footerLines = doc.splitTextToSize(footer || `${o.name} · demo document generated in the admin dashboard`, W - 2 * M) as string[];
    footerLines.forEach((l, i) => doc.text(l, M, FOOTER_Y + i * 3.4));
  }

  return doc.output('blob');
}
