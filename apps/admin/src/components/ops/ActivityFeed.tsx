'use client';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import SectionCard from '@/components/ui/SectionCard';
import IconTile from '@/components/ui/IconTile';
import { LoadingRows } from '@/components/ui/States';
import { fmtTime } from '@/lib/format';
import type { ActivityItem } from '@/lib/types';

const toneMap = { success: 'success', primary: 'primary', warning: 'warning', error: 'error', neutral: 'neutral' } as const;

/** Live feed derived from task/payment/loyalty/inventory events (README §3d). */
export default function ActivityFeed({ items }: { items: ActivityItem[] | undefined }) {
  return (
    <SectionCard title="Live activity" sx={{ minHeight: 320 }}>
      {!items ? (
        <LoadingRows rows={5} height={52} />
      ) : (
        <Box component="ol" aria-live="polite" aria-relevant="additions" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 1.5 }}>
          {items.map((a) => (
            <Box component="li" key={a.id} sx={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
              <IconTile icon={a.icon} tone={toneMap[a.tone]} size={44} />
              <Box sx={{ minWidth: 0 }}>
                <Typography variant="h5" component="p" noWrap>{a.title}</Typography>
                <Typography variant="body2" color="text.secondary" noWrap>{a.subtitle} · {fmtTime(a.at)}</Typography>
              </Box>
            </Box>
          ))}
        </Box>
      )}
    </SectionCard>
  );
}
