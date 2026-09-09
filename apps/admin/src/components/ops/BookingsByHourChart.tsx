'use client';
import Box from '@mui/material/Box';
import { BarChart } from '@mui/x-charts/BarChart';
import { useTheme } from '@mui/material/styles';
import SectionCard from '@/components/ui/SectionCard';
import { LegendDot } from '@/components/ui/Pills';
import { brand, tk } from '@/theme/tokens';
import { useDocumentHidden, useReducedMotion } from '@/lib/hooks';
import type { Kpis } from '@/lib/types';

/** Stacked bars: car wash #006398 / auto body #8BD2FF; future hours at 40% opacity (README §3a). */
export default function BookingsByHourChart({ data }: { data: Kpis['bookings_by_hour'] | undefined }) {
  const theme = useTheme();
  const reduced = useReducedMotion();
  const hidden = useDocumentHidden();
  const rows = data ?? [];
  const currentHour = new Date().getHours();
  const labels = rows.map((r) => String(r.hour).padStart(2, '0'));
  const past = (k: 'car_wash' | 'auto_body') => rows.map((r) => (r.future ? 0 : r[k]));
  const future = (k: 'car_wash' | 'auto_body') => rows.map((r) => (r.future ? r[k] : 0));
  const alpha = (hex: string) => `${hex}66`; // 40% opacity

  return (
    <SectionCard
      title="Bookings by hour"
      actions={
        <Box sx={{ display: 'flex', gap: 2 }}>
          <LegendDot color={brand.chartCarWash} label="Car wash" />
          <LegendDot color={brand.chartAutoBody} label="Auto body" />
        </Box>
      }
      sx={{ minHeight: 320 }}
    >
      <Box sx={{ height: 260, width: '100%', '& .MuiChartsAxis-tickLabel': { fontFamily: theme.typography.fontFamily } }}>
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
            { id: 'cwf', label: 'Car wash (upcoming)', data: future('car_wash'), stack: 'h', color: alpha(brand.chartCarWash) },
            { id: 'abf', label: 'Auto body (upcoming)', data: future('auto_body'), stack: 'h', color: alpha(brand.chartAutoBody) },
          ]}
          slotProps={{ tooltip: { trigger: 'axis' } }}
          sx={{
            [`& .MuiChartsAxis-tickLabel[data-index="${labels.indexOf(String(currentHour).padStart(2, '0'))}"]`]: { fill: tk.primary, fontWeight: 700 },
          }}
        />
      </Box>
    </SectionCard>
  );
}
