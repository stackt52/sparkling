import type { QuoteItemCategory } from '@/lib/types';
import type { Tone } from '@/components/ui/StatusChip';

/** Presentation of the per-item attention-area categories (shared by the drawer, the Raise-quote flow and the public page). */
export const QUOTE_CATEGORY_META: Record<QuoteItemCategory, { label: string; icon: string; tone: Tone }> = {
  dent: { label: 'Dent', icon: 'car_crash', tone: 'warning' },
  scratch: { label: 'Scratch', icon: 'gesture', tone: 'warning' },
  bumper: { label: 'Bumper', icon: 'front_loader', tone: 'primary' },
  panel: { label: 'Panel', icon: 'view_agenda', tone: 'primary' },
  paint: { label: 'Paint', icon: 'format_paint', tone: 'secondary' },
  glass: { label: 'Glass', icon: 'window', tone: 'secondary' },
  other: { label: 'Other', icon: 'build', tone: 'neutral' },
};

export function categoryMeta(category: string | null | undefined) {
  if (!category) return null;
  const key = category.toLowerCase() as QuoteItemCategory;
  return QUOTE_CATEGORY_META[key] ?? { label: category.charAt(0).toUpperCase() + category.slice(1), icon: 'build', tone: 'neutral' as Tone };
}

/** Quotation-level category label (`Bumper`, `Dent`…) from the first item, matching the customer app's request chips. */
export function quotationCategoryFromItems(items: { category?: string | null }[]): string {
  const first = items.find((i) => i.category)?.category;
  return first ? first.charAt(0).toUpperCase() + first.slice(1) : 'Other';
}
