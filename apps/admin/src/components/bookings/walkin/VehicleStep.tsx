'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import StatusChip from '@/components/ui/StatusChip';
import { EmptyState } from '@/components/ui/States';
import RadioCards from './RadioCards';
import { useApi } from '@/lib/auth/AuthProvider';
import { ApiRequestError, conflictDetail, uuid } from '@/lib/api';
import Tile from '@/components/ui/Tile';
import { SIZE_HINT, SIZE_LABEL, SizeToggle } from '@/components/catalogue/pricing';
import { fonts, tk } from '@/theme/tokens';
import { vehicleSizeOf, type Vehicle, type VehicleSize, type WalkInCustomer, type WalkInVehicle } from '@/lib/types';

function VehicleCard({ v }: { v: WalkInVehicle }) {
  return (
    <>
      <IconTile icon="directions_car" tone="primary" size={44} />
      <Box sx={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 0.5 }}>
        <Typography component="span" sx={{ fontFamily: fonts.mono, fontWeight: 700, fontSize: 17, letterSpacing: '0.02em' }}>{v.registration_no}</Typography>
        <Typography variant="body2" component="span" sx={{ color: tk.onSurfaceVariant }}>{[v.make, v.model, v.colour].filter(Boolean).join(' · ') || 'Details not captured'}</Typography>
        <Box sx={{ display: 'flex', gap: 0.75, mt: 0.25 }}>
          {v.disc_verified ? <StatusChip tone="success" label="Disc verified" icon={<MSymbol name="verified" size={14} filled />} /> : <StatusChip tone="neutral" label="Manual" />}
        </Box>
      </Box>
    </>
  );
}

interface VehicleForm { registration_no: string; make: string; model: string; colour: string; year: string; vin: string }
const emptyForm = (): VehicleForm => ({ registration_no: '', make: '', model: '', colour: '', year: '', vin: '' });

