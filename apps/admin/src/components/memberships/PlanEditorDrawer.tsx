'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import Chip from '@mui/material/Chip';
import Autocomplete from '@mui/material/Autocomplete';
import FormControlLabel from '@mui/material/FormControlLabel';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import DetailDrawer from '@/components/ui/DetailDrawer';
import M3Switch from '@/components/ui/M3Switch';
import Tile from '@/components/ui/Tile';
import MSymbol from '@/components/MSymbol';
import TierChip from '@/components/ui/TierChip';
import { parseRands, randsInput } from '@/components/catalogue/pricing';
import { useApi } from '@/lib/auth/AuthProvider';
import { tk } from '@/theme/tokens';
import { DISCOUNT_SCOPES, type DiscountScope, type EntitlementPeriod, type GroupSelection, type MembershipPlan, type MembershipPlanInput, type Service } from '@/lib/types';
import { SCOPE_HINT, SCOPE_LABEL, SELECTION_LABEL } from './planFormat';

interface EntitlementForm { key: string; code: string; label: string; quantity: string; period: EntitlementPeriod; service_codes: string[]; locked: boolean }
interface GroupForm { key: string; code: string; name: string; selection: GroupSelection; entitlements: EntitlementForm[] }
interface PlanForm { name: string; tagline: string; fee: string; discount_pct: string; discount_scope: DiscountScope; discount_note: string; is_active: boolean; groups: GroupForm[] }

let k = 0;
const key = () => `k${(k += 1)}`;

function fromPlan(p: MembershipPlan): PlanForm {
  return {
    name: p.name, tagline: p.tagline ?? '', fee: randsInput(p.monthly_fee_cents), discount_pct: String(p.discount_pct), discount_scope: p.discount_scope, discount_note: p.discount_note ?? '', is_active: p.is_active,
    groups: p.groups.map((g) => ({ key: key(), code: g.code, name: g.name, selection: g.selection, entitlements: g.entitlements.map((e) => ({ key: key(), code: e.code, label: e.label, quantity: String(e.quantity), period: e.period, service_codes: e.services.map((s) => s.code), locked: true })) })),
  };
}

function toInput(f: PlanForm): MembershipPlanInput {
  return {
    name: f.name.trim(), tagline: f.tagline.trim() || null, monthly_fee_cents: parseRands(f.fee) ?? 0, discount_pct: Number(f.discount_pct) || 0, discount_scope: f.discount_scope, discount_note: f.discount_note.trim() || null, is_active: f.is_active,
    groups: f.groups.map((g) => ({ code: g.code.trim(), name: g.name.trim(), selection: g.selection, entitlements: g.entitlements.map((e) => ({ code: e.code.trim(), label: e.label.trim(), quantity: Number(e.quantity) || 0, period: e.period, service_codes: e.service_codes })) })),
  };
}

function EntitlementRow({ e, services, onChange, onRemove }: { e: EntitlementForm; services: Service[]; onChange: (p: Partial<EntitlementForm>) => void; onRemove: () => void }) {
  const picked = e.service_codes.map((c) => services.find((s) => s.code === c)).filter((s): s is Service => Boolean(s));
  return (
    <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1.25, py: 1.5, bgcolor: tk.surfaceCard, border: `1px solid ${tk.outlineVariant}` }}>
      <Box sx={{ display: 'grid', gridTemplateColumns: '90px 1fr auto', gap: 1, alignItems: 'center' }}>
        <TextField label="Code" size="small" value={e.code} onChange={(ev) => onChange({ code: ev.target.value.toUpperCase() })} disabled={e.locked} slotProps={{ htmlInput: { style: { fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 700 } } }} />
        <TextField label="Label" size="small" value={e.label} onChange={(ev) => onChange({ label: ev.target.value })} placeholder="4 × Sparkling Wash" />
        <IconButton aria-label={`Remove option ${e.code || ''}`} onClick={onRemove} size="small"><MSymbol name="delete" size={20} /></IconButton>
      </Box>
      <Box sx={{ display: 'grid', gridTemplateColumns: '110px 130px', gap: 1 }}>
        <TextField label="Quantity" size="small" type="number" value={e.quantity} onChange={(ev) => onChange({ quantity: ev.target.value })} slotProps={{ htmlInput: { min: 1, step: 1 } }} />
        <TextField label="Period" size="small" select value={e.period} onChange={(ev) => onChange({ period: ev.target.value as EntitlementPeriod })}>
          <MenuItem value="month">per month</MenuItem>
          <MenuItem value="year">per year</MenuItem>
        </TextField>
      </Box>
      <Autocomplete
        multiple
        size="small"
        options={services}
        value={picked}
        getOptionLabel={(s) => `${s.name} (${s.code})`}
        isOptionEqualToValue={(a, b) => a.code === b.code}
        onChange={(_ev, v) => onChange({ service_codes: v.map((s) => s.code) })}
        renderValue={(value, getTagProps) => value.map((s, i) => { const { key: tagKey, ...tag } = getTagProps({ index: i }); return <Chip key={tagKey} size="small" label={i === 0 ? `${s.name} · primary` : s.name} {...tag} sx={{ bgcolor: i === 0 ? tk.primaryContainer : tk.surfaceContainerHigh }} />; })}
        renderInput={(params) => <TextField {...params} label="Redeemable services" helperText="Any of these redeems the option; the first is the primary service" />}
      />
    </Tile>
  );
}

