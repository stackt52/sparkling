'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Divider from '@mui/material/Divider';
import Skeleton from '@mui/material/Skeleton';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import IconButton from '@mui/material/IconButton';
import CircularProgress from '@mui/material/CircularProgress';
import Tooltip from '@mui/material/Tooltip';
import { useColorScheme } from '@mui/material/styles';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { differenceInCalendarDays, format, parseISO } from 'date-fns';
import MSymbol from '@/components/MSymbol';
import { Logo } from '@/components/layout/Logo';
import IconTile from '@/components/ui/IconTile';
import StatusChip from '@/components/ui/StatusChip';
import Toast from '@/components/ui/Toast';
import PhotoLightbox from '@/components/quotations/PhotoLightbox';
import { categoryMeta } from '@/components/quotations/quoteCategories';
import { ApiRequestError } from '@/lib/api';
import { copyText } from '@/lib/clipboard';
import { downloadBlob } from '@/lib/csv';
import { isDemo } from '@/lib/env';
import { fmtDate, rands } from '@/lib/format';
import { formatPhone, normalisePhone } from '@/lib/phone';
import { useHydrated, useToast } from '@/lib/hooks';
import { decidePublicQuotation, getPublicQuotation, publicPdfBlob, publicPdfHref, publicPhotoUrl } from '@/lib/publicQuote';
import { fonts, shape, tk } from '@/theme/tokens';
import type { PublicQuotation } from '@/lib/types';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'ready'; view: PublicQuotation }
  | { kind: 'not_found' }
  | { kind: 'expired'; ref: string | null }
  | { kind: 'error'; message: string };

const CONTENT_MAX = 560;

const sourceLabel = (s: PublicQuotation['decision_source']) => (s === 'public_link' ? 'via this link' : s === 'app' ? 'in the Sparkling app' : s === 'staff' ? 'at the counter' : '');
const fullDate = (iso: string | null | undefined) => (iso ? format(parseISO(iso), 'd MMM yyyy, HH:mm') : '—');

/* ------------------------------------------------------------------ */
/* Chrome (header / footer / theme toggle)                              */
/* ------------------------------------------------------------------ */

