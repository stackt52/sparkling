'use client';
import * as React from 'react';
import { usePathname } from 'next/navigation';
import Box from '@mui/material/Box';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import useMediaQuery from '@mui/material/useMediaQuery';
import MSymbol from '@/components/MSymbol';
import { spacing, tk } from '@/theme/tokens';
import { useAuth } from '@/lib/auth/AuthProvider';
import { can } from '@/lib/rbac';
import NavRail, { Logo, NavDestination, UserMenu } from './NavRail';
import { NAV_ITEMS, isActive } from './nav';

/** Rail on desktop; collapses to a top bar + modal drawer under 900px (UX-005). */
export default function AppShell({ children }: { children: React.ReactNode }) {
  const compact = useMediaQuery('(max-width:899.95px)');
  const [open, setOpen] = React.useState(false);
  const pathname = usePathname();
  const { role } = useAuth();
  const items = NAV_ITEMS.filter((i) => can(role, i.cap));

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: tk.surface }}>
      {!compact && <NavRail />}
      {compact && (
        <>
          <Box component="header" sx={{ position: 'fixed', top: 0, left: 0, right: 0, height: 60, display: 'flex', alignItems: 'center', gap: 1, px: 1.5, bgcolor: tk.surfaceContainer, borderBottom: `1px solid ${tk.outlineVariant}`, zIndex: (t) => t.zIndex.appBar }}>
            <IconButton aria-label="Open navigation" onClick={() => setOpen(true)} sx={{ color: tk.onSurface }}>
              <MSymbol name="menu" />
            </IconButton>
            <Logo height={26} />
            <Box sx={{ flex: 1 }} />
            <UserMenu compact />
          </Box>
          <Drawer open={open} onClose={() => setOpen(false)} slotProps={{ paper: { sx: { width: 280, p: 2, borderRadius: '0 28px 28px 0' } } }}>
            <Box sx={{ px: 1, py: 1.5 }}><Logo height={30} /></Box>
            <Box component="nav" aria-label="Primary" sx={{ display: 'flex', flexDirection: 'column', gap: 0.5, mt: 1 }}>
              {items.map((item) => (
                <NavDestination key={item.href} item={item} active={isActive(item, pathname)} horizontal onNavigate={() => setOpen(false)} />
              ))}
            </Box>
          </Drawer>
        </>
      )}
      <Box component="main" id="main" sx={{ flex: 1, minWidth: 0, px: { xs: 2, sm: `${spacing.gutter}px` }, pb: { xs: 2, md: 3 }, pt: compact ? '76px' : { xs: 2, md: 3 }, display: 'flex', flexDirection: 'column', gap: `${spacing.cardGap}px` }}>
        {children}
      </Box>
    </Box>
  );
}