/** Editor for one plan: name, tagline, fee, discount, active flag and the groups → options → service picker. */
export default function PlanEditorDrawer({ plan, onClose, onSaved, onError }: { plan: MembershipPlan | null; onClose: () => void; onSaved: (p: MembershipPlan) => void; onError: (e: unknown) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const [form, setForm] = React.useState<PlanForm | null>(() => (plan ? fromPlan(plan) : null));
  // Re-seed the form when a different plan is opened (state derived during render, no effect).
  const [seededFor, setSeededFor] = React.useState(plan);
  if (plan !== seededFor) { setSeededFor(plan); setForm(plan ? fromPlan(plan) : null); }
  const servicesQ = useQuery({ queryKey: ['services'], queryFn: () => api.listServices(), enabled: Boolean(plan) });
  const services = React.useMemo(() => (servicesQ.data ?? []).filter((s) => s.is_active && !s.is_addon), [servicesQ.data]);

  const save = useMutation({
    mutationFn: () => api.saveMembershipPlan(plan!.code, toInput(form!)),
    onSuccess: (p) => { void qc.invalidateQueries({ queryKey: ['membership-plans'] }); void qc.invalidateQueries({ queryKey: ['memberships'] }); onSaved(p); },
    onError,
  });

  const patchGroup = (gk: string, p: Partial<GroupForm>) => setForm((f) => (f ? { ...f, groups: f.groups.map((g) => (g.key === gk ? { ...g, ...p } : g)) } : f));
  const patchEnt = (gk: string, ek: string, p: Partial<EntitlementForm>) => setForm((f) => (f ? { ...f, groups: f.groups.map((g) => (g.key === gk ? { ...g, entitlements: g.entitlements.map((e) => (e.key === ek ? { ...e, ...p } : e)) } : g)) } : f));
  const fee = form ? parseRands(form.fee) : null;
  const errors = form ? {
    name: form.name.trim() === '',
    fee: fee === undefined,
    pct: !(Number(form.discount_pct) >= 0 && Number(form.discount_pct) <= 100),
    groups: form.groups.some((g) => !g.code.trim() || g.entitlements.length === 0 || g.entitlements.some((e) => !e.code.trim() || !(Number(e.quantity) > 0) || e.service_codes.length === 0)),
  } : null;
  const valid = errors ? !errors.name && !errors.fee && !errors.pct && !errors.groups : false;

  return (
    <DetailDrawer
      open={Boolean(plan)}
      onClose={onClose}
      width={{ xs: '100%', sm: 560 }}
      label="Membership plan"
      titleId="plan-editor-title"
      title={plan && (<><Typography variant="h2">{plan.name}</Typography><TierChip tier={plan.tier} /></>)}
      subtitle={plan && <>Code <span className="mono">{plan.code}</span> · fee changes apply from the next invoice · groups and options are replaced by code</>}
      footer={
        <Box sx={{ display: 'flex', gap: 1.5, justifyContent: 'flex-end' }}>
          <Button onClick={onClose} disabled={save.isPending}>Cancel</Button>
          <Button variant="contained" color="secondary" onClick={() => save.mutate()} disabled={!valid || save.isPending} startIcon={save.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="save" size={20} />}>Save plan</Button>
        </Box>
      }
    >
      {form && (
        <Box component="form" onSubmit={(e) => { e.preventDefault(); if (valid) save.mutate(); }} sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <TextField label="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required error={errors?.name} />
          <TextField label="Tagline" value={form.tagline} onChange={(e) => setForm({ ...form, tagline: e.target.value })} placeholder="Monthly washes, 10 % off everything else" />
          <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.5 }}>
            <TextField label="Monthly fee (R)" value={form.fee} onChange={(e) => setForm({ ...form, fee: e.target.value })} error={errors?.fee} helperText={errors?.fee ? 'Enter a rand amount' : 'Applies from the next invoice'} slotProps={{ input: { startAdornment: <Typography sx={{ mr: 0.5, color: tk.onSurfaceVariant }}>R</Typography> } }} />
            <TextField label="Discount %" type="number" value={form.discount_pct} onChange={(e) => setForm({ ...form, discount_pct: e.target.value })} error={errors?.pct} slotProps={{ htmlInput: { min: 0, max: 100, step: 1 } }} />
          </Box>
          <TextField select label="Discount applies to" value={form.discount_scope} onChange={(e) => setForm({ ...form, discount_scope: e.target.value as DiscountScope })} helperText={SCOPE_HINT[form.discount_scope]}>
            {DISCOUNT_SCOPES.map((s) => <MenuItem key={s} value={s}>{SCOPE_LABEL[s]}</MenuItem>)}
          </TextField>
          <TextField label="Discount note" value={form.discount_note} onChange={(e) => setForm({ ...form, discount_note: e.target.value })} placeholder="Shown on the plan card and in the customer app" />
          <Tile sx={{ justifyContent: 'space-between' }}>
            <Box>
              <Typography variant="h6" component="p">Active</Typography>
              <Typography variant="body2" color="text.secondary">Inactive plans keep existing members but cannot be joined</Typography>
            </Box>
            <FormControlLabel control={<M3Switch checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />} label="Active" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' } }} />
          </Tile>

          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mt: 1 }}>
            <Typography variant="h4" component="h3">Entitlement groups</Typography>
            <Button size="small" variant="outlined" startIcon={<MSymbol name="add" size={18} />} onClick={() => setForm({ ...form, groups: [...form.groups, { key: key(), code: '', name: '', selection: 'choose_one', entitlements: [] }] })}>Add group</Button>
          </Box>
          <Typography variant="body2" color="text.secondary" sx={{ mt: -1.5 }}>A member picks one option per “choose one” group; “all included” groups apply every option. Options that members have already redeemed cannot be deleted.</Typography>
          {form.groups.map((g) => (
            <Tile key={g.key} sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1.25, py: 1.75 }}>
              <Box sx={{ display: 'grid', gridTemplateColumns: '110px 1fr 150px auto', gap: 1, alignItems: 'center' }}>
                <TextField label="Group code" size="small" value={g.code} onChange={(e) => patchGroup(g.key, { code: e.target.value.toLowerCase() })} slotProps={{ htmlInput: { style: { fontFamily: 'ui-monospace, Menlo, monospace' } } }} />
                <TextField label="Group name" size="small" value={g.name} onChange={(e) => patchGroup(g.key, { name: e.target.value })} />
                <TextField label="Selection" size="small" select value={g.selection} onChange={(e) => patchGroup(g.key, { selection: e.target.value as GroupSelection })}>
                  {(['choose_one', 'all'] as GroupSelection[]).map((s) => <MenuItem key={s} value={s}>{SELECTION_LABEL[s]}</MenuItem>)}
                </TextField>
                <IconButton aria-label={`Remove group ${g.name || g.code}`} size="small" onClick={() => setForm({ ...form, groups: form.groups.filter((x) => x.key !== g.key) })}><MSymbol name="delete" size={20} /></IconButton>
              </Box>
              {g.entitlements.map((e) => (
                <EntitlementRow key={e.key} e={e} services={services} onChange={(p) => patchEnt(g.key, e.key, p)} onRemove={() => patchGroup(g.key, { entitlements: g.entitlements.filter((x) => x.key !== e.key) })} />
              ))}
              <Button size="small" variant="text" startIcon={<MSymbol name="add" size={18} />} onClick={() => patchGroup(g.key, { entitlements: [...g.entitlements, { key: key(), code: '', label: '', quantity: '1', period: 'month', service_codes: [], locked: false }] })} sx={{ alignSelf: 'flex-start' }}>Add option</Button>
            </Tile>
          ))}
        </Box>
      )}
    </DetailDrawer>
  );
}
