/**
 * CSV helpers (REP-007): every export starts with metadata header rows
 * (generated_at, filters, scope) followed by a blank line and the data table.
 */
export interface CsvMeta {
  report: string;
  generated_at?: string;
  generated_by?: string;
  scope?: string;
  filters?: Record<string, string | number | boolean | null | undefined>;
}

function cell(v: unknown): string {
  if (v === null || v === undefined) return '';
  const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function buildCsv(meta: CsvMeta, columns: string[], rows: Record<string, unknown>[]): string {
  const lines: string[] = [];
  lines.push(`# report,${cell(meta.report)}`);
  lines.push(`# generated_at,${cell(meta.generated_at ?? new Date().toISOString())}`);
  if (meta.generated_by) lines.push(`# generated_by,${cell(meta.generated_by)}`);
  lines.push(`# scope,${cell(meta.scope ?? 'all outlets')}`);
  const filters = Object.entries(meta.filters ?? {}).filter(([, v]) => v !== undefined && v !== null && v !== '');
  lines.push(`# filters,${cell(filters.map(([k, v]) => `${k}=${v}`).join('; ') || 'none')}`);
  lines.push('');
  lines.push(columns.map(cell).join(','));
  for (const r of rows) lines.push(columns.map((c) => cell(r[c])).join(','));
  return lines.join('\r\n');
}

export function downloadCsv(filename: string, csv: string) {
  if (typeof window === 'undefined') return;
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
