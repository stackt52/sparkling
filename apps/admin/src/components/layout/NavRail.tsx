'use client';
import * as React from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import Box from '@mui/material/Box';
import ButtonBase from '@mui/material/ButtonBase';
import Avatar from '@mui/material/Avatar';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import ListItemIcon from '@mui/material/ListItemIcon';
import ListItemText from '@mui/material/ListItemText';
import Divider from '@mui/material/Divider';
import Typography from '@mui/material/Typography';
import { useColorScheme } from '@mui/material/styles';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';
import { useAuth } from '@/lib/auth/AuthProvider';
import { can, roleLabel } from '@/lib/rbac';
import { initials } from '@/lib/format';
import { ADMIN_ROLES } from '@/lib/types';
import { NAV_ITEMS, isActive } from './nav';

export const RAIL_WIDTH = 84;

export function Logo({ height = 30 }: { height?: number }) {
  return (
    <Box sx={{ position: 'relative', height, width: height * 2.7, display: 'block' }}>
      <Image src="/logo-light.png" alt="Sparkling" fill sizes="120px" style={{ objectFit: 'contain' }} className="logo-light" priority />
      <Image src="/logo-dark.png" alt="" fill sizes="120px" style={{ objectFit: 'contain' }} className="logo-dark" priority />
      <style>{`
        .logo-dark{display:none}
        [data-mui-color-scheme="dark"] .logo-light{display:none}
        [data-mui-color-scheme="dark"] .logo-dark{display:block}
      `}</style>
    </Box>
  );
}

export function NavDestination({ item, active, horizontal, onNavigate }: { item: (typeof NAV_ITEMS)[number]; active: boolean; horizontal?: boolean; onNavigate?: () => void }) {
  return (
    <ButtonBase
      component={Link}
      href={item.href}
      onClick={onNavigate}
      aria-current={active ? 'page' : undefined}
      sx={{
        display: 'flex',
        flexDirection: horizontal ? 'row' : 'column',
        alignItems: 'center',
        gap: horizontal ? 1.5 : 0.5,
        width: horizontal ? '100%' : 72,
        justifyContent: horizontal ? 'flex-start' : 'center',
        px: horizontal ? 2 : 0,
        py: horizontal ? 1 : 0.75,
        borderRadius: horizontal ? '999px' : '16px',
        color: active ? tk.onSurface : tk.onSurfaceVariant,
        fontFamily: 'inherit',
        ...(horizontal && active && { bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer }),
        '&:focus-visible': { outline: `3px solid ${tk.primary}`, outlineOffset: -3 },
      }}
    >
      <Box
        sx={{
          width: horizontal ? 40 : 56,
          height: horizontal ? 40 : 30,
          borderRadius: 999,
          display: 'grid',
          placeItems: 'center',
          bgcolor: active && !horizontal ? tk.primaryContainer : 'transparent',
          color: active ? (horizontal ? tk.onPrimaryContainer : tk.primary) : tk.onSurfaceVariant,
          transition: 'background-color 200ms',
          '.MuiButtonBase-root:hover &': { bgcolor: active ? tk.primaryContainer : tk.surfaceContainerHigh },
        }}
      >
        <MSymbol name={item.icon} filled={active} size={24} />
      </Box>
      <Typography component="span" sx={{ fontSize: horizontal ? 14 : 12, fontWeight: active ? 700 : 500, lineHeight: 1.2 }}>
        {item.label}
      </Typography>
    </ButtonBase>
  );
}

