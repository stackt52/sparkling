'use client';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import { BarChart } from '@mui/x-charts/BarChart';
import { useTheme } from '@mui/material/styles';
import SectionCard from '@/components/ui/SectionCard';
import { LegendDot } from '@/components/ui/Pills';
import { brand, tk } from '@/theme/tokens';
import { useFilters } from '@/lib/filters';
import { useDocumentHidden, useReducedMotion } from '@/lib/hooks';
import type { Kpis, Period } from '@/lib/types';

const PERIOD_SUBTITLE: Record<Period, string> = { today: 'Today', week: 'This week', month: 'This month' };
const alpha = (hex: string) => `${hex}66`; // 40% opacity

/**
 * Stacked bars: car wash #006398 / auto body #8BD2FF (README §3a). The series is the hour-of-day distribution of the
 * bookings in the header's period (`GET /admin/kpis?period=`), so "This week" / "This month" stack bookings from other
 * days on the same hour. Hours still to come are drawn at 40 % opacity — only on today's chart, where `future` means something.
 */
export default function BookingsByHourChart({ data }: { data: Kpis['bookings_by_hour'] | undefined }) {
  const theme = useTheme();
  const reduced = useReducedMotion();
  const hidden = useDocumentHidden();
  const { period } = useFilters();
  const isToday = period === 'today';
  const rows = data ?? [];
  const empty = data !== undefined && rows.every((r) => r.car_wash + r.auto_body === 0);
  const currentHour = new Date().getHours();
  const labels = rows.map((r) => String(r.hour).padStart(2, '0'));
  const upcoming = (r: Kpis['bookings_by_hour'][number]) => isToday && r.future;
  const past = (k: 'car_wash' | 'auto_body') => rows.map((r) => (upcoming(r) ? 0 : r[k]));
  const future = (k: 'car_wash' | 'auto_body') => rows.map((r) => (upcoming(r) ? r[k] : 0));

  return (
    <SectionCard
      title="Bookings by hour"
      subtitle={PERIOD_SUBTITLE[period]}
      actions={
        <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
          <LegendDot color={brand.chartCarWash} label="Car wash" />
          <LegendDot color={brand.chartAutoBody} label="Auto body" />
          {isToday && <LegendDot color={alpha(brand.chartCarWash)} label="Car wash (upcoming)" />}
          {isToday && <LegendDot color={alpha(brand.chartAutoBody)} label="Auto body (upcoming)" />}
        </Box>
      }
      sx={{ minHeight: 320 }}
    >
      <Box data-testid="bookings-by-hour" data-period={period} sx={{ height: 260, width: '100%', '& .MuiChartsAxis-tickLabel': { fontFamily: theme.typography.fontFamily } }}>
        {empty ? (
          <Box sx={{ height: '100%', display: 'grid', placeItems: 'center' }}>
            <Typography variant="body2" color="text.secondary" data-testid="bookings-by-hour-empty">No bookings in this period</Typography>
          </Box>
        ) : (
          <BarChart
            skipAnimation={reduced || hidden}
            hideLegend
            borderRadius={10}
            margin={{ top: 8, bottom: 8, left: 8, right: 8 }}
            xAxis={[{ scaleType: 'band', data: labels, categoryGapRatio: 0.35, disableLine: true, disableTicks: true, tickLabelStyle: { fontSize: 13, fontWeight: 600, fill: tk.onSurfaceVariant } }]}
            yAxis={[{ position: 'none' }]}
            series={[
              { id: 'cw', label: 'Car wash', data: past('car_wash'), stack: 'h', color: brand.chartCarWash },
              { id: 'ab', label: 'Auto body', data: past('auto_body'), stack: 'h', color: brand.chartAutoBody },
              ...(isToday
                ? [
                    { id: 'cwf', label: 'Car wash (upcoming)', data: future('car_wash'), stack: 'h', color: alpha(brand.chartCarWash) },
                    { id: 'abf', label: 'Auto body (upcoming)', data: future('auto_body'), stack: 'h', color: alpha(brand.chartAutoBody) },
                  ]
                : []),
            ]}
            slotProps={{ tooltip: { trigger: 'axis' } }}
            sx={isToday ? { [`& .MuiChartsAxis-tickLabel[data-index="${labels.indexOf(String(currentHour).padStart(2, '0'))}"]`]: { fill: tk.primary, fontWeight: 700 } } : undefined}
          />
        )}
      </Box>
    </SectionCard>
  );
}
