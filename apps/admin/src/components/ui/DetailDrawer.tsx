'use client';
import * as React from 'react';
import Drawer from '@mui/material/Drawer';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import type { SxProps, Theme } from '@mui/material/styles';
import type { ResponsiveStyleValue } from '@mui/system';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';

export interface DetailDrawerProps {
  open: boolean;
  onClose: () => void;
  /** Paper width; full-width on xs by default. */
  width?: ResponsiveStyleValue<number | string>;
  /** Overline label rendered on the top row next to the close button, e.g. "Booking". */
  label: string;
  /** Rendered under the label — typically an h2 plus status chips. */
  title?: React.ReactNode;
  /** Secondary line under the title. */
  subtitle?: React.ReactNode;
  /** aria-label of the close button. */
  closeLabel?: string;
  /** Optional fixed footer for the primary action(s). */
  footer?: React.ReactNode;
  /** Extra styles for the scrolling body. */
  bodySx?: SxProps<Theme>;
  /** Rendered at the bottom of the fixed header (e.g. tabs or filter fields). */
  headerExtra?: React.ReactNode;
  /** Id given to the title row; the drawer's dialog is labelled by it. */
  titleId?: string;
  /** Scrolling body. */
  children?: React.ReactNode;
}

/**
 * Right-hand detail drawer with a fixed header (label + close button, title, subtitle),
 * a scrolling body and an optional fixed footer. The header always renders, so the
 * close button stays reachable while content is still loading.
 */
export default function DetailDrawer({
  open,
  onClose,
  width = { xs: '100%', sm: 460 },
  label,
  title,
  subtitle,
  closeLabel = 'Close',
  footer,
  bodySx,
  headerExtra,
  titleId,
  children,
}: DetailDrawerProps) {
  return (
    <Drawer
      anchor="right"
      open={open}
      onClose={onClose}
      slotProps={{
        paper: {
          role: 'dialog',
          'aria-labelledby': titleId,
          sx: {
            width,
            borderRadius: { xs: 0, sm: '28px 0 0 28px' },
            p: 0,
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
          },
        },
      }}
    >
      {/* Fixed header: label, title line and close button never scroll away. */}
      <Box component="header" sx={{ flexShrink: 0, px: 3, pt: 2.5, pb: 2, borderBottom: `1px solid ${tk.outlineVariant}`, bgcolor: tk.surfaceCard }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Typography variant="overline" color="text.secondary">{label}</Typography>
          <IconButton aria-label={closeLabel} onClick={onClose} edge="end"><MSymbol name="close" /></IconButton>
        </Box>
        {title != null && title !== false && (
          <Box id={titleId} sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 0.5, flexWrap: 'wrap' }}>{title}</Box>
        )}
        {subtitle != null && subtitle !== false && (
          <Typography component="div" color="text.secondary" sx={{ mt: 0.5 }}>{subtitle}</Typography>
        )}
        {headerExtra}
      </Box>

      {/* Scrolling body */}
      <Box sx={[{ flex: 1, minHeight: 0, overflowY: 'auto', overscrollBehavior: 'contain', px: 3, py: 2.5 }, ...(Array.isArray(bodySx) ? bodySx : [bodySx])]}>
        {children}
      </Box>

      {/* Fixed footer for the primary action(s) */}
      {footer != null && footer !== false && (
        <Box component="footer" sx={{ flexShrink: 0, px: 3, py: 2, borderTop: `1px solid ${tk.outlineVariant}`, bgcolor: tk.surfaceCard }}>
          {footer}
        </Box>
      )}
    </Drawer>
  );
}
