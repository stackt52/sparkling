/**
 * Minimal in-memory Supabase stub covering the query-builder subset the API
 * uses: from().select/insert/update/upsert/delete + filters, order, range,
 * limit, single, maybeSingle, rpc. Unique constraints are simulated per table
 * so 23505 handling can be tested. Embedded selects ("outlet:outlets(...)")
 * are ignored — rows come back flat.
 */
import { randomUUID } from 'node:crypto';

type Row = Record<string, any>;
type Filter = (row: Row) => boolean;

export interface FakeOptions {
  unique?: Record<string, string[][]>; // table -> list of unique column sets
  rpc?: Record<string, (args: Record<string, unknown>) => unknown>;
}

const DEFAULT_UNIQUE: Record<string, string[][]> = {
  idempotency_keys: [['key']],
  payment_events: [['provider', 'provider_event_id']],
  payments: [['idempotency_key'], ['receipt_no']],
  loyalty_ledger: [['idempotency_key']],
  staff_points_ledger: [['idempotency_key']],
  bookings: [['client_op_id']],
  quotations: [['client_op_id']],
  tasks: [['client_op_id']],
  task_events: [['client_op_id']],
  checklist_step_results: [['client_op_id'], ['work_order_id', 'step_key']],
  inventory_movements: [['client_op_id']],
  notifications: [['dedupe_key']],
  sync_operations: [['client_op_id']],
  reward_redemptions: [['code']],
  device_tokens: [['token']],
  profiles: [['id']],
};

function uniqueError(cols: string[]) {
  return { code: '23505', message: `duplicate key value violates unique constraint (${cols.join(',')})`, details: `Key (${cols.join(', ')}) already exists.` };
}

class QueryBuilder implements PromiseLike<{ data: any; error: any; count?: number | null }> {
  private filters: Filter[] = [];
  private op: 'select' | 'insert' | 'update' | 'upsert' | 'delete' = 'select';
  private payload: Row | Row[] | null = null;
  private orderBy: Array<{ col: string; asc: boolean }> = [];
  private limitN: number | null = null;
  private rangeFrom = 0;
  private rangeTo: number | null = null;
  private mode: 'many' | 'single' | 'maybeSingle' = 'many';
  private wantReturn = false;
  private upsertConflict: string[] | null = null;
  private ignoreDuplicates = false;

  constructor(private readonly db: FakeSupabase, private readonly table: string) {}

