'use client';
import Link from 'next/link';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import SectionCard from '@/components/ui/SectionCard';
import Tile from '@/components/ui/Tile';
import MSymbol from '@/components/MSymbol';
import { EmptyState, LoadingRows } from '@/components/ui/States';
import type { ExceptionItem } from '@/lib/types';

export function exceptionHref(e: ExceptionItem): string {
  switch (e.link.type) {
    case 'work_order':
      return `/work-orders?focus=${e.link.id}`;
    case 'inventory_item':
      return `/inventory?focus=${e.link.id}`;
    case 'payment':
      return `/reports?tab=payments&focus=${e.link.id}`;
    default:
      return `/bookings?focus=${e.link.id}`;
  }
}

/** Tinted rows linking to the underlying record (ADM-011/013). */
export default function ExceptionsList({ items, loading }: { items: ExceptionItem[] | undefined; loading?: boolean }) {
  return (
    <SectionCard title="Exceptions" sx={{ minHeight: 320 }}>
      {loading && !items ? (
        <LoadingRows rows={4} height={64} />
      ) : !items?.length ? (
        <EmptyState icon="task_alt" title="No open exceptions" description="Blocked work, SLA breaches, stock-outs and failed payments will appear here." />
      ) : (
        <Box component="ul" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 1.25, maxHeight: 560, overflowY: 'auto', pr: 0.5 }}>
          {items.map((e) => (
            <li key={e.id}>
              <Link href={exceptionHref(e)} aria-label={`${e.title}. ${e.subtitle}. Open record`} style={{ display: 'block', borderRadius: 18 }}>
              <Tile tone={e.severity === 'error' ? 'error' : 'warning'} interactive sx={{ minHeight: 68 }}>
                <Box sx={{ width: 30, height: 30, borderRadius: '50%', bgcolor: e.severity === 'error' ? 'var(--mui-palette-container-onError)' : 'var(--mui-palette-container-onWarning)', color: e.severity === 'error' ? 'var(--mui-palette-container-error)' : 'var(--mui-palette-container-warning)', display: 'grid', placeItems: 'center', flexShrink: 0 }}>
                  <MSymbol name={e.icon} filled size={18} />
                </Box>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography variant="h5" component="p" sx={{ color: 'inherit' }}>{e.title}</Typography>
                  <Typography variant="body2" sx={{ color: 'inherit', opacity: 0.85 }}>{e.subtitle}</Typography>
                </Box>
                <MSymbol name="chevron_right" size={22} />
              </Tile>
              </Link>
            </li>
          ))}
        </Box>
      )}
    </SectionCard>
  );
}