function ModeToggle() {
  const { mode, setMode } = useColorScheme();
  const hydrated = useHydrated();
  if (!hydrated) return <Box sx={{ width: 40, height: 40 }} />;
  const dark = mode === 'dark' || (mode === 'system' && typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  return (
    <Tooltip title={dark ? 'Switch to light' : 'Switch to dark'}>
      <IconButton aria-label={dark ? 'Switch to light mode' : 'Switch to dark mode'} onClick={() => setMode(dark ? 'light' : 'dark')} sx={{ color: tk.onSurfaceVariant }}>
        <MSymbol name={dark ? 'light_mode' : 'dark_mode'} size={22} />
      </IconButton>
    </Tooltip>
  );
}

function Shell({ children, footer, bottomBar }: { children: React.ReactNode; footer?: React.ReactNode; bottomBar?: boolean }) {
  return (
    <Box sx={{ minHeight: '100dvh', bgcolor: tk.surface, color: tk.onSurface, display: 'flex', flexDirection: 'column', pb: bottomBar ? 11 : 0 }}>
      <Box component="header" sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', px: 2, py: 1.5, maxWidth: CONTENT_MAX, width: '100%', mx: 'auto' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25 }}>
          <Logo height={30} />
          {isDemo() && <Chip size="small" label="Demo" sx={{ bgcolor: tk.goldLight, color: tk.onGold, height: 22 }} />}
        </Box>
        <ModeToggle />
      </Box>
      <Box component="main" id="main" sx={{ flex: 1, width: '100%', maxWidth: CONTENT_MAX, mx: 'auto', px: 2, display: 'flex', flexDirection: 'column', gap: 1.75, pb: 3 }}>
        {children}
      </Box>
      <Box component="footer" sx={{ maxWidth: CONTENT_MAX, width: '100%', mx: 'auto', px: 2, pb: 3, pt: 1, textAlign: 'center' }}>
        <Typography variant="caption" color="text.secondary" component="p">{footer ?? 'Sparkling Auto Care Centres'}</Typography>
      </Box>
    </Box>
  );
}

function DownloadPdf({ token, view, refLabel, variant = 'outlined' }: { token: string; view: PublicQuotation | null; refLabel: string; variant?: 'outlined' | 'text' }) {
  const [busy, setBusy] = React.useState(false);
  const toast = useToast();
  const href = view ? publicPdfHref(view) : null;
  const filename = `${refLabel || 'quotation'}.pdf`;
  if (href) {
    return (
      <Button component="a" href={href} download={filename} target="_blank" rel="noopener" variant={variant} startIcon={<MSymbol name="download" size={20} />} sx={{ px: 2.5 }}>
        Download PDF
      </Button>
    );
  }
  return (
    <>
      <Button
        variant={variant}
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          try {
            downloadBlob(filename, await publicPdfBlob(token));
          } catch (e) {
            toast.error(e);
          } finally {
            setBusy(false);
          }
        }}
        startIcon={busy ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="download" size={20} />}
        sx={{ px: 2.5 }}
      >
        Download PDF
      </Button>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/* ------------------------------------------------------------------ */
/* Cards                                                                */
/* ------------------------------------------------------------------ */

function HeroCard({ view }: { view: PublicQuotation }) {
  const vehicle = [view.vehicle.make, view.vehicle.model, view.vehicle.colour].filter(Boolean).join(' · ');
  return (
    <Box component="section" aria-label="Quotation summary" sx={{ borderRadius: `${shape.dialog}px`, background: tk.heroGradient, color: '#FFFFFF', p: 2.5, display: 'flex', flexDirection: 'column', gap: 1.5, position: 'relative', overflow: 'hidden' }}>
      <Box sx={{ position: 'absolute', right: -40, top: -40, width: 160, height: 160, borderRadius: '50%', bgcolor: 'rgba(255,255,255,0.08)' }} aria-hidden />
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
        <Typography variant="overline" sx={{ opacity: 0.8 }}>Quotation</Typography>
        <StatusChip status={view.status} sx={{ bgcolor: 'rgba(255,255,255,0.16)', color: '#FFFFFF' }} />
      </Box>
      <Box>
        <Typography component="h1" sx={{ fontFamily: fonts.mono, fontWeight: 700, fontSize: 26, letterSpacing: '0.02em', lineHeight: 1.1 }}>{view.ref}</Typography>
        <Typography sx={{ mt: 0.5, opacity: 0.9, fontSize: 15 }}>{view.outlet.name}</Typography>
      </Box>
      <Typography sx={{ fontSize: 15 }}>Prepared for <b>{view.customer.first_name}</b></Typography>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, flexWrap: 'wrap' }}>
        <Box component="span" sx={{ fontFamily: fonts.mono, fontWeight: 700, fontSize: 15, letterSpacing: '0.04em', bgcolor: 'rgba(255,255,255,0.92)', color: tk.navy, borderRadius: '10px', px: 1.25, py: 0.5 }}>{view.vehicle.registration_no}</Box>
        {vehicle && <Typography sx={{ opacity: 0.9, fontSize: 14 }}>{vehicle}</Typography>}
      </Box>
    </Box>
  );
}

function ItemsCard({ view }: { view: PublicQuotation }) {
  const days = view.valid_until ? differenceInCalendarDays(parseISO(view.valid_until), new Date()) : null;
  const validity = days === null ? null : days < 0 ? 'Expired' : days === 0 ? 'Last day to decide' : `${days} day${days === 1 ? '' : 's'} left`;
  const urgent = days !== null && days <= 3;
  return (
    <Paper component="section" aria-labelledby="items-title" sx={{ p: 2.5 }}>
      <Typography id="items-title" variant="h4" component="h2">What needs attention</Typography>
      <Box component="ul" sx={{ listStyle: 'none', p: 0, m: 0, mt: 1.5, display: 'flex', flexDirection: 'column', gap: 1.5 }}>
        {view.items.map((it, i) => {
          const meta = categoryMeta(it.category);
          const qty = it.quantity ?? 1;
          return (
            <Box component="li" key={i} sx={{ display: 'flex', gap: 1.5, alignItems: 'flex-start' }}>
              <Box sx={{ flex: 1, minWidth: 0 }}>
                {meta && <StatusChip tone={meta.tone} label={meta.label} icon={<MSymbol name={meta.icon} size={14} filled />} sx={{ mb: 0.75 }} />}
                <Typography variant="h5" component="p">{it.label}{qty > 1 ? ` × ${qty}` : ''}</Typography>
                {it.description && <Typography variant="body2" color="text.secondary" sx={{ mt: 0.25 }}>{it.description}</Typography>}
              </Box>
              <Typography sx={{ fontWeight: 600, whiteSpace: 'nowrap', pt: meta ? 3.75 : 0 }}>{rands(it.amount_cents * qty, { decimals: true })}</Typography>
            </Box>
          );
        })}
      </Box>
      <Divider sx={{ borderStyle: 'dashed', my: 2 }} />
      <Box sx={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 2 }}>
        <Box>
          <Typography variant="h4" component="p">Total</Typography>
          <Typography variant="caption" color="text.secondary">Incl. VAT · {view.currency}</Typography>
        </Box>
        <Typography component="p" sx={{ fontSize: 22, fontWeight: 700, color: tk.primary, fontVariantNumeric: 'tabular-nums' }}>{rands(view.amount_cents, { decimals: true })}</Typography>
      </Box>
      {view.valid_until && (
        <Box sx={{ mt: 2, display: 'flex', alignItems: 'center', gap: 1, borderRadius: `${shape.tile}px`, px: 1.75, py: 1.25, bgcolor: urgent ? tk.warningContainer : tk.surfaceContainer, color: urgent ? tk.onWarningContainer : tk.onSurface }}>
          <MSymbol name="event" size={20} filled />
          <Typography variant="body2" sx={{ color: 'inherit' }}>
            Valid until <b>{fmtDate(view.valid_until, 'd MMM yyyy')}</b>{validity ? ` · ${validity}` : ''}
          </Typography>
        </Box>
      )}
    </Paper>
  );
}