export function UserMenu({ compact }: { compact?: boolean }) {
  const { profile, role, signOut, isDemo, switchDemoRole } = useAuth();
  const { mode, setMode } = useColorScheme();
  const [anchor, setAnchor] = React.useState<null | HTMLElement>(null);
  const name = profile?.full_name ?? 'Admin';
  const nextMode = mode === 'dark' ? 'light' : 'dark';
  return (
    <>
      <ButtonBase
        onClick={(e) => setAnchor(e.currentTarget)}
        aria-label={`Account menu for ${name}`}
        aria-haspopup="menu"
        aria-expanded={Boolean(anchor)}
        sx={{ borderRadius: 999, display: 'flex', alignItems: 'center', gap: 1.5, p: compact ? 0.5 : 0 }}
      >
        <Avatar sx={{ width: compact ? 40 : 64, height: compact ? 40 : 64, bgcolor: tk.secondary, color: tk.onSecondary, fontWeight: 700, fontSize: compact ? 15 : 20 }}>
          {initials(name)}
        </Avatar>
        {compact && (
          <Box sx={{ textAlign: 'left' }}>
            <Typography variant="subtitle2">{name}</Typography>
            <Typography variant="caption" color="text.secondary">{role ? roleLabel[role] : ''}</Typography>
          </Box>
        )}
      </ButtonBase>
      <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)} anchorOrigin={{ vertical: 'top', horizontal: 'right' }} transformOrigin={{ vertical: 'bottom', horizontal: 'left' }}>
        <Box sx={{ px: 2, py: 1 }}>
          <Typography variant="subtitle2">{name}</Typography>
          <Typography variant="caption" color="text.secondary">{profile?.email} · {role ? roleLabel[role] : ''}</Typography>
        </Box>
        <Divider sx={{ my: 0.5 }} />
        <MenuItem onClick={() => { setMode(nextMode); }}>
          <ListItemIcon><MSymbol name={mode === 'dark' ? 'light_mode' : 'dark_mode'} size={20} /></ListItemIcon>
          <ListItemText>{mode === 'dark' ? 'Light theme' : 'Dark theme'}</ListItemText>
        </MenuItem>
        <MenuItem onClick={() => { setMode('system'); }} selected={mode === 'system'}>
          <ListItemIcon><MSymbol name="contrast" size={20} /></ListItemIcon>
          <ListItemText>Follow system</ListItemText>
        </MenuItem>
        {isDemo && <Divider sx={{ my: 0.5 }} />}
        {isDemo && (
          <Box sx={{ px: 2, pt: 0.5 }}>
            <Typography variant="overline" color="text.secondary">Demo role</Typography>
          </Box>
        )}
        {isDemo &&
          ADMIN_ROLES.map((r) => (
            <MenuItem key={r} selected={r === role} onClick={() => { switchDemoRole(r); setAnchor(null); }}>
              <ListItemIcon><MSymbol name={r === role ? 'radio_button_checked' : 'radio_button_unchecked'} size={20} /></ListItemIcon>
              <ListItemText>{roleLabel[r]}</ListItemText>
            </MenuItem>
          ))}
        <Divider sx={{ my: 0.5 }} />
        <MenuItem onClick={() => { setAnchor(null); void signOut(); }}>
          <ListItemIcon><MSymbol name="logout" size={20} /></ListItemIcon>
          <ListItemText>Sign out</ListItemText>
        </MenuItem>
      </Menu>
    </>
  );
}

/** 84px Material 3 navigation rail (desktop ≥ 900px). */
export default function NavRail() {
  const pathname = usePathname();
  const { role } = useAuth();
  const items = NAV_ITEMS.filter((i) => can(role, i.cap));
  return (
    <Box
      component="nav"
      aria-label="Primary"
      sx={{
        width: RAIL_WIDTH,
        flexShrink: 0,
        position: 'sticky',
        top: 0,
        height: '100vh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        bgcolor: tk.surfaceContainer,
        borderRight: `1px solid ${tk.outlineVariant}`,
        py: 2,
        gap: 1,
        overflowY: 'auto',
        overflowX: 'hidden',
      }}
    >
      <Link href="/" aria-label="Sparkling home" style={{ display: 'block', marginBottom: 8 }}>
        <Logo height={28} />
      </Link>
      <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.75, flex: 1 }}>
        {items.map((item) => (
          <NavDestination key={item.href} item={item} active={isActive(item, pathname)} />
        ))}
      </Box>
      <UserMenu />
    </Box>
  );
}
