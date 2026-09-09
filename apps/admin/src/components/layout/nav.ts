import type { Capability } from '@/lib/rbac';

export interface NavItem {
  href: string;
  label: string;
  icon: string;
  cap: Capability;
  /** Path prefixes that keep this destination active. */
  match?: string[];
}

export const NAV_ITEMS: NavItem[] = [
  { href: '/', label: 'Overview', icon: 'dashboard', cap: 'view:overview' },
  { href: '/bookings', label: 'Bookings', icon: 'calendar_month', cap: 'view:bookings' },
  { href: '/quotations', label: 'Quotes', icon: 'request_quote', cap: 'view:quotations' },
  { href: '/work-orders', label: 'Work', icon: 'checklist', cap: 'view:work_orders' },
  { href: '/staff', label: 'Staff', icon: 'groups', cap: 'view:staff', match: ['/staff'] },
  { href: '/customers', label: 'Customers', icon: 'person_search', cap: 'view:customers' },
  { href: '/loyalty', label: 'Loyalty', icon: 'loyalty', cap: 'view:loyalty' },
  { href: '/inventory', label: 'Stock', icon: 'inventory_2', cap: 'view:inventory' },
  { href: '/reports', label: 'Reports', icon: 'monitoring', cap: 'view:reports' },
  { href: '/settings', label: 'Config', icon: 'settings', cap: 'view:config', match: ['/settings', '/outlets', '/services', '/templates', '/audit'] },
];

export function isActive(item: NavItem, pathname: string): boolean {
  if (item.href === '/') return pathname === '/';
  return (item.match ?? [item.href]).some((m) => pathname === m || pathname.startsWith(`${m}/`));
}