  select(_cols?: string) {
    if (this.op === 'select') return this;
    this.wantReturn = true;
    return this;
  }
  insert(rows: Row | Row[]) {
    this.op = 'insert';
    this.payload = rows;
    return this;
  }
  update(patch: Row) {
    this.op = 'update';
    this.payload = patch;
    return this;
  }
  upsert(rows: Row | Row[], opts?: { onConflict?: string; ignoreDuplicates?: boolean }) {
    this.op = 'upsert';
    this.payload = rows;
    this.upsertConflict = opts?.onConflict ? opts.onConflict.split(',').map((s) => s.trim()) : null;
    this.ignoreDuplicates = !!opts?.ignoreDuplicates;
    return this;
  }
  delete() {
    this.op = 'delete';
    return this;
  }
  eq(col: string, v: unknown) { this.filters.push((r) => r[col] === v); return this; }
  neq(col: string, v: unknown) { this.filters.push((r) => r[col] !== v); return this; }
  gt(col: string, v: any) { this.filters.push((r) => r[col] > v); return this; }
  gte(col: string, v: any) { this.filters.push((r) => r[col] >= v); return this; }
  lt(col: string, v: any) { this.filters.push((r) => r[col] < v); return this; }
  lte(col: string, v: any) { this.filters.push((r) => r[col] <= v); return this; }
  in(col: string, vals: unknown[]) { this.filters.push((r) => vals.includes(r[col])); return this; }
  is(col: string, v: unknown) { this.filters.push((r) => (v === null ? r[col] === null || r[col] === undefined : r[col] === v)); return this; }
  not(col: string, op: string, v: unknown) {
    if (op === 'is') this.filters.push((r) => !(v === null ? r[col] === null || r[col] === undefined : r[col] === v));
    else this.filters.push((r) => r[col] !== v);
    return this;
  }
  ilike(col: string, pattern: string) {
    const re = new RegExp('^' + pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*').replace(/_/g, '.') + '$', 'i');
    this.filters.push((r) => typeof r[col] === 'string' && re.test(r[col]));
    return this;
  }
  like(col: string, pattern: string) { return this.ilike(col, pattern); }
  or(expr: string) {
    const parts = expr.split(',').map((p) => p.trim()).filter((p) => !p.startsWith('and('));
    const fns = parts.map((p) => {
      const [col, op, ...rest] = p.split('.');
      const val = rest.join('.');
      if (op === 'ilike') {
        const re = new RegExp('^' + val.replace(/%/g, '.*') + '$', 'i');
        return (r: Row) => typeof r[col] === 'string' && re.test(r[col]);
      }
      if (op === 'eq') return (r: Row) => String(r[col]) === val;
      if (op === 'in') { const vals = val.replace(/^\(|\)$/g, '').split(','); return (r: Row) => vals.includes(String(r[col])); }
      return () => true;
    });
    this.filters.push((r) => fns.some((f) => f(r)));
    return this;
  }
  order(col: string, opts?: { ascending?: boolean }) { this.orderBy.push({ col, asc: opts?.ascending !== false }); return this; }
  limit(n: number) { this.limitN = n; return this; }
  range(from: number, to: number) { this.rangeFrom = from; this.rangeTo = to; return this; }
  single() { this.mode = 'single'; return this; }
  maybeSingle() { this.mode = 'maybeSingle'; return this; }

  private applyFilters(rows: Row[]): Row[] {
    return rows.filter((r) => this.filters.every((f) => f(r)));
  }

  private finish(rows: Row[]): { data: any; error: any } {
    let out = [...rows];
    for (const o of [...this.orderBy].reverse()) {
      out.sort((a, b) => {
        const x = a[o.col]; const y = b[o.col];
        if (x === y) return 0;
        if (x === null || x === undefined) return 1;
        if (y === null || y === undefined) return -1;
        return (x < y ? -1 : 1) * (o.asc ? 1 : -1);
      });
    }
    if (this.rangeTo !== null) out = out.slice(this.rangeFrom, this.rangeTo + 1);
    if (this.limitN !== null) out = out.slice(0, this.limitN);
    if (this.mode === 'single') {
      if (out.length !== 1) return { data: null, error: { code: 'PGRST116', message: `expected 1 row, got ${out.length}` } };
      return { data: out[0], error: null };
    }
    if (this.mode === 'maybeSingle') {
      if (out.length > 1) return { data: null, error: { code: 'PGRST116', message: `expected ≤1 row, got ${out.length}` } };
      return { data: out[0] ?? null, error: null };
    }
    return { data: out, error: null };
  }

  private execute(): { data: any; error: any } {
    const table = this.db.tables.get(this.table) ?? [];
    this.db.tables.set(this.table, table);
    this.db.calls.push({ table: this.table, op: this.op });
    switch (this.op) {
      case 'select':
        return this.finish(this.applyFilters(table).map((r) => ({ ...r })));
      case 'insert': {
        const rows = Array.isArray(this.payload) ? this.payload : [this.payload as Row];
        const inserted: Row[] = [];
        for (const r of rows) {
          const row = this.db.withDefaults(this.table, r);
          const dup = this.db.findUniqueClash(this.table, row);
          if (dup) return { data: null, error: uniqueError(dup) };
          table.push(row);
          inserted.push({ ...row });
        }
        return this.finish(this.wantReturn ? inserted : []);
      }
      case 'upsert': {
        const rows = Array.isArray(this.payload) ? this.payload : [this.payload as Row];
        const out: Row[] = [];
        for (const r of rows) {
          const cols = this.upsertConflict ?? ['id'];
          const existing = table.find((t) => cols.every((c) => t[c] === r[c]));
          if (existing) {
            if (this.ignoreDuplicates) { out.push({ ...existing }); continue; }
            Object.assign(existing, r);
            out.push({ ...existing });
          } else {
            const row = this.db.withDefaults(this.table, r);
            const dup = this.db.findUniqueClash(this.table, row);
            if (dup) return { data: null, error: uniqueError(dup) };
            table.push(row);
            out.push({ ...row });
          }
        }
        return this.finish(this.wantReturn ? out : []);
      }
      case 'update': {
        const targets = this.applyFilters(table);
        const out: Row[] = [];
        for (const t of targets) {
          const candidate = { ...t, ...(this.payload as Row) };
          const dup = this.db.findUniqueClash(this.table, candidate, t);
          if (dup) return { data: null, error: uniqueError(dup) };
        }
        for (const t of targets) {
          Object.assign(t, this.payload, { updated_at: new Date().toISOString() });
          out.push({ ...t });
        }
        return this.finish(this.wantReturn ? out : []);
      }
      case 'delete': {
        const targets = new Set(this.applyFilters(table));
        const remaining = table.filter((r) => !targets.has(r));
        this.db.tables.set(this.table, remaining);
        return this.finish(this.wantReturn ? [...targets] : []);
      }
    }
  }

  then<R1 = any, R2 = never>(onfulfilled?: ((v: { data: any; error: any }) => R1 | PromiseLike<R1>) | null, onrejected?: ((reason: any) => R2 | PromiseLike<R2>) | null): Promise<R1 | R2> {
    return Promise.resolve().then(() => this.execute()).then(onfulfilled, onrejected);
  }
}

export class FakeSupabase {
  tables = new Map<string, Row[]>();
  calls: Array<{ table: string; op: string }> = [];
  unique: Record<string, string[][]>;
  rpcs: Record<string, (args: Record<string, unknown>) => unknown>;

