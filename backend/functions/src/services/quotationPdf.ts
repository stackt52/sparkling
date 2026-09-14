/**
 * A4 quotation PDF (pdfkit), laid out like the Sparkling Auto Care Centre paper
 * quote: logo top-right, "QUOTE" + outlet code, Date / Expiry / Quote Number /
 * Reference / VAT Number, the outlet's legal block, customer + vehicle block,
 * an items table (Description | Quantity | Unit Price | VAT | Amount ZAR) with
 * Subtotal / TOTAL VAT / TOTAL ZAR, the standard Terms, a signature line, the
 * outlet's banking details, optional damage-photo thumbnails and a QR code of
 * the public link. Every page carries the company-registration footer.
 *
 * Stored amounts are VAT-inclusive; the table shows VAT-exclusive unit prices
 * and adds 15% so TOTAL ZAR equals the stored total.
 */
import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';
import { sparklingLogoBuffer, SPARKLING_LOGO_SIZE } from '../assets/logo.js';
import { getObjectStorage } from '../lib/storage.js';
import { getSupabase } from '../lib/supabase.js';
import { logger } from '../middleware/correlation.js';
import type { Attachment, Outlet, Quotation, Vehicle } from '../types.js';
import { loadQuotationAttachments, markPdfGenerated, OUTLET_LEGAL_COLUMNS, publicQuoteUrl, QUOTE_TERMS, quoteExpired } from './quotations.js';

export const PDF_MAX_THUMBNAILS = 4;
export const VAT_RATE = 0.15;

export interface QuotationPdfInput {
  quotation: Quotation;
  outlet: Pick<Outlet, 'name' | 'code' | 'address_line' | 'city' | 'phone' | 'email' | 'legal_name' | 'trading_as' | 'company_registration_no' | 'vat_number' | 'registered_office' | 'bank_details'> | null;
  customer: { full_name: string | null; phone?: string | null } | null;
  vehicle: Pick<Vehicle, 'registration_no' | 'make' | 'model' | 'colour' | 'vin' | 'year'> | null;
  attachments: Attachment[];
  publicUrl: string | null;
  /** Loads photo bytes; return null (or throw) to skip the thumbnail. */
  loadPhoto?: (att: Attachment) => Promise<Buffer | null>;
}

const PAGE = { width: 595.28, height: 841.89, margin: 42 };
const INK = '#1f2937';
const MUTED = '#6b7280';
const RULE = '#9ca3af';
const LIGHT_RULE = '#e5e7eb';
const FOOTER_H = 26;

/** "4,500.00" style, from cents. */
function amount(cents: number): string {
  const v = Math.round(cents) / 100;
  return v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'Africa/Johannesburg' });
}

function surname(fullName: string | null | undefined): string {
  const parts = (fullName ?? '').trim().split(/\s+/).filter(Boolean);
  return (parts.length > 1 ? parts[parts.length - 1] : parts[0] ?? '').toUpperCase();
}

function firstName(fullName: string | null | undefined): string {
  return (fullName ?? '').trim().split(/\s+/)[0] ?? '';
}

