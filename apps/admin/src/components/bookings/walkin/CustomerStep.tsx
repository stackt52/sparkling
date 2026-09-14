'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import InputAdornment from '@mui/material/InputAdornment';
import Button from '@mui/material/Button';
import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import FormControlLabel from '@mui/material/FormControlLabel';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQuery } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import StatusChip from '@/components/ui/StatusChip';
import TierChip, { TIER_NAME } from '@/components/ui/TierChip';
import M3Switch from '@/components/ui/M3Switch';
import Tile from '@/components/ui/Tile';
import { EmptyState, ErrorState } from '@/components/ui/States';
import RadioCards from './RadioCards';
import { useApi } from '@/lib/auth/AuthProvider';
import { ApiRequestError, conflictDetail, uuid } from '@/lib/api';
import { initials } from '@/lib/format';
import { fonts, tk } from '@/theme/tokens';
import type { WalkInCustomer } from '@/lib/types';

/** Plan pill: "Gold · 3 washes left · 1 450 pts" (tier = plan; silver = no plan). */
export function PlanPill({ loyalty }: { loyalty: WalkInCustomer['loyalty'] }) {
  if (!loyalty) return <StatusChip tone="neutral" label="No loyalty account" />;
  const washes = loyalty.plan_code ? ` · ${loyalty.included_remaining} wash${loyalty.included_remaining === 1 ? '' : 'es'} left` : '';
  return <TierChip tier={loyalty.tier} icon={loyalty.plan_code ? <MSymbol name="workspace_premium" filled size={16} /> : undefined} label={`${loyalty.plan_name ?? TIER_NAME[loyalty.tier]}${washes} · ${loyalty.balance_points} pts`} />;
}

function CustomerCard({ c }: { c: WalkInCustomer }) {
  return (
    <>
      <Avatar sx={{ width: 44, height: 44, bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer, fontWeight: 700, fontSize: 15 }}>{initials(c.full_name)}</Avatar>
      <Box sx={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 0.5 }}>
        <Typography variant="h5" component="span" sx={{ color: 'inherit' }}>{c.full_name}</Typography>
        <Typography variant="body2" component="span" sx={{ color: tk.onSurfaceVariant }}>{[c.phone, c.email].filter(Boolean).join(' · ') || 'No contact details'}</Typography>
        <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mt: 0.25 }}>
          <PlanPill loyalty={c.loyalty} />
          {c.vehicles.map((v) => (
            <Chip key={v.id} size="small" label={v.registration_no} sx={{ fontFamily: fonts.mono, bgcolor: tk.surfaceCard, color: tk.onSurface, border: `1px solid ${tk.outlineVariant}` }} />
          ))}
        </Box>
      </Box>
    </>
  );
}