  constructor(opts: FakeOptions = {}) {
    this.unique = { ...DEFAULT_UNIQUE, ...(opts.unique ?? {}) };
    this.rpcs = opts.rpc ?? {};
  }

  seed(table: string, rows: Row[]) {
    this.tables.set(table, rows.map((r) => this.withDefaults(table, r)));
    return this;
  }
  rows(table: string): Row[] { return this.tables.get(table) ?? []; }
  from(table: string) { return new QueryBuilder(this, table); }
  async rpc(name: string, args: Record<string, unknown>) {
    const fn = this.rpcs[name];
    if (!fn) return { data: null, error: { code: '42883', message: `function ${name} does not exist` } };
    try { return { data: await fn(args), error: null }; } catch (e) { return { data: null, error: { message: (e as Error).message } }; }
  }

  withDefaults(table: string, r: Row): Row {
    const now = new Date().toISOString();
    const row: Row = { ...r };
    if (row.id === undefined && !['staff_outlets', 'staff_skills', 'outlet_services', 'idempotency_keys', 'feature_flags', 'notification_templates', 'staff_availability', 'loyalty_accounts', 'staff_badges'].includes(table)) row.id = randomUUID();
    if (row.created_at === undefined) row.created_at = now;
    if (row.updated_at === undefined) row.updated_at = now;
    if (table === 'bookings' && !row.ref) row.ref = `SPK-2026-${String(1000 + this.rows(table).length).padStart(4, '0')}`;
    if (table === 'work_orders' && !row.ref) row.ref = `WO-2026-${String(4000 + this.rows(table).length).padStart(4, '0')}`;
    if (table === 'quotations' && !row.ref) row.ref = `QT-2026-${String(1000 + this.rows(table).length).padStart(4, '0')}`;
    for (const k of Object.keys(row)) if (row[k] === undefined) row[k] = null;
    return row;
  }

  findUniqueClash(table: string, row: Row, exclude?: Row): string[] | null {
    const sets = this.unique[table] ?? [];
    for (const cols of sets) {
      if (cols.some((c) => row[c] === null || row[c] === undefined)) continue;
      const clash = this.rows(table).find((t) => t !== exclude && cols.every((c) => t[c] === row[c]));
      if (clash) return cols;
    }
    return null;
  }
}

export function fakeSupabase(opts?: FakeOptions): FakeSupabase {
  return new FakeSupabase(opts);
}