export default function VehicleStep({ customer, selected, onSelect, onCustomerUpdated, onError, size, onSizeChange }: {
  customer: WalkInCustomer;
  selected: WalkInVehicle | null;
  onSelect: (v: WalkInVehicle) => void;
  onCustomerUpdated: (c: WalkInCustomer) => void;
  onError: (e: unknown) => void;
  /** Pricing size (prefilled from the vehicle's `size_class`, else derived from the model). */
  size?: VehicleSize;
  onSizeChange?: (s: VehicleSize) => void;
}) {
  const api = useApi();
  const [open, setOpen] = React.useState(false);
  const [form, setForm] = React.useState<VehicleForm>(emptyForm);
  const [opId, setOpId] = React.useState(() => uuid());
  const [conflict, setConflict] = React.useState<{ id: string; message: string } | null>(null);
  const regOk = form.registration_no.replace(/[^a-z0-9]/gi, '').length >= 4;
  const yearNum = form.year.trim() === '' ? null : Number(form.year);
  const yearOk = yearNum === null || (Number.isInteger(yearNum) && yearNum >= 1950 && yearNum <= new Date().getFullYear() + 1);
  const vinOk = form.vin.trim() === '' || /^[A-HJ-NPR-Z0-9]{11,17}$/i.test(form.vin.trim());
  const valid = regOk && yearOk && vinOk;

  const toSummary = (v: Vehicle): WalkInVehicle => ({ id: v.id, registration_no: v.registration_no, make: v.make, model: v.model, colour: v.colour, disc_verified: v.disc_verified, size_class: v.size_class ?? null });

  const add = useMutation({
    mutationFn: (force: boolean) => api.createCustomerVehicle(customer.id, { registration_no: form.registration_no.trim().toUpperCase(), make: form.make.trim() || null, model: form.model.trim() || null, colour: form.colour.trim() || null, year: yearNum, vin: form.vin.trim() || null, source: 'manual', client_op_id: opId }, force),
    onSuccess: ({ vehicle, duplicate }) => {
      const summary = toSummary(vehicle);
      const already = customer.vehicles.find((v) => v.id === summary.id);
      if (!already) onCustomerUpdated({ ...customer, vehicles: [...customer.vehicles, summary] });
      onSelect(already ?? summary);
      setOpen(false);
      setConflict(null);
      setForm(emptyForm());
      setOpId(uuid());
      if (duplicate) onError(new Error(`${summary.registration_no} was already on file — selected the existing vehicle`));
    },
    onError: (e) => {
      const id = conflictDetail<string>(e, 'existing_vehicle_id');
      if (id) setConflict({ id, message: e instanceof ApiRequestError ? e.error.message : 'This vehicle is already registered' });
      else onError(e);
    },
  });

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
        <Box>
          <Typography variant="h4" component="h3">Vehicles on file for {customer.full_name}</Typography>
          <Typography variant="body2" color="text.secondary">Pick the car being washed, or add one by hand.</Typography>
        </Box>
        <Button variant="outlined" onClick={() => setOpen(true)} startIcon={<MSymbol name="add_circle" size={20} />}>Add vehicle</Button>
      </Box>
      {customer.vehicles.length ? (
        <RadioCards label="Customer vehicles" items={customer.vehicles} getKey={(v) => v.id} selected={selected?.id ?? null} onSelect={onSelect} render={(v) => <VehicleCard v={v} />} columns={{ xs: '1fr', md: '1fr 1fr' }} />
      ) : (
        <EmptyState icon="no_crash" title="No vehicles yet" description="Add the customer’s vehicle to continue." action={<Button variant="contained" color="secondary" onClick={() => setOpen(true)} startIcon={<MSymbol name="add_circle" size={20} />}>Add vehicle</Button>} />
      )}

      {selected && size && onSizeChange && (
        <Tile sx={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 1.5 }} component="section" aria-labelledby="walkin-size-title">
          <Box sx={{ minWidth: 0 }}>
            <Typography id="walkin-size-title" variant="h6" component="p">Pricing size · {SIZE_LABEL[size]}</Typography>
            <Typography variant="body2" color="text.secondary">
              {SIZE_HINT[size]} · {selected.size_class ? 'from the vehicle record' : `derived from ${[selected.make, selected.model].filter(Boolean).join(' ') || 'the plate'}`}{vehicleSizeOf(selected) !== size ? ' · overridden for this booking' : ''}. Car-wash prices differ for small and large vehicles.
            </Typography>
          </Box>
          <SizeToggle value={size} onChange={onSizeChange} ariaLabel="Pricing size" />
        </Tile>
      )}

      <Dialog open={open} onClose={() => !add.isPending && setOpen(false)} aria-labelledby="add-vehicle-title" fullWidth maxWidth="sm">
        <DialogTitle id="add-vehicle-title">Add vehicle</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>Entered manually (source: manual). Disc-scanned vehicles from the staff app show as verified.</Typography>
          <Box component="form" id="add-vehicle-form" onSubmit={(e) => { e.preventDefault(); if (valid) add.mutate(false); }} sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr' }, gap: 2 }}>
            <TextField label="Registration number" placeholder="KL 45 MN GP" value={form.registration_no} onChange={(e) => setForm({ ...form, registration_no: e.target.value.toUpperCase() })} required autoFocus error={form.registration_no !== '' && !regOk} helperText={form.registration_no !== '' && !regOk ? 'Too short' : ' '} sx={{ gridColumn: '1 / -1', '& input': { fontFamily: fonts.mono, letterSpacing: '0.04em' } }} />
            <TextField label="Make" value={form.make} onChange={(e) => setForm({ ...form, make: e.target.value })} />
            <TextField label="Model" value={form.model} onChange={(e) => setForm({ ...form, model: e.target.value })} />
            <TextField label="Colour" value={form.colour} onChange={(e) => setForm({ ...form, colour: e.target.value })} />
            <TextField label="Year (optional)" type="number" value={form.year} onChange={(e) => setForm({ ...form, year: e.target.value })} error={!yearOk} helperText={!yearOk ? 'Enter a 4-digit year' : ' '} slotProps={{ htmlInput: { min: 1950, max: new Date().getFullYear() + 1 } }} />
            <TextField label="VIN (optional)" value={form.vin} onChange={(e) => setForm({ ...form, vin: e.target.value.toUpperCase() })} error={!vinOk} helperText={!vinOk ? '11–17 characters, no I, O or Q' : ' '} sx={{ gridColumn: '1 / -1', '& input': { fontFamily: fonts.mono } }} />
          </Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setOpen(false)} disabled={add.isPending}>Cancel</Button>
          <Button type="submit" form="add-vehicle-form" variant="contained" color="secondary" disabled={!valid || add.isPending} startIcon={add.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="save" size={20} />}>Save vehicle</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={Boolean(conflict)} onClose={() => setConflict(null)} aria-labelledby="dup-vehicle-title">
        <DialogTitle id="dup-vehicle-title">Plate already registered</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary">{conflict?.message}. You can still register it against {customer.full_name} (for example after a change of ownership) — this is recorded in the audit log.</Typography>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setConflict(null)}>Go back</Button>
          <Button variant="contained" color="secondary" disabled={add.isPending} onClick={() => add.mutate(true)}>Register anyway</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
