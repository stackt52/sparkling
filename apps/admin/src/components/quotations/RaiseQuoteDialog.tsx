'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import IconButton from '@mui/material/IconButton';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Stepper from '@mui/material/Stepper';
import Step from '@mui/material/Step';
import StepButton from '@mui/material/StepButton';
import StepLabel from '@mui/material/StepLabel';
import FormControlLabel from '@mui/material/FormControlLabel';
import CircularProgress from '@mui/material/CircularProgress';
import useMediaQuery from '@mui/material/useMediaQuery';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { addDays, format } from 'date-fns';
import MSymbol from '@/components/MSymbol';
import M3Switch from '@/components/ui/M3Switch';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import CustomerStep from '@/components/bookings/walkin/CustomerStep';
import VehicleStep from '@/components/bookings/walkin/VehicleStep';
import QuoteItemsEditor, { cleanQuoteItems, emptyQuoteItem, quoteItemsTotal } from './QuoteItemsEditor';
import PhotoDropzone, { vetPhotos } from './PhotoDropzone';
import QuotationPhotoGrid, { type PendingPhoto } from './QuotationPhotoGrid';
import DownloadPdfButton from './DownloadPdfButton';
import { QUOTE_CATEGORY_META, quotationCategoryFromItems } from './quoteCategories';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { uuid } from '@/lib/api';
import { copyText } from '@/lib/clipboard';
import { useFilters } from '@/lib/filters';
import { fmtDate, rands } from '@/lib/format';
import { formatPhone } from '@/lib/phone';
import { fonts, tk } from '@/theme/tokens';
import { QUOTE_ITEM_CATEGORIES, type QuoteLineItem, type Quotation, type WalkInCustomer, type WalkInVehicle } from '@/lib/types';

const STEPS = ['Customer', 'Vehicle', 'Quote'] as const;
const HINTS = ['Find or register the customer', 'Pick the vehicle being repaired', 'Items, photos and validity'];

interface Draft {
  step: 0 | 1 | 2;
  customer: WalkInCustomer | null;
  vehicle: WalkInVehicle | null;
  outlet_id: string;
  category: string;
  description: string;
  items: QuoteLineItem[];
  valid_until: string;
  items_note: string;
  send: boolean;
  photos: PendingPhoto[];
  client_op_id: string;
}

export interface RaiseQuoteInitial {
  customer?: WalkInCustomer | null;
  vehicle?: WalkInVehicle | null;
  outlet_id?: string | null;
}

const newDraft = (outletId: string, initial?: RaiseQuoteInitial): Draft => ({
  step: initial?.customer && initial.vehicle ? 2 : initial?.customer ? 1 : 0, customer: initial?.customer ?? null, vehicle: initial?.vehicle ?? null, outlet_id: initial?.outlet_id || outletId, category: '', description: '', items: [emptyQuoteItem()],
  valid_until: format(addDays(new Date(), 14), 'yyyy-MM-dd'), items_note: '', send: true, photos: [], client_op_id: uuid(),
});

/**
 * "Raise quote" — the dashboard twin of the staff app's flow: customer search / register → vehicle
 * pick / add → items (category chips, description, auto-body service, amount) + photos + valid-until
 * → `POST /quotations` (staff shape) → success with the public link.
 */
interface RaiseQuoteDialogProps {
  open: boolean;
  onClose: () => void;
  onOpenQuotation: (id: string) => void;
  onToast: (kind: 'success' | 'error' | 'info', message: string | Error) => void;
  /** Prefill (e.g. from the walk-in flow when a by-quote service is picked); applied each time the dialog opens. */
  initial?: RaiseQuoteInitial;
}

export default function RaiseQuoteDialog(props: RaiseQuoteDialogProps) {
  // With a prefill, remount per open so the draft restarts from `initial`; without one the unsent draft is kept between opens.
  const [session, setSession] = React.useState(0);
  const [wasOpen, setWasOpen] = React.useState(props.open);
  if (props.open !== wasOpen) {
    setWasOpen(props.open);
    if (props.open && props.initial) setSession((n) => n + 1);
  }
  return <RaiseQuoteDialogBody key={session} {...props} />;
}