function PhotosCard({ view }: { view: PublicQuotation }) {
  const [index, setIndex] = React.useState<number | null>(null);
  if (!view.attachments.length) return null;
  const photos = view.attachments.map((a) => ({ id: a.id, src: publicPhotoUrl(a.url), caption: a.caption }));
  return (
    <Paper component="section" aria-labelledby="photos-title" sx={{ p: 2.5 }}>
      <Typography id="photos-title" variant="h4" component="h2">Damage photos</Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mt: 0.25 }}>Taken by {view.outlet.name} during the assessment. Tap to enlarge.</Typography>
      <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(104px, 1fr))', gap: 1.25, mt: 1.5 }}>
        {photos.map((p, i) => (
          <Box key={p.id} component="button" type="button" onClick={() => setIndex(i)} aria-label={`Open photo${p.caption ? `: ${p.caption}` : ''}`} sx={{ p: 0, border: `1px solid ${tk.outlineVariant}`, borderRadius: '14px', overflow: 'hidden', bgcolor: tk.surfaceContainer, cursor: 'pointer', aspectRatio: '4 / 3', display: 'block' }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.src} alt={p.caption ?? 'Damage photo'} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} loading="lazy" />
          </Box>
        ))}
      </Box>
      <PhotoLightbox photos={photos} index={index} onClose={() => setIndex(null)} onIndex={setIndex} />
    </Paper>
  );
}

function OutletCard({ view, onCopy }: { view: PublicQuotation; onCopy: () => void }) {
  return (
    <Paper component="section" aria-labelledby="outlet-title" sx={{ p: 2.5, display: 'flex', flexDirection: 'column', gap: 1.5 }}>
      <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'flex-start' }}>
        <IconTile icon="storefront" tone="primary" size={44} />
        <Box sx={{ minWidth: 0, flex: 1 }}>
          <Typography id="outlet-title" variant="h5" component="h2">{view.outlet.trading_as || view.outlet.name}</Typography>
          {view.outlet.trading_as && view.outlet.trading_as !== view.outlet.name && <Typography variant="body2" color="text.secondary">{view.outlet.name}</Typography>}
          {view.outlet.address_line && <Typography variant="body2" color="text.secondary">{view.outlet.address_line}</Typography>}
          {view.outlet.vat_number && <Typography variant="caption" color="text.secondary" component="p">VAT No. {view.outlet.vat_number}</Typography>}
          {view.outlet.phone && (
            <Typography variant="body2" sx={{ mt: 0.5 }}>
              <Box component="a" href={`tel:${normalisePhone(view.outlet.phone) ?? view.outlet.phone.replace(/\s+/g, '')}`} sx={{ color: tk.primary, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 0.5 }}>
                <MSymbol name="call" size={18} filled />{formatPhone(view.outlet.phone)}
              </Box>
            </Typography>
          )}
        </Box>
      </Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, borderRadius: `${shape.tile}px`, px: 1.75, py: 1.25, bgcolor: tk.surfaceContainer }}>
        <MSymbol name="bookmark" size={20} filled style={{ color: tk.onSurfaceVariant }} />
        <Typography variant="body2" sx={{ flex: 1 }}>Save this link — you can come back to your quotation any time.</Typography>
        <Button size="small" variant="text" onClick={onCopy} startIcon={<MSymbol name="link" size={18} />}>Copy</Button>
      </Box>
    </Paper>
  );
}

