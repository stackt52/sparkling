'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import { useAuth } from '@/lib/auth/AuthProvider';
import { can, type Capability } from '@/lib/rbac';

const TABS: { href: string; label: string; cap: Capability }[] = [
  { href: '/settings', label: 'Settings', cap: 'view:config' },
  { href: '/outlets', label: 'Outlets', cap: 'view:config' },
  { href: '/services', label: 'Services', cap: 'view:config' },
  { href: '/templates', label: 'Checklists', cap: 'view:config' },
  { href: '/audit', label: 'Audit log', cap: 'view:audit' },
];

/** Sub-navigation shared by the configuration screens. */
export default function ConfigTabs() {
  const pathname = usePathname();
  const { role } = useAuth();
  const tabs = TABS.filter((t) => can(role, t.cap));
  const idx = Math.max(0, tabs.findIndex((t) => pathname === t.href || pathname.startsWith(`${t.href}/`)));
  return (
    <Tabs value={idx} aria-label="Configuration sections" variant="scrollable" allowScrollButtonsMobile>
      {tabs.map((t) => <Tab key={t.href} label={t.label} component={Link} href={t.href} />)}
    </Tabs>
  );
}