function useDebounced(value: string, ms = 300) {
  const [v, setV] = React.useState(value);
  React.useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

interface RegisterState { full_name: string; phone: string; email: string; whatsapp: boolean; marketing: boolean }
const emptyRegister = (): RegisterState => ({ full_name: '', phone: '', email: '', whatsapp: true, marketing: false });

export default function CustomerStep({ selected, onSelect, onError }: { selected: WalkInCustomer | null; onSelect: (c: WalkInCustomer) => void; onError: (e: unknown) => void }) {
  const api = useApi();
  const [search, setSearch] = React.useState('');
  const q = useDebounced(search.trim());
  const results = useQuery({ queryKey: ['walkin-customers', q], queryFn: () => api.searchWalkInCustomers(q), enabled: q.length >= 2 });

  const [registerOpen, setRegisterOpen] = React.useState(false);
  const [form, setForm] = React.useState<RegisterState>(emptyRegister);
  const [opId, setOpId] = React.useState(() => uuid());
  const [existing, setExisting] = React.useState<WalkInCustomer | null>(null);
  const fieldErrors = { name: form.full_name.trim().length < 2, phone: form.phone.replace(/\D/g, '').length < 9, email: form.email.trim() !== '' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email.trim()) };
  const valid = !fieldErrors.name && !fieldErrors.phone && !fieldErrors.email;

  const register = useMutation({
    mutationFn: () => api.createWalkInCustomer({ full_name: form.full_name.trim(), phone: form.phone.trim(), email: form.email.trim() || null, whatsapp_opt_in: form.whatsapp, marketing_opt_in: form.marketing, client_op_id: opId }),
    onSuccess: (c) => {
      setRegisterOpen(false);
      setForm(emptyRegister());
      setOpId(uuid());
      onSelect(c);
    },
    onError: (e) => {
      const hit = conflictDetail<WalkInCustomer>(e, 'existing_customer');
      if (hit) setExisting(hit);
      else onError(e);
    },
  });

  const openRegister = () => {
    // Seed the form from what was typed so a "no match" search flows straight into registration.
    const digitsOnly = /^[\d\s+()-]{6,}$/.test(search.trim());
    setForm({ ...emptyRegister(), full_name: !digitsOnly && !search.includes('@') ? search.trim() : '', phone: digitsOnly ? search.trim() : '', email: search.includes('@') ? search.trim() : '' });
    setRegisterOpen(true);
  };

  const list = results.data ?? [];
  const showSelectedSeparately = selected && !list.some((c) => c.id === selected.id);

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap', alignItems: 'flex-start' }}>
        <TextField
          label="Find customer"
          placeholder="Name, phone, e-mail or plate"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          autoFocus
          sx={{ flex: 1, minWidth: 260 }}
          slotProps={{
            input: {
              startAdornment: <InputAdornment position="start"><MSymbol name="search" size={20} /></InputAdornment>,
              endAdornment: results.isFetching ? <InputAdornment position="end"><CircularProgress size={18} aria-label="Searching" /></InputAdornment> : undefined,
            },
            htmlInput: { 'aria-describedby': 'walkin-search-hint' },
          }}
        />
        <Button variant="outlined" onClick={openRegister} startIcon={<MSymbol name="person_add" size={20} />} sx={{ height: 56, px: 2.5 }}>
          Register new customer
        </Button>
      </Box>
      <Typography id="walkin-search-hint" variant="body2" color="text.secondary" sx={{ mt: -1 }}>Type at least 2 characters. Walk-ins registered here are claimed automatically when the customer later signs up with the same phone or e-mail.</Typography>

      {showSelectedSeparately && (
        <Box>
          <Typography variant="overline" color="text.secondary">Selected</Typography>
          <RadioCards label="Selected customer" items={[selected]} getKey={(c) => c.id} selected={selected.id} onSelect={onSelect} render={(c) => <CustomerCard c={c} />} />
        </Box>
      )}

      {q.length < 2 && !selected && (
        <EmptyState icon="person_search" title="Search for the customer" description="Find an existing customer by name, phone, e-mail or number plate — or register a new walk-in." />
      )}
      {results.error && <ErrorState error={results.error} onRetry={() => results.refetch()} />}
      {q.length >= 2 && results.isSuccess && (
        list.length ? (
          <Box>
            <Typography variant="overline" color="text.secondary">{list.length} {list.length === 1 ? 'match' : 'matches'}</Typography>
            <RadioCards label="Matching customers" items={list} getKey={(c) => c.id} selected={selected?.id ?? null} onSelect={onSelect} render={(c) => <CustomerCard c={c} />} />
          </Box>
        ) : (
          <EmptyState icon="person_off" title={`No customer matches “${q}”`} description="Check the spelling, or register them as a new walk-in." action={<Button variant="contained" color="secondary" onClick={openRegister} startIcon={<MSymbol name="person_add" size={20} />}>Register new customer</Button>} />
        )
      )}

      {/* Register dialog */}
      <Dialog open={registerOpen} onClose={() => !register.isPending && setRegisterOpen(false)} aria-labelledby="register-title" fullWidth maxWidth="sm">
        <DialogTitle id="register-title">Register customer</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>New walk-in · no app account needed. Bookings, vehicles and points carry over when they sign up.</Typography>
          <Box component="form" id="register-form" onSubmit={(e) => { e.preventDefault(); if (valid) register.mutate(); }} sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <TextField label="Full name" value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} required autoFocus error={form.full_name !== '' && fieldErrors.name} helperText={form.full_name !== '' && fieldErrors.name ? 'Enter the customer’s name' : ' '} />
            <TextField label="Phone" placeholder="082 123 4567" type="tel" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} required error={form.phone !== '' && fieldErrors.phone} helperText={form.phone !== '' && fieldErrors.phone ? 'Enter a valid South African number' : 'Used for WhatsApp receipts and to claim the profile later'} />
            <TextField label="E-mail (optional)" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} error={fieldErrors.email} helperText={fieldErrors.email ? 'That e-mail does not look right' : ' '} />
            <Tile sx={{ justifyContent: 'space-between' }}>
              <Box>
                <Typography variant="h6" component="p">WhatsApp updates</Typography>
                <Typography variant="body2" color="text.secondary">Booking confirmations, ready-for-collection and receipts</Typography>
              </Box>
              <FormControlLabel control={<M3Switch checked={form.whatsapp} onChange={(e) => setForm({ ...form, whatsapp: e.target.checked })} />} label="WhatsApp updates" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' } }} />
            </Tile>
            <Tile sx={{ justifyContent: 'space-between' }}>
              <Box>
                <Typography variant="h6" component="p">Marketing messages</Typography>
                <Typography variant="body2" color="text.secondary">Offers and loyalty news — off unless they ask</Typography>
              </Box>
              <FormControlLabel control={<M3Switch checked={form.marketing} onChange={(e) => setForm({ ...form, marketing: e.target.checked })} />} label="Marketing messages" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' } }} />
            </Tile>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
              <MSymbol name="verified_user" size={18} />
              <span>Confirm with the customer that Sparkling may store their details (POPIA). Consent choices are recorded against your name in the audit log.</span>
            </Typography>
          </Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setRegisterOpen(false)} disabled={register.isPending}>Cancel</Button>
          <Button type="submit" form="register-form" variant="contained" color="secondary" disabled={!valid || register.isPending} startIcon={register.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="person_add" size={20} />}>
            Register customer
          </Button>
        </DialogActions>
      </Dialog>

      {/* 409 conflict: already registered */}
      <Dialog open={Boolean(existing)} onClose={() => setExisting(null)} aria-labelledby="existing-title">
        <DialogTitle id="existing-title">Already registered</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            {register.error instanceof ApiRequestError ? register.error.error.message : 'A customer with these details already exists.'} Use the existing profile so their vehicles and points stay together.
          </Typography>
          {existing && (
            <Tile sx={{ alignItems: 'center' }}>
              <CustomerCard c={existing} />
            </Tile>
          )}
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setExisting(null)}>Edit details</Button>
          <Button variant="contained" color="secondary" onClick={() => { if (existing) onSelect(existing); setExisting(null); setRegisterOpen(false); setForm(emptyRegister()); setOpId(uuid()); }}>
            Use {existing?.full_name.split(' ')[0]}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
