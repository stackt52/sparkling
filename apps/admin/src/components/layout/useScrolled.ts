'use client';
import * as React from 'react';

/**
 * True once the dashboard's scroll container (`#main`) has scrolled past `threshold` px.
 * Used to switch fixed chrome (page header, compact top bar) to a translucent, blurred
 * surface while content moves underneath it.
 */
export default function useScrolled(threshold = 4): boolean {
  const [scrolled, setScrolled] = React.useState(false);

  React.useEffect(() => {
    const el = document.getElementById('main');
    if (!el) return;
    // Plain state update: React batches these, and it keeps working in background tabs
    // where requestAnimationFrame callbacks are paused.
    const onScroll = () => setScrolled(el.scrollTop > threshold);
    onScroll();
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => el.removeEventListener('scroll', onScroll);
  }, [threshold]);

  return scrolled;
}

/** Shared sx for translucent chrome: surface colour at ~72% with a backdrop blur. */
export const translucentSurface = (surface: string, scrolled: boolean) => ({
  bgcolor: scrolled ? `color-mix(in srgb, ${surface} 72%, transparent)` : surface,
  backdropFilter: scrolled ? 'saturate(160%) blur(14px)' : 'none',
  WebkitBackdropFilter: scrolled ? 'saturate(160%) blur(14px)' : 'none',
  transition: 'background-color 200ms ease, box-shadow 200ms ease, border-color 200ms ease',
});
