import type { UserRole } from './types';

/**
 * UI-side RBAC (the server enforces the same matrix).
 *  - admin: everything
 *  - manager: ops + config except user/flag admin and template/outlet/service CRUD
 *  - finance: read-only + exports (Messages visible, no resend)
 *  - supervisor: ops, work orders, inventory only
 */
export type Capability =
  | 'view:overview'
  | 'view:bookings'
  | 'view:quotations'
  | 'view:work_orders'
  | 'view:staff'
  | 'view:customers'
  | 'view:loyalty'
  | 'view:inventory'
  | 'view:reports'
  | 'view:config'
  | 'view:audit'
  | 'view:notifications'
  | 'notification:resend'
  | 'export:csv'
  | 'booking:cancel'
  | 'booking:create'
  | 'quote:write'
  | 'quote:convert'
  | 'task:assign'
  | 'task:transition'
  /** Explicit "car checked in" (`POST /work-orders/:id/checkin`, `POST /bookings/:id/checkin`) — ops roles. */
  | 'work_order:checkin'
  /** Counter payment attestation (`POST /payments/record`) for bookings and accepted quotations — staff / manager / admin. */
  | 'payment:record'
  | 'user:manage'
  | 'loyalty:draft'
  | 'loyalty:publish'
  /** Membership plans, enrolments, renewals (manager+). */
  | 'memberships:manage'
  | 'inventory:threshold'
  | 'inventory:movement'
  | 'catalogue:manage'
  /** Canonical service catalogue (codes, groups, composites) — admin only. */
  | 'service:manage'
  | 'template:manage'
  | 'flags:manage';

const matrix: Record<Exclude<UserRole, 'customer' | 'technician'>, Set<Capability>> = {
  admin: new Set<Capability>([
    'view:overview', 'view:bookings', 'view:quotations', 'view:work_orders', 'view:staff', 'view:customers',
    'view:loyalty', 'view:inventory', 'view:reports', 'view:config', 'view:audit', 'view:notifications', 'export:csv',
    'booking:cancel', 'booking:create', 'quote:write', 'quote:convert', 'task:assign', 'task:transition', 'work_order:checkin', 'payment:record', 'user:manage',
    'loyalty:draft', 'loyalty:publish', 'memberships:manage', 'inventory:threshold', 'inventory:movement', 'catalogue:manage', 'service:manage',
    'template:manage', 'flags:manage', 'notification:resend',
  ]),
  manager: new Set<Capability>([
    'view:overview', 'view:bookings', 'view:quotations', 'view:work_orders', 'view:staff', 'view:customers',
    'view:loyalty', 'view:inventory', 'view:reports', 'view:config', 'view:audit', 'view:notifications', 'export:csv',
    'booking:cancel', 'booking:create', 'quote:write', 'quote:convert', 'task:assign', 'task:transition', 'work_order:checkin', 'payment:record',
    'loyalty:draft', 'memberships:manage', 'inventory:threshold', 'inventory:movement', 'notification:resend',
  ]),
  finance: new Set<Capability>([
    'view:overview', 'view:bookings', 'view:quotations', 'view:customers', 'view:loyalty', 'view:inventory',
    'view:reports', 'view:audit', 'view:notifications', 'export:csv',
  ]),
  supervisor: new Set<Capability>([
    'view:overview', 'view:work_orders', 'view:inventory', 'view:bookings', 'view:quotations',
    'booking:create', 'quote:write', 'quote:convert', 'task:assign', 'task:transition', 'work_order:checkin', 'payment:record', 'inventory:movement',
  ]),
};

export function can(role: UserRole | null | undefined, cap: Capability): boolean {
  if (!role || role === 'customer' || role === 'technician') return false;
  return matrix[role].has(cap);
}

export const roleLabel: Record<UserRole, string> = {
  customer: 'Customer',
  technician: 'Technician',
  supervisor: 'Supervisor',
  manager: 'Manager',
  admin: 'Admin',
  finance: 'Finance',
};