function RaiseQuoteDialogBody({ open, onClose, onOpenQuotation, onToast, initial }: RaiseQuoteDialogProps) {
  const api = useApi();
  const qc = useQueryClient();
  const { profile } = useAuth();
  const { outletId } = useFilters();
  const compact = useMediaQuery('(max-width:899.95px)');
  const defaultOutlet = outletId ?? profile?.outlet_ids[0] ?? '';
  const [draft, setDraft] = React.useState<Draft>(() => newDraft(defaultOutlet, initial));
  const [result, setResult] = React.useState<{ quotation: Quotation; photo_failures: number } | null>(null);
  const patch = (p: Partial<Draft>) => setDraft((d) => ({ ...d, ...p }));

  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets(), enabled: open });
  const allowedOutlets = React.useMemo(() => (outlets.data ?? []).filter((o) => o.is_active && (profile?.role === 'admin' || !profile || profile.outlet_ids.includes(o.id))), [outlets.data, profile]);
  // Falls back to the first outlet the user may quote for until they pick one.
  const outletIdSel = draft.outlet_id || allowedOutlets[0]?.id || '';
  const services = useQuery({ queryKey: ['outlet-services-for', outletIdSel], queryFn: () => api.listOutletServicesFor(outletIdSel), enabled: open && Boolean(outletIdSel), select: (rows) => rows.filter((s) => s.group_name === 'Auto Body Repair' || s.category === 'auto_body') });

  const items = cleanQuoteItems(draft.items);
  const total = quoteItemsTotal(items);
  const reach: 0 | 1 | 2 = !draft.customer ? 0 : !draft.vehicle ? 1 : 2;
  const quoteValid = Boolean(outletIdSel) && items.length > 0 && total > 0 && /^\d{4}-\d{2}-\d{2}$/.test(draft.valid_until) && draft.valid_until >= format(new Date(), 'yyyy-MM-dd') && draft.description.trim().length > 0;

  const raise = useMutation({
    mutationFn: async () => {
      const quotation = await api.raiseQuotation({
        customer_id: draft.customer!.id,
        vehicle_id: draft.vehicle!.id,
        outlet_id: outletIdSel,
        category: draft.category || quotationCategoryFromItems(items),
        description: draft.description.trim(),
        items,
        valid_until: draft.valid_until,
        items_note: draft.items_note.trim() || null,
        client_op_id: draft.client_op_id,
        send_to_customer: draft.send,
      });
      let photo_failures = 0;
      for (const p of draft.photos) {
        try {
          await api.uploadQuotationPhoto(quotation.id, p.file, p.caption ?? undefined);
        } catch {
          photo_failures += 1;
        }
      }
      return { quotation: photo_failures < draft.photos.length ? await api.getQuotation(quotation.id) : quotation, photo_failures };
    },
    onSuccess: (res) => {
      setResult(res);
      void qc.invalidateQueries({ queryKey: ['quotations'] });
      onToast('success', `${res.quotation.ref} ${draft.send ? 'sent to' : 'raised for'} ${res.quotation.customer_name}`);
      if (res.photo_failures) onToast('error', new Error(`${res.photo_failures} photo${res.photo_failures === 1 ? '' : 's'} could not be uploaded — add them from the quotation drawer`));
    },
    onError: (e) => onToast('error', e instanceof Error ? e : new Error(String(e))),
  });

  const reset = () => {
    setDraft(newDraft(defaultOutlet, initial));
    setResult(null);
  };
  const close = () => {
    if (raise.isPending) return;
    onClose();
    // Keep an unsent draft for the next open; clear after a successful send.
    if (result) reset();
  };
  const go = (s: 0 | 1 | 2) => patch({ step: s });

  const addPhotos = (files: File[]) => {
    const { ok, rejected } = vetPhotos(files, draft.photos.length);
    rejected.forEach((r) => onToast('error', new Error(r)));
    if (ok.length) patch({ photos: [...draft.photos, ...ok.map((file) => ({ id: uuid(), file }))] });
  };

  const q = result?.quotation;
  return (
    <Dialog open={open} onClose={close} fullScreen={compact} fullWidth maxWidth="md" aria-labelledby="raise-quote-title" slotProps={{ paper: { sx: { borderRadius: compact ? 0 : undefined, height: compact ? '100%' : 'min(92vh, 860px)', display: 'flex', flexDirection: 'column' } } }}>
      <DialogTitle id="raise-quote-title" sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, pb: 1 }}>
        <Box>
          <Typography variant="overline" color="text.secondary" component="div">Quotation</Typography>
          <Typography variant="h2" component="span">{q ? 'Quote sent' : 'Raise quote'}</Typography>
        </Box>
        <IconButton aria-label="Close" onClick={close} edge="end" disabled={raise.isPending}><MSymbol name="close" /></IconButton>
      </DialogTitle>

      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
        {q ? (
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 2, py: 2 }}>
            <Box sx={{ position: 'relative', width: 112, height: 112, borderRadius: '46% 54% 52% 48% / 55% 45% 55% 45%', bgcolor: tk.primaryContainer, display: 'grid', placeItems: 'center' }} aria-hidden>
              <Box sx={{ width: 80, height: 80, borderRadius: '52% 48% 46% 54% / 48% 56% 44% 52%', bgcolor: tk.primary, color: tk.onPrimary, display: 'grid', placeItems: 'center' }}><MSymbol name="check" size={48} weight={700} /></Box>
              <Box sx={{ position: 'absolute', top: 4, right: 8, width: 12, height: 12, borderRadius: '50%', bgcolor: tk.azure }} />
              <Box sx={{ position: 'absolute', bottom: 10, left: -2, width: 10, height: 10, borderRadius: '50%', bgcolor: tk.gold }} />
            </Box>
            <Box>
              <Typography variant="h1" component="h2" sx={{ fontSize: 28 }}>{draft.send ? `Sent to ${q.customer_name.split(' ')[0]}` : `Quote raised for ${q.customer_name.split(' ')[0]}`}</Typography>
              <Typography color="text.secondary" sx={{ mt: 1 }}>{draft.send ? 'The customer received the link on WhatsApp / push and can accept or decline with one tap.' : 'Send the link from the quotation drawer when you are ready.'}</Typography>
              <Typography component="div" sx={{ mt: 1.5, display: 'flex', gap: 1, justifyContent: 'center', alignItems: 'center', flexWrap: 'wrap' }}>
                <Box component="span" className="mono" sx={{ fontWeight: 700, fontSize: 18, color: tk.primary }}>{q.ref}</Box>
                <StatusChip status={q.status} />
                <Typography component="span" sx={{ fontWeight: 700 }}>{rands(q.amount_cents ?? 0, { decimals: true })}</Typography>
              </Typography>
            </Box>
            {q.public_url && (
              <Tile sx={{ width: '100%', maxWidth: 560, gap: 1 }}>
                <MSymbol name="link" size={20} style={{ color: tk.primary }} />
                <Typography component="code" sx={{ fontFamily: fonts.mono, fontSize: 12.5, flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', textAlign: 'left' }} title={q.public_url}>{q.public_url}</Typography>
                <IconButton size="small" aria-label="Copy public link" onClick={async () => { if (await copyText(q.public_url!)) onToast('success', 'Public link copied'); else onToast('error', new Error('Could not copy the link')); }}><MSymbol name="content_copy" size={18} /></IconButton>
                <IconButton size="small" aria-label="Open public link" component="a" href={q.public_url} target="_blank" rel="noopener"><MSymbol name="open_in_new" size={18} /></IconButton>
              </Tile>
            )}
            <Typography variant="body2" color="text.secondary">Valid until {fmtDate(q.valid_until, 'd MMM yyyy')} · {q.attachments.length} photo{q.attachments.length === 1 ? '' : 's'} · {q.outlet.name}</Typography>
            <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap', justifyContent: 'center' }}>
              <DownloadPdfButton q={q} onToast={onToast} />
              <Button variant="outlined" onClick={reset} startIcon={<MSymbol name="add" size={20} />}>Raise another</Button>
              <Button variant="contained" color="secondary" onClick={() => { onOpenQuotation(q.id); close(); }} startIcon={<MSymbol name="open_in_new" size={20} />}>Open quotation</Button>
            </Box>
          </Box>
        ) : (
          <>
            <Stepper nonLinear activeStep={draft.step} orientation={compact ? 'vertical' : 'horizontal'} sx={{ '& .MuiStepLabel-label': { fontWeight: 600 }, '& .MuiStepIcon-root.Mui-active, & .MuiStepIcon-root.Mui-completed': { color: tk.primary }, ...(compact && { '& .MuiStepContent-root, & .MuiStepConnector-root': { display: 'none' } }) }}>
              {STEPS.map((label, i) => (
                <Step key={label} completed={i < draft.step && i < reach} disabled={i > reach}>
                  <StepButton onClick={() => go(i as 0 | 1 | 2)} optional={!compact && <Typography variant="caption" color="text.secondary">{HINTS[i]}</Typography>}>
                    <StepLabel>{label}</StepLabel>
                  </StepButton>
                </Step>
              ))}
            </Stepper>

            {draft.step === 0 && <CustomerStep selected={draft.customer} onSelect={(c) => setDraft((d) => ({ ...d, customer: c, vehicle: d.customer?.id === c.id ? d.vehicle : null }))} onError={(e) => onToast('error', e instanceof Error ? e : new Error(String(e)))} />}
            {draft.step === 1 && draft.customer && (
              <VehicleStep customer={draft.customer} selected={draft.vehicle} onSelect={(v) => patch({ vehicle: v })} onCustomerUpdated={(c) => patch({ customer: c })} onError={(e) => onToast('info', e instanceof Error ? e.message : String(e))} />
            )}
            {draft.step === 2 && draft.customer && draft.vehicle && (
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <Tile sx={{ gap: 2, flexWrap: 'wrap' }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <MSymbol name="person" filled size={20} style={{ color: tk.primary }} />
                    <Typography sx={{ fontWeight: 600 }}>{draft.customer.full_name}</Typography>
                    {draft.customer.phone && <Typography variant="body2" color="text.secondary">{formatPhone(draft.customer.phone)}</Typography>}
                  </Box>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <MSymbol name="directions_car" filled size={20} style={{ color: tk.primary }} />
                    <Typography className="mono" sx={{ fontWeight: 700 }}>{draft.vehicle.registration_no}</Typography>
                    <Typography variant="body2" color="text.secondary">{[draft.vehicle.make, draft.vehicle.model].filter(Boolean).join(' ')}</Typography>
                  </Box>
                </Tile>
                <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr' }, gap: 2 }}>
                  <TextField select label="Outlet" value={allowedOutlets.some((o) => o.id === outletIdSel) ? outletIdSel : ''} onChange={(e) => patch({ outlet_id: e.target.value })} required helperText="Must be one of your outlets">
                    {allowedOutlets.map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
                  </TextField>
                  <TextField select label="Damage type" value={draft.category} onChange={(e) => patch({ category: e.target.value })} helperText={draft.category ? ' ' : `Defaults to the first item's category (${quotationCategoryFromItems(items)})`}>
                    <MenuItem value=""><em>From items</em></MenuItem>
                    {QUOTE_ITEM_CATEGORIES.map((c) => <MenuItem key={c} value={QUOTE_CATEGORY_META[c].label}>{QUOTE_CATEGORY_META[c].label}</MenuItem>)}
                  </TextField>
                </Box>
                <TextField label="Summary of the damage" placeholder="e.g. Rear bumper scuffed in parking lot, paint cracked on left corner." value={draft.description} onChange={(e) => patch({ description: e.target.value })} required multiline minRows={2} slotProps={{ htmlInput: { maxLength: 600 } }} />
                <Box>
                  <Typography variant="h4" component="h3" sx={{ mb: 1 }}>What needs attention</Typography>
                  <QuoteItemsEditor items={draft.items} onChange={(items) => patch({ items })} services={services.data} />
                </Box>
                <Box>
                  <Typography variant="h4" component="h3" sx={{ mb: 0.5 }}>Damage photos</Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>Uploaded once the quote is created and shown to the customer on the public page.</Typography>
                  <QuotationPhotoGrid quotationId={null} attachments={[]} pending={draft.photos} onRemovePending={(p) => patch({ photos: draft.photos.filter((x) => x.id !== p.id) })}>
                    <PhotoDropzone compact count={draft.photos.length} onFiles={addPhotos} />
                  </QuotationPhotoGrid>
                </Box>
                <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '200px 1fr' }, gap: 2 }}>
                  <TextField label="Valid until" type="date" value={draft.valid_until} onChange={(e) => patch({ valid_until: e.target.value })} required slotProps={{ inputLabel: { shrink: true }, htmlInput: { min: format(new Date(), 'yyyy-MM-dd') } }} error={draft.valid_until < format(new Date(), 'yyyy-MM-dd')} helperText={draft.valid_until < format(new Date(), 'yyyy-MM-dd') ? 'Must be today or later' : ' '} />
                  <TextField label="Notes for the customer (optional)" placeholder="Turnaround, courtesy wash, what is excluded…" value={draft.items_note} onChange={(e) => patch({ items_note: e.target.value })} multiline minRows={1} maxRows={3} slotProps={{ htmlInput: { maxLength: 500 } }} />
                </Box>
                <Tile sx={{ justifyContent: 'space-between' }}>
                  <Box>
                    <Typography variant="h6" component="p">Send to customer now</Typography>
                    <Typography variant="body2" color="text.secondary">{draft.customer.whatsapp_opt_in ? 'WhatsApp + push with the public link' : 'Push only — no WhatsApp opt-in on file'} · {draft.customer.phone ? formatPhone(draft.customer.phone) : 'no phone'}</Typography>
                  </Box>
                  <FormControlLabel control={<M3Switch checked={draft.send} onChange={(e) => patch({ send: e.target.checked })} />} label="Send to customer now" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' } }} />
                </Tile>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
                  <MSymbol name="info" size={18} />
                  <span>The customer accepts or declines via the link or in the app — nothing is booked until they approve (CUS-033). The decision is one-time.</span>
                </Typography>
              </Box>
            )}
          </>
        )}
      </DialogContent>

      {!q && (
        <DialogActions sx={{ p: 2.5, pt: 1.5, borderTop: `1px solid ${tk.outlineVariant}`, justifyContent: 'space-between', gap: 1.5, flexWrap: 'wrap' }}>
          <Button variant="text" disabled={draft.step === 0 || raise.isPending} onClick={() => go((draft.step - 1) as 0 | 1)} startIcon={<MSymbol name="arrow_back" size={20} />}>Back</Button>
          {draft.step < 2 ? (
            <Button variant="contained" color="secondary" disabled={reach <= draft.step} onClick={() => go((draft.step + 1) as 1 | 2)} endIcon={<MSymbol name="arrow_forward" size={20} />} sx={{ px: 3 }}>
              {draft.step === 0 ? 'Choose vehicle' : 'Build quote'}
            </Button>
          ) : (
            <Button variant="contained" color="secondary" disabled={!quoteValid || raise.isPending} onClick={() => raise.mutate()} startIcon={raise.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="send" size={20} />} sx={{ px: 3 }}>
              {draft.send ? `Send to customer · ${rands(total, { decimals: true })}` : `Raise quote · ${rands(total, { decimals: true })}`}
            </Button>
          )}
        </DialogActions>
      )}
    </Dialog>
  );
}