function plateCompact(reg: string | null | undefined): string {
  return (reg ?? '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
}

function statusLine(q: Quotation): string {
  const expired = quoteExpired(q);
  const via = q.decision_source === 'public_link' ? 'via the quote link' : q.decision_source === 'app' ? 'in the Sparkling app' : q.decision_source === 'staff' ? 'by staff' : '';
  switch (q.status) {
    case 'accepted':
      return `Accepted on ${fmtDate(q.decided_at)}${q.decision_by_name ? ` by ${q.decision_by_name}` : ''}${via ? ` ${via}` : ''}.`;
    case 'declined':
      return `Declined on ${fmtDate(q.decided_at)}${q.decision_by_name ? ` by ${q.decision_by_name}` : ''}.`;
    case 'converted':
      return 'Accepted and converted to a work order.';
    case 'expired':
      return `Expired on ${fmtDate(q.valid_until)}.`;
    case 'quoted':
      return expired ? `Expired on ${fmtDate(q.valid_until)}.` : `Awaiting your decision - valid until ${fmtDate(q.valid_until)}.`;
    default:
      return q.status.replace('_', ' ');
  }
}

/** Splits a VAT-inclusive amount into exclusive + VAT (cents). */
export function splitVat(inclCents: number): { excl: number; vat: number } {
  const excl = Math.round(inclCents / (1 + VAT_RATE));
  return { excl, vat: inclCents - excl };
}

/** Builds the PDF bytes. Pure apart from `loadPhoto`. */
export async function buildQuotationPdf(input: QuotationPdfInput): Promise<Buffer> {
  const { quotation: q } = input;
  const o = input.outlet;
  const v = input.vehicle;
  const c = input.customer;
  const doc = new PDFDocument({ size: 'A4', margin: PAGE.margin, autoFirstPage: true, bufferPages: true, info: { Title: `Quotation ${q.ref}`, Author: 'Sparkling Auto Care Centres', Subject: 'Quotation' } });
  // Pagination is driven by ensureSpace(); stop pdfkit from adding pages itself when text
  // approaches the bottom margin (that also lets the footer be drawn inside the margin).
  const disableAutoBreak = () => {
    doc.page.margins.bottom = 0;
  };
  disableAutoBreak();
  doc.on('pageAdded', disableAutoBreak);
  const chunks: Buffer[] = [];
  doc.on('data', (b: Buffer) => chunks.push(b));
  const done = new Promise<Buffer>((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });
  const left = PAGE.margin;
  const right = PAGE.width - PAGE.margin;
  const contentWidth = right - left;
  const bottomLimit = PAGE.height - PAGE.margin - FOOTER_H;

  const ensureSpace = (needed: number, y: number): number => {
    if (y + needed <= bottomLimit) return y;
    doc.addPage();
    return PAGE.margin;
  };

  // ---- Header -------------------------------------------------------------
  let logoH = 0;
  try {
    const logoW = 128;
    logoH = (SPARKLING_LOGO_SIZE.height / SPARKLING_LOGO_SIZE.width) * logoW;
    doc.image(sparklingLogoBuffer(), right - logoW, PAGE.margin, { width: logoW });
  } catch (err) {
    logger.warn({ err }, 'logo embed failed; continuing without');
    doc.fillColor('#006398').font('Helvetica-Bold').fontSize(20).text('SPARKLING', right - 140, PAGE.margin, { width: 140, align: 'right' });
    logoH = 24;
  }
  const headerTop = PAGE.margin + logoH + 18;

  doc.fillColor(INK).font('Helvetica').fontSize(30).text('QUOTE', left, headerTop);
  doc.font('Helvetica').fontSize(10).fillColor(INK).text(o?.code ?? '', left + 30, doc.y + 6);

  // Meta column (Date / Expiry / Quote Number / Reference / VAT Number)
  const metaX = left + contentWidth * 0.55;
  const legalX = left + contentWidth * 0.75;
  const meta: Array<[string, string]> = [
    ['Date', fmtDate(q.quoted_at ?? q.created_at)],
    ['Expiry', fmtDate(q.valid_until)],
    ['Quote Number', q.ref],
    ['Reference', [plateCompact(v?.registration_no), surname(c?.full_name)].filter(Boolean).join('-') || q.ref],
    ['VAT Number', o?.vat_number ?? '-'],
  ];
  let my = headerTop;
  for (const [label, value] of meta) {
    doc.font('Helvetica-Bold').fontSize(9).fillColor(INK).text(label, metaX, my, { width: legalX - metaX - 8 });
    doc.font('Helvetica').fontSize(9).fillColor(INK).text(value, metaX, doc.y, { width: legalX - metaX - 8 });
    my = doc.y + 6;
  }

  // Outlet legal block
  const legalLines = [
    o?.legal_name ?? o?.name ?? 'Sparkling Auto Care Centres',
    o?.trading_as ? `T/A ${o.trading_as}` : '',
    o?.address_line ?? '',
    o?.city ?? '',
    o?.phone ? `Tel: ${o.phone}` : '',
    o?.email ? `email: ${o.email}` : '',
  ].filter(Boolean);
  doc.font('Helvetica').fontSize(9).fillColor(INK);
  let ly = headerTop;
  for (const line of legalLines) {
    doc.text(line, legalX, ly, { width: right - legalX });
    ly = doc.y + 1;
  }

  // ---- Customer & vehicle block ---------------------------------------------
  let y = Math.max(my, ly, headerTop + 70) + 12;
  const custTitle = [firstName(c?.full_name) || 'Customer', plateCompact(v?.registration_no)].filter(Boolean).join('-');
  doc.font('Helvetica-Bold').fontSize(11).fillColor(INK).text(custTitle, left, y);
  y = doc.y + 6;
  doc.font('Helvetica').fontSize(9.5).fillColor(INK);
  for (const line of [c?.full_name ?? '', c?.phone ?? '', [v?.make, v?.model].filter(Boolean).join(' '), v?.registration_no ?? '', v?.colour ?? '', v?.vin ? `VIN ${v.vin}` : ''].filter(Boolean)) {
    doc.text(line, left, y);
    y = doc.y + 1;
  }
  if (q.description) {
    y += 6;
    doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(`${q.category}: ${q.description}`, left, y, { width: contentWidth });
    y = doc.y;
  }
  y += 22;

  // ---- Items table ------------------------------------------------------------
  const col = { desc: left + 4, qty: right - 300, unit: right - 220, vat: right - 130, amt: right - 90 };
  const header = (yy: number): number => {
    doc.font('Helvetica-Bold').fontSize(9).fillColor(INK);
    doc.text('Description', col.desc, yy, { width: col.qty - col.desc - 6 });
    doc.text('Quantity', col.qty, yy, { width: col.unit - col.qty - 6, align: 'right' });
    doc.text('Unit Price', col.unit, yy, { width: col.vat - col.unit - 6, align: 'right' });
    doc.text('VAT', col.vat, yy, { width: col.amt - col.vat - 6, align: 'right' });
    doc.text('Amount ZAR', col.amt, yy, { width: right - col.amt - 4, align: 'right' });
    const lineY = yy + 16;
    doc.moveTo(left, lineY).lineTo(right, lineY).strokeColor(INK).lineWidth(0.8).stroke();
    return lineY + 6;
  };
  y = ensureSpace(60, y);
  y = header(y);
  const items = q.line_items ?? [];
  let subtotalExcl = 0;
  let totalVat = 0;
  doc.font('Helvetica').fontSize(9.5).fillColor(INK);
  if (items.length === 0) {
    doc.fillColor(MUTED).text('No line items.', col.desc, y + 4);
    y = doc.y + 8;
  }
  for (const item of items) {
    const qty = item.quantity && item.quantity > 0 ? item.quantity : 1;
    const lineIncl = (item.amount_cents ?? 0) * qty;
    const { excl, vat } = splitVat(lineIncl);
    subtotalExcl += excl;
    totalVat += vat;
    const unitExcl = splitVat(item.amount_cents ?? 0).excl;
    const descText = [item.label, item.description].filter(Boolean).join(' - ');
    const rowH = Math.max(doc.heightOfString(descText, { width: col.qty - col.desc - 6 }), 12) + 10;
    y = ensureSpace(rowH + 4, y);
    doc.fillColor(INK).font('Helvetica').fontSize(9.5);
    doc.text(descText, col.desc, y + 4, { width: col.qty - col.desc - 6 });
    doc.text(qty.toFixed(2), col.qty, y + 4, { width: col.unit - col.qty - 6, align: 'right' });
    doc.text(amount(unitExcl), col.unit, y + 4, { width: col.vat - col.unit - 6, align: 'right' });
    doc.text(item.amount_cents ? `${Math.round(VAT_RATE * 100)}%` : '', col.vat, y + 4, { width: col.amt - col.vat - 6, align: 'right' });
    doc.text(amount(excl), col.amt, y + 4, { width: right - col.amt - 4, align: 'right' });
    y += rowH;
    doc.moveTo(left, y).lineTo(right, y).strokeColor(LIGHT_RULE).lineWidth(0.5).stroke();
  }
  const total = q.amount_cents ?? subtotalExcl + totalVat;
  if (items.length) {
    // Absorb rounding so the components reconcile to the stored total.
    totalVat = total - subtotalExcl;
  }

  // ---- Totals -----------------------------------------------------------------
  y = ensureSpace(80, y) + 10;
  const totalsLabelX = col.unit;
  const totalRow = (label: string, value: string, bold = false, ruleAbove = false, ruleBelow = false) => {
    if (ruleAbove) doc.moveTo(totalsLabelX, y - 4).lineTo(right, y - 4).strokeColor(RULE).lineWidth(0.8).stroke();
    doc.font(bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(bold ? 10.5 : 9.5).fillColor(INK);
    doc.text(label, totalsLabelX, y, { width: col.amt - totalsLabelX - 6, align: 'right' });
    doc.text(value, col.amt, y, { width: right - col.amt - 4, align: 'right' });
    y = doc.y + 8;
    if (ruleBelow) {
      doc.moveTo(totalsLabelX, y - 4).lineTo(right, y - 4).strokeColor(RULE).lineWidth(0.8).stroke();
      y += 2;
    }
  };
  totalRow('Subtotal', amount(subtotalExcl));
  totalRow('TOTAL  VAT', amount(totalVat), false, false, true);
  totalRow('TOTAL ZAR', amount(total), true, false, true);

  // Status line
  y = ensureSpace(30, y) + 2;
  doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(statusLine(q), left, y, { width: contentWidth });
  y = doc.y;
  if (q.items_note) {
    doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(q.items_note, left, y + 4, { width: contentWidth });
    y = doc.y;
  }
  if (q.decision_note) {
    doc.font('Helvetica').fontSize(9).fillColor(MUTED).text(`Customer note: ${q.decision_note}`, left, y + 4, { width: contentWidth });
    y = doc.y;
  }

  // ---- Terms ------------------------------------------------------------------
  doc.font('Helvetica').fontSize(9);
  const termsH = doc.heightOfString(QUOTE_TERMS, { width: contentWidth });
  y = ensureSpace(termsH + 60, y) + 26;
  doc.font('Helvetica-Bold').fontSize(10).fillColor(INK).text('Terms', left, y);
  y = doc.y + 4;
  doc.moveTo(left, y).lineTo(right, y).strokeColor(INK).lineWidth(0.8).stroke();
  y += 8;
  doc.font('Helvetica').fontSize(9).fillColor(INK).text(QUOTE_TERMS, left, y, { width: contentWidth, lineGap: 1.5 });
  y = doc.y + 22;

  // Signature
  y = ensureSpace(40, y);
  doc.font('Helvetica').fontSize(9).fillColor(INK).text('________________________________', left, y);
  doc.text('Signature', left, doc.y + 2);
  y = doc.y + 16;

  // ---- Banking details ----------------------------------------------------------
  const bank = o?.bank_details ?? null;
  const bankLines = bank
    ? [
        bank.financial_institution ? `Financial Institution: ${bank.financial_institution}` : '',
        bank.account_name ? `Account Name: ${bank.account_name}` : '',
        bank.branch ? `Branch: ${bank.branch}` : '',
        bank.branch_code ? `Branch code: ${bank.branch_code}` : '',
        bank.account_number ? `Account Number: ${bank.account_number}` : '',
        bank.account_type ? `Account Type: ${bank.account_type}` : '',
      ].filter(Boolean)
    : [];
  y = ensureSpace(20 + bankLines.length * 13, y);
  doc.font('Helvetica').fontSize(9.5).fillColor(INK).text('OUR BANKING DETAILS:', left, y);
  y = doc.y + 4;
  for (const line of bankLines) {
    doc.text(line, left, y);
    y = doc.y + 1;
  }
  if (!bankLines.length) {
    doc.fillColor(MUTED).text('Banking details are available from the outlet on request.', left, y);
    y = doc.y;
  }

  // ---- Public link + QR -------------------------------------------------------------
  if (input.publicUrl) {
    let qr: Buffer | null = null;
    try {
      qr = await QRCode.toBuffer(input.publicUrl, { type: 'png', margin: 1, width: 84, errorCorrectionLevel: 'M' });
    } catch (err) {
      logger.warn({ err }, 'qr generation failed; continuing without');
    }
    y = ensureSpace(100, y) + 14;
    if (qr) doc.image(qr, left, y, { width: 84, height: 84 });
    doc.font('Helvetica-Bold').fontSize(9).fillColor(INK).text('View, accept or decline online', left + 96, y + 8, { width: contentWidth - 96 });
    doc.font('Helvetica').fontSize(8.5).fillColor(MUTED).text(input.publicUrl, left + 96, doc.y + 2, { width: contentWidth - 96 });
    doc.text('Scan the code or open the link on your phone. Your decision can only be made once.', left + 96, doc.y + 2, { width: contentWidth - 96 });
    y += 96;
  }

  // ---- Damage photos (JPEG/PNG only) -----------------------------------------------
  const photos = input.attachments.filter((a) => a.kind === 'damage_photo' && ['image/jpeg', 'image/png'].includes(a.mime_type)).slice(0, PDF_MAX_THUMBNAILS);
  if (photos.length && input.loadPhoto) {
    const thumbW = (contentWidth - 10 * (PDF_MAX_THUMBNAILS - 1)) / PDF_MAX_THUMBNAILS;
    const thumbH = thumbW * 0.75;
    y = ensureSpace(thumbH + 40, y) + 10;
    doc.font('Helvetica-Bold').fontSize(9).fillColor(INK).text('Damage photos', left, y);
    y = doc.y + 6;
    let x = left;
    for (const att of photos) {
      try {
        const buf = await input.loadPhoto(att);
        if (buf && buf.length) {
          doc.image(buf, x, y, { fit: [thumbW, thumbH], align: 'center', valign: 'center' });
          if (att.caption) doc.font('Helvetica').fontSize(7).fillColor(MUTED).text(att.caption, x, y + thumbH + 2, { width: thumbW, height: 10, ellipsis: true });
        }
      } catch (err) {
        logger.warn({ err, attachment_id: att.id }, 'pdf thumbnail skipped');
      }
      x += thumbW + 10;
    }
  }

  // ---- Footer on every page --------------------------------------------------------
  const footer = [o?.company_registration_no ? `Company Registration No: ${o.company_registration_no}.` : '', o?.registered_office ? `Registered Office: ${o.registered_office}.` : '']
    .filter(Boolean)
    .join('  ');
  const range = doc.bufferedPageRange();
  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);
    const fy = PAGE.height - 30;
    doc.font('Helvetica').fontSize(7.5).fillColor(MUTED);
    doc.text(footer || `${q.ref}`, left, fy, { width: contentWidth - 60, lineBreak: false });
    doc.text(`${q.ref} · page ${i - range.start + 1} of ${range.count}`, right - 120, fy, { width: 120, align: 'right', lineBreak: false });
  }

  doc.end();
  return done;
}