function DecidedCard({ view }: { view: PublicQuotation }) {
  const accepted = view.status === 'accepted' || view.status === 'converted';
  const declined = view.status === 'declined';
  if (!accepted && !declined) return null;
  const tone = accepted ? { outer: tk.successContainer, inner: tk.success, icon: 'check', fg: tk.onPrimary } : { outer: tk.surfaceContainerHigh, inner: tk.onSurfaceVariant, icon: 'close', fg: tk.surfaceCard };
  return (
    <Paper component="section" role="status" aria-live="polite" sx={{ p: 3, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 1.5 }}>
      <Box sx={{ position: 'relative', width: 112, height: 112, borderRadius: '46% 54% 52% 48% / 55% 45% 55% 45%', bgcolor: tone.outer, display: 'grid', placeItems: 'center' }} aria-hidden>
        <Box sx={{ width: 80, height: 80, borderRadius: '52% 48% 46% 54% / 48% 56% 44% 52%', bgcolor: tone.inner, color: tone.fg, display: 'grid', placeItems: 'center' }}>
          <MSymbol name={tone.icon} size={48} weight={700} />
        </Box>
        {accepted && (
          <>
            <Box sx={{ position: 'absolute', top: 4, right: 8, width: 12, height: 12, borderRadius: '50%', bgcolor: tk.azure }} />
            <Box sx={{ position: 'absolute', bottom: 10, left: -2, width: 10, height: 10, borderRadius: '50%', bgcolor: tk.gold }} />
          </>
        )}
      </Box>
      <Box>
        <Typography variant="h2" component="h2" sx={{ fontSize: 24, fontWeight: 700 }}>
          {accepted ? `Accepted — ${view.outlet.name} will be in touch` : 'Declined'}
        </Typography>
        <Typography color="text.secondary" sx={{ mt: 0.75 }}>
          {accepted
            ? view.status === 'converted'
              ? 'The repair has been scheduled as a work order. You will get updates on WhatsApp.'
              : 'Nothing is charged now — the outlet will call to book the repair.'
            : 'Thanks for letting us know. Contact the outlet if you change your mind.'}
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
          {accepted ? 'Accepted' : 'Declined'} {fullDate(view.decided_at)}{view.decision_by_name ? ` by ${view.decision_by_name}` : ''}{view.decision_source ? ` · ${sourceLabel(view.decision_source)}` : ''}
        </Typography>
      </Box>
    </Paper>
  );
}

/* ------------------------------------------------------------------ */
/* Decision                                                             */
/* ------------------------------------------------------------------ */