/** Loads everything the PDF needs for a quotation and renders it; stamps `pdf_generated_at` once. */
export async function renderQuotationPdf(q: Quotation): Promise<Buffer> {
  const db = getSupabase();
  const [outlet, customer, vehicle, attachments] = await Promise.all([
    db.from('outlets').select(OUTLET_LEGAL_COLUMNS).eq('id', q.outlet_id).maybeSingle(),
    db.from('profiles').select('full_name, phone').eq('id', q.customer_id).maybeSingle(),
    db.from('vehicles').select('registration_no, make, model, colour, vin, year').eq('id', q.vehicle_id).maybeSingle(),
    loadQuotationAttachments([q.id]),
  ]);
  const pdf = await buildQuotationPdf({
    quotation: q,
    outlet: (outlet.data ?? null) as QuotationPdfInput['outlet'],
    customer: (customer.data ?? null) as QuotationPdfInput['customer'],
    vehicle: (vehicle.data ?? null) as QuotationPdfInput['vehicle'],
    attachments,
    publicUrl: publicTokenUsable(q) ? publicQuoteUrl(q.public_token) : null,
    loadPhoto: (att) => getObjectStorage().getObject(att.storage_path),
  });
  await markPdfGenerated(q);
  return pdf;
}

function publicTokenUsable(q: Quotation): boolean {
  if (!q.public_token) return false;
  if (!q.public_token_expires_at) return true;
  return new Date(q.public_token_expires_at).getTime() > Date.now();
}

export function pdfFilename(q: Pick<Quotation, 'ref'>): string {
  return `${q.ref.replace(/[^A-Za-z0-9._-]/g, '_')}.pdf`;
}