function DecisionBar({ view, token, onDecided, onConflict }: { view: PublicQuotation; token: string; onDecided: (v: PublicQuotation) => void; onConflict: () => void }) {
  const [dialog, setDialog] = React.useState<'accept' | 'decline' | null>(null);
  const [name, setName] = React.useState(view.customer.first_name);
  const [note, setNote] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const toast = useToast();

  const submit = async () => {
    if (!dialog) return;
    setBusy(true);
    try {
      const next = await decidePublicQuotation(token, dialog === 'accept' ? { decision: 'accept', accepted_by_name: name.trim() || undefined, note: note.trim() || undefined } : { decision: 'decline', note: note.trim() || undefined });
      setDialog(null);
      onDecided(next);
    } catch (e) {
      if (e instanceof ApiRequestError && e.status === 409) {
        setDialog(null);
        toast.info('This quotation was already decided');
        onConflict();
      } else if (e instanceof ApiRequestError && e.status === 410) {
        setDialog(null);
        toast.error(new Error('This quotation has expired'));
        onConflict();
      } else toast.error(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      {/* Fixed (not sticky): globals.css sets overflow-x:hidden on html/body, which defeats position:sticky. */}
      <Box sx={{ position: 'fixed', left: 0, right: 0, bottom: 0, zIndex: 2, px: 2, pt: 1.5, pb: 'max(12px, env(safe-area-inset-bottom))', bgcolor: 'color-mix(in srgb, var(--mui-palette-surface-main) 88%, transparent)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)', borderTop: `1px solid ${tk.outlineVariant}` }}>
        <Box sx={{ display: 'flex', gap: 1.25, maxWidth: CONTENT_MAX, mx: 'auto' }}>
          <Button variant="outlined" color="error" onClick={() => { setNote(''); setDialog('decline'); }} startIcon={<MSymbol name="close" size={20} />} sx={{ flex: '1 1 0', minWidth: 0, whiteSpace: 'nowrap', borderColor: tk.error, color: tk.error }}>
            Decline
          </Button>
          <Button variant="contained" color="secondary" onClick={() => { setNote(''); setDialog('accept'); }} startIcon={<MSymbol name="check" size={20} />} sx={{ flex: '1.6 1 0', minWidth: 0, whiteSpace: 'nowrap' }}>
            Accept quotation
          </Button>
        </Box>
      </Box>

      <Dialog open={dialog !== null} onClose={() => !busy && setDialog(null)} aria-labelledby="decision-title" fullWidth maxWidth="xs">
        <DialogTitle id="decision-title">{dialog === 'accept' ? `Accept ${view.ref}?` : `Decline ${view.ref}?`}</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {dialog === 'accept'
              ? `${view.outlet.name} will contact you to book the repair for ${rands(view.amount_cents, { decimals: true })}. Nothing is charged now, and this can only be done once.`
              : 'No work will be scheduled. You can still contact the outlet for a revised quote.'}
          </Typography>
          <Box component="form" id="decision-form" onSubmit={(e) => { e.preventDefault(); void submit(); }} sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {dialog === 'accept' && <TextField label="Your name" value={name} onChange={(e) => setName(e.target.value)} autoFocus slotProps={{ htmlInput: { maxLength: 80 } }} helperText="Shown on the quotation as the person who accepted" />}
            <TextField label={dialog === 'accept' ? 'Note for the outlet (optional)' : 'Reason (optional)'} value={note} onChange={(e) => setNote(e.target.value)} multiline minRows={2} autoFocus={dialog === 'decline'} slotProps={{ htmlInput: { maxLength: 500 } }} />
          </Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setDialog(null)} disabled={busy}>Cancel</Button>
          <Button type="submit" form="decision-form" variant="contained" color={dialog === 'accept' ? 'secondary' : 'error'} disabled={busy} startIcon={busy ? <CircularProgress size={16} color="inherit" /> : <MSymbol name={dialog === 'accept' ? 'check' : 'close'} size={20} />}>
            {dialog === 'accept' ? 'Accept quotation' : 'Decline quotation'}
          </Button>
        </DialogActions>
      </Dialog>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/* ------------------------------------------------------------------ */
/* Page                                                                 */
/* ------------------------------------------------------------------ */

function LoadingSkeleton() {
  return (
    <Box aria-busy="true" aria-label="Loading quotation" sx={{ display: 'flex', flexDirection: 'column', gap: 1.75 }}>
      <Skeleton variant="rounded" height={190} sx={{ borderRadius: `${shape.dialog}px` }} />
      <Skeleton variant="rounded" height={260} sx={{ borderRadius: `${shape.card}px` }} />
      <Skeleton variant="rounded" height={120} sx={{ borderRadius: `${shape.card}px` }} />
    </Box>
  );
}

function MessageCard({ icon, tone, title, children, actions }: { icon: string; tone: 'error' | 'warning' | 'neutral'; title: string; children?: React.ReactNode; actions?: React.ReactNode }) {
  return (
    <Paper component="section" role="alert" sx={{ p: 3, mt: 2, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 1.5 }}>
      <IconTile icon={icon} tone={tone} size={64} />
      <Typography variant="h2" component="h1" sx={{ fontSize: 24, fontWeight: 700 }}>{title}</Typography>
      {children && <Typography color="text.secondary" sx={{ maxWidth: 420 }}>{children}</Typography>}
      {actions && <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap', justifyContent: 'center', mt: 0.5 }}>{actions}</Box>}
    </Paper>
  );
}

export default function PublicQuotePage({ token }: { token: string }) {
  const qc = useQueryClient();
  const query = useQuery({ queryKey: ['public-quote', token], queryFn: () => getPublicQuotation(token), retry: false, staleTime: Infinity, refetchOnWindowFocus: false });
  const toast = useToast();

  const state: LoadState = React.useMemo(() => {
    if (query.data) return { kind: 'ready', view: query.data };
    if (query.isPending) return { kind: 'loading' };
    const e = query.error;
    if (e instanceof ApiRequestError && e.status === 404) return { kind: 'not_found' };
    if (e instanceof ApiRequestError && e.status === 410) {
      const d = e.error.details as { ref?: string } | undefined;
      return { kind: 'expired', ref: d && !Array.isArray(d) ? d.ref ?? null : null };
    }
    return { kind: 'error', message: e instanceof Error ? e.message : 'Something went wrong' };
  }, [query.data, query.isPending, query.error]);

  React.useEffect(() => {
    const ref = state.kind === 'ready' ? state.view.ref : state.kind === 'expired' ? state.ref : null;
    document.title = ref ? `Quotation ${ref} · Sparkling` : 'Quotation · Sparkling';
  }, [state]);

  const copyLink = async () => {
    if (await copyText(window.location.href)) toast.success('Link copied');
    else toast.error(new Error('Could not copy — long-press the address bar instead'));
  };

  if (state.kind === 'loading') {
    return <Shell><LoadingSkeleton /></Shell>;
  }
  if (state.kind === 'not_found') {
    return (
      <Shell>
        <MessageCard icon="link_off" tone="error" title="This link isn't valid">
          Check the link in your WhatsApp message, or ask your Sparkling outlet to send the quotation again.
        </MessageCard>
      </Shell>
    );
  }
  if (state.kind === 'expired') {
    return (
      <Shell footer={state.ref ? `Sparkling Auto Care Centres · ${state.ref}` : undefined}>
        <MessageCard icon="event_busy" tone="warning" title="This quotation has expired" actions={<DownloadPdf token={token} view={null} refLabel={state.ref ?? 'quotation'} />}>
          {state.ref ? `Quotation ${state.ref} is no longer valid — contact your Sparkling outlet for an updated quote.` : 'Contact your Sparkling outlet for an updated quote.'}
        </MessageCard>
      </Shell>
    );
  }
  if (state.kind === 'error') {
    return (
      <Shell>
        <MessageCard icon="cloud_off" tone="error" title="Could not load your quotation" actions={<Button variant="outlined" onClick={() => void query.refetch()} startIcon={<MSymbol name="refresh" size={20} />}>Try again</Button>}>
          {state.message}
        </MessageCard>
      </Shell>
    );
  }

  const view = state.view;
  const decided = ['accepted', 'declined', 'converted'].includes(view.status);
  const expiredNotice = view.expired && !decided;

  return (
    <Shell bottomBar={view.can_decide && !decided} footer={<>Sparkling Auto Care Centres{view.valid_until ? ` · quotation valid until ${fmtDate(view.valid_until, 'd MMM yyyy')}` : ''}</>}>
      {decided && <DecidedCard view={view} />}
      <HeroCard view={view} />
      {expiredNotice && (
        <Box role="status" sx={{ display: 'flex', gap: 1.25, alignItems: 'center', borderRadius: `${shape.tile}px`, px: 1.75, py: 1.25, bgcolor: tk.warningContainer, color: tk.onWarningContainer }}>
          <MSymbol name="event_busy" size={22} filled />
          <Typography variant="body2" sx={{ color: 'inherit' }}>This quotation has expired — contact {view.outlet.name} for an updated quote.</Typography>
        </Box>
      )}
      <ItemsCard view={view} />
      <PhotosCard view={view} />
      {view.notes && (
        <Paper component="section" aria-labelledby="notes-title" sx={{ p: 2.5 }}>
          <Typography id="notes-title" variant="h4" component="h2">Notes from {view.outlet.name}</Typography>
          <Typography sx={{ mt: 0.75, whiteSpace: 'pre-wrap' }}>{view.notes}</Typography>
        </Paper>
      )}
      {view.terms && (
        <Paper component="section" aria-labelledby="terms-title" sx={{ p: 2.5 }}>
          <Typography id="terms-title" variant="h4" component="h2">Terms</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.75, lineHeight: 1.55 }}>{view.terms}</Typography>
        </Paper>
      )}
      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
        <DownloadPdf token={token} view={view} refLabel={view.ref} />
        <Button variant="text" onClick={copyLink} startIcon={<MSymbol name="link" size={20} />}>Copy link</Button>
      </Box>
      <OutletCard view={view} onCopy={copyLink} />
      {!decided && (
        <Typography variant="caption" color="text.secondary" sx={{ display: 'flex', gap: 1, alignItems: 'flex-start', px: 0.5 }}>
          <MSymbol name="info" size={18} />
          <span>Accept or decline below — nothing is booked or charged until you approve, and the decision can only be made once.</span>
        </Typography>
      )}
      {view.can_decide && !decided && (
        <DecisionBar
          view={view}
          token={token}
          onDecided={(v) => { qc.setQueryData(['public-quote', token], v); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
          onConflict={() => void query.refetch()}
        />
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </Shell>
  );
}
