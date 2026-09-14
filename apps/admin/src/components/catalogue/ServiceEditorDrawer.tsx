'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Radio from '@mui/material/Radio';
import RadioGroup from '@mui/material/RadioGroup';
import FormControlLabel from '@mui/material/FormControlLabel';
import FormLabel from '@mui/material/FormLabel';
import FormControl from '@mui/material/FormControl';
import InputAdornment from '@mui/material/InputAdornment';
import Autocomplete from '@mui/material/Autocomplete';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import DetailDrawer from '@/components/ui/DetailDrawer';
import IconTile from '@/components/ui/IconTile';
import M3Switch from '@/components/ui/M3Switch';
import StatusChip from '@/components/ui/StatusChip';
import MSymbol from '@/components/MSymbol';
import ComponentListEditor, { makeCycleFor } from './ComponentListEditor';
import { GROUP_ICON, PRICING_MODE_HINT, PRICING_MODE_LABEL, SERVICE_ICONS, VAT_MODE_HINT, VAT_MODE_LABEL, isSizePriced, parseRands, randsInput } from './pricing';
import { useApi } from '@/lib/auth/AuthProvider';
import { fonts, tk } from '@/theme/tokens';
import { SERVICE_GROUPS, type PricingMode, type Service, type ServiceCategory, type ServiceComponent, type ServiceGroup, type ServiceInput, type VatMode } from '@/lib/types';

interface Form {
  code: string; name: string; description: string; group_name: ServiceGroup; category: ServiceCategory; duration_minutes: string;
  pricing_mode: PricingMode; vat_mode: VatMode; price_small: string; price_large: string; price_general: string;
  is_addon: boolean; addon_group_name: ServiceGroup | ''; notes: string; icon: string; checklist_template_id: string; is_active: boolean; components: ServiceComponent[];
}

const fromService = (s: Service | null): Form => ({
  code: s?.code ?? '', name: s?.name ?? '', description: s?.description ?? '', group_name: s?.group_name ?? 'Car Wash Options', category: s?.category ?? 'car_wash',
  duration_minutes: String(s?.duration_minutes ?? 30), pricing_mode: s?.pricing_mode ?? 'from', vat_mode: s?.vat_mode ?? 'incl',
  price_small: randsInput(s?.price_small_cents), price_large: randsInput(s?.price_large_cents), price_general: randsInput(s?.price_general_cents),
  is_addon: s?.is_addon ?? false, addon_group_name: (s?.addon_group_name as ServiceGroup | null) ?? '', notes: s?.notes ?? '', icon: s?.icon ?? 'local_car_wash',
  checklist_template_id: s?.checklist_template_id ?? '', is_active: s?.is_active ?? true, components: s ? [...s.components] : [],
});

/**
 * Service editor (right-hand drawer): identity, group / category, pricing + VAT mode, per-size
 * prices, add-on flag, the global composite set ("This service includes") and the read-only
 * "Included in" list. `service === null` creates a new service.
 */
interface DrawerProps {
  open: boolean;
  service: Service | null;
  services: Service[];
  readOnly: boolean;
  onClose: () => void;
  onSaved: (s: Service, created: boolean) => void;
  onError: (e: unknown) => void;
}

export default function ServiceEditorDrawer(props: DrawerProps) {
  // Remount the form each time the drawer opens so its state starts from the current service.
  const [session, setSession] = React.useState(0);
  const [wasOpen, setWasOpen] = React.useState(props.open);
  if (props.open !== wasOpen) {
    setWasOpen(props.open);
    if (props.open) setSession((n) => n + 1);
  }
  return <ServiceEditorForm key={`${session}:${props.service?.id ?? 'new'}`} {...props} />;
}

function ServiceEditorForm({ open, service, services, readOnly, onClose, onSaved, onError }: DrawerProps) {
  const api = useApi();
  const qc = useQueryClient();
  const templates = useQuery({ queryKey: ['templates'], queryFn: () => api.listTemplates(), enabled: open });
  const [form, setForm] = React.useState<Form>(() => fromService(service));
  const [dirty, setDirty] = React.useState(false);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => { setForm((f) => ({ ...f, [k]: v })); setDirty(true); };

  const selfId = service?.id ?? '__new__';
  const sizePriced = isSizePriced(form.group_name);
  const byQuote = form.pricing_mode === 'by_quote';
  const options = React.useMemo(() => services.filter((s) => s.id !== selfId && s.category === form.category).map((s) => ({ id: s.id, code: s.code, name: s.name, hint: s.group_name })), [services, selfId, form.category]);
  const edges = React.useMemo(() => new Map(services.map((s) => [s.id, s.components.map((c) => c.child_service_id)])), [services]);
  const codeOf = React.useCallback((id: string) => services.find((s) => s.id === id)?.code ?? (id === selfId ? form.code || 'THIS' : id), [services, selfId, form.code]);
  const cycleFor = React.useMemo(() => makeCycleFor(selfId, edges, codeOf), [selfId, edges, codeOf]);
  const includedIn = React.useMemo(() => (service ? services.filter((s) => s.components.some((c) => c.child_service_id === service.id)) : []), [service, services]);
  const hasCycle = form.components.some((c) => cycleFor(c.child_service_id));

  const priceErr = (v: string) => v !== '' && parseRands(v) === undefined;
  const codeOk = /^[A-Z0-9_]{2,40}$/.test(form.code);
  const duplicateCode = services.some((s) => s.id !== selfId && s.code === form.code);
  const durationOk = Number(form.duration_minutes) > 0;
  const valid = codeOk && !duplicateCode && form.name.trim().length > 0 && durationOk && !hasCycle && !priceErr(form.price_small) && !priceErr(form.price_large) && !priceErr(form.price_general) && (!form.is_addon || form.addon_group_name);

  const save = useMutation({
    mutationFn: async () => {
      const body: ServiceInput = {
        code: form.code, name: form.name.trim(), description: form.description.trim() || null, group_name: form.group_name, category: form.category,
        duration_minutes: Number(form.duration_minutes), pricing_mode: form.pricing_mode, vat_mode: form.vat_mode,
        price_small_cents: byQuote || !sizePriced ? null : parseRands(form.price_small) ?? null,
        price_large_cents: byQuote || !sizePriced ? null : parseRands(form.price_large) ?? null,
        price_general_cents: byQuote || sizePriced ? null : parseRands(form.price_general) ?? null,
        is_addon: form.is_addon, addon_group_name: form.is_addon ? form.addon_group_name || null : null, notes: form.notes.trim() || null,
        icon: form.icon.trim() || 'local_car_wash', checklist_template_id: form.checklist_template_id || null, is_active: form.is_active, components: form.components,
      };
      return service ? api.updateService(service.id, body) : api.createService(body);
    },
    onSuccess: (s) => {
      void qc.invalidateQueries({ queryKey: ['services'] });
      void qc.invalidateQueries({ queryKey: ['outlet-offers'] });
      void qc.invalidateQueries({ queryKey: ['walkin-services'] });
      setDirty(false);
      onSaved(s, !service);
    },
    onError,
  });

  const field = (label: string, key: keyof Form, extra: Partial<React.ComponentProps<typeof TextField>> = {}) => (
    <TextField label={label} value={form[key] as string} onChange={(e) => set(key, e.target.value as never)} size="small" disabled={readOnly} {...extra} />
  );

  return (
    <DetailDrawer
      open={open}
      onClose={onClose}
      width={{ xs: '100%', sm: 600 }}
      label={service ? 'Service' : 'New service'}
      closeLabel="Close service editor"
      titleId="service-editor-title"
      title={(
        <>
          <IconTile icon={form.icon || 'local_car_wash'} tone={form.category === 'auto_body' ? 'neutral' : 'primary'} size={40} />
          <Typography variant="h2" component="h2" sx={{ minWidth: 0 }}>{form.name || (service ? service.name : 'New service')}</Typography>
          {service && <Chip size="small" label={service.code} sx={{ fontFamily: fonts.mono, bgcolor: tk.surfaceContainerHigh }} />}
          {!form.is_active && <StatusChip tone="neutral" label="Inactive" />}
        </>
      )}
      subtitle={readOnly ? 'Read-only — service management needs the Admin role.' : service ? `${form.group_name} · edits apply to every outlet that inherits these values.` : 'Define the canonical service; bind it to outlets from Outlets → Catalogue.'}
      footer={!readOnly && (
        <Box sx={{ display: 'flex', gap: 1.5, justifyContent: 'flex-end' }}>
          <Button onClick={onClose} disabled={save.isPending}>Cancel</Button>
          <Button variant="contained" color="secondary" disabled={!valid || !dirty || save.isPending} onClick={() => save.mutate()} startIcon={save.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="save" size={20} />} sx={{ px: 3 }}>
            {service ? 'Save changes' : 'Create service'}
          </Button>
        </Box>
      )}
    >
      <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.75 }}>
        {field('Name', 'name', { required: true, sx: { gridColumn: '1 / -1' } })}
        <TextField label="Code" value={form.code} onChange={(e) => set('code', e.target.value.toUpperCase().replace(/[^A-Z0-9_]+/g, '_'))} size="small" required disabled={readOnly} error={form.code !== '' && (!codeOk || duplicateCode)} helperText={duplicateCode ? 'Another service uses this code' : form.code !== '' && !codeOk ? 'A–Z, 0–9 and _ only' : 'Stable identifier used by the apps'} slotProps={{ htmlInput: { style: { fontFamily: fonts.mono } } }} />
        <TextField label="Duration (min)" type="number" value={form.duration_minutes} onChange={(e) => set('duration_minutes', e.target.value)} size="small" disabled={readOnly} error={!durationOk} helperText={!durationOk ? 'Must be positive' : ' '} slotProps={{ htmlInput: { min: 5, step: 5 } }} />
        {field('Description', 'description', { multiline: true, minRows: 2, sx: { gridColumn: '1 / -1' } })}
        <TextField select label="Group" value={form.group_name} onChange={(e) => { const g = e.target.value as ServiceGroup; set('group_name', g); set('category', g === 'Auto Body Repair' ? 'auto_body' : 'car_wash'); set('vat_mode', g === 'Auto Body Repair' ? 'excl' : 'incl'); }} size="small" disabled={readOnly} helperText="Price-sheet group (tab)">
          {SERVICE_GROUPS.map((g) => <MenuItem key={g} value={g}><MSymbol name={GROUP_ICON[g]} size={18} style={{ marginRight: 8 }} />{g}</MenuItem>)}
        </TextField>
        <TextField select label="Category" value={form.category} onChange={(e) => set('category', e.target.value as ServiceCategory)} size="small" disabled={readOnly} helperText="Drives checklists and reporting">
          <MenuItem value="car_wash">Car wash</MenuItem>
          <MenuItem value="auto_body">Auto body</MenuItem>
        </TextField>

        <FormControl component="fieldset" disabled={readOnly} sx={{ gridColumn: '1 / -1' }}>
          <FormLabel component="legend" sx={{ fontSize: 12.5, fontWeight: 600, color: tk.onSurfaceVariant }}>Pricing mode</FormLabel>
          <RadioGroup row value={form.pricing_mode} onChange={(e) => set('pricing_mode', e.target.value as PricingMode)}>
            {(Object.keys(PRICING_MODE_LABEL) as PricingMode[]).map((m) => <FormControlLabel key={m} value={m} control={<Radio size="small" />} label={<span title={PRICING_MODE_HINT[m]}>{PRICING_MODE_LABEL[m]}</span>} />)}
          </RadioGroup>
          <Typography variant="caption" color="text.secondary">{PRICING_MODE_HINT[form.pricing_mode]}</Typography>
        </FormControl>
        <FormControl component="fieldset" disabled={readOnly} sx={{ gridColumn: '1 / -1' }}>
          <FormLabel component="legend" sx={{ fontSize: 12.5, fontWeight: 600, color: tk.onSurfaceVariant }}>VAT</FormLabel>
          <RadioGroup row value={form.vat_mode} onChange={(e) => set('vat_mode', e.target.value as VatMode)}>
            {(Object.keys(VAT_MODE_LABEL) as VatMode[]).map((m) => <FormControlLabel key={m} value={m} control={<Radio size="small" />} label={VAT_MODE_LABEL[m]} />)}
          </RadioGroup>
          <Typography variant="caption" color="text.secondary">{VAT_MODE_HINT[form.vat_mode]}</Typography>
        </FormControl>

        <Typography variant="h5" component="h3" sx={{ gridColumn: '1 / -1', mt: 0.5 }}>Default prices <Typography component="span" variant="body2" color="text.secondary">· outlets override these in their catalogue</Typography></Typography>
        {sizePriced ? (
          <>
            <TextField label="Small vehicle" value={form.price_small} onChange={(e) => set('price_small', e.target.value)} size="small" disabled={readOnly || byQuote} error={priceErr(form.price_small)} helperText={byQuote ? 'No price — by quote' : 'Hatch / sedan · bike uses this'} slotProps={{ input: { startAdornment: <InputAdornment position="start">R</InputAdornment> }, htmlInput: { inputMode: 'decimal' } }} />
            <TextField label="Large vehicle" value={form.price_large} onChange={(e) => set('price_large', e.target.value)} size="small" disabled={readOnly || byQuote} error={priceErr(form.price_large)} helperText={byQuote ? 'No price — by quote' : 'SUV / bakkie / bus · falls back to small'} slotProps={{ input: { startAdornment: <InputAdornment position="start">R</InputAdornment> }, htmlInput: { inputMode: 'decimal' } }} />
          </>
        ) : (
          <TextField label="General price" value={form.price_general} onChange={(e) => set('price_general', e.target.value)} size="small" disabled={readOnly || byQuote} error={priceErr(form.price_general)} helperText={byQuote ? 'No price — by quote' : 'Size-independent (auto body)'} sx={{ gridColumn: '1 / -1' }} slotProps={{ input: { startAdornment: <InputAdornment position="start">R</InputAdornment> }, htmlInput: { inputMode: 'decimal' } }} />
        )}

        <Box sx={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
          <FormControlLabel control={<M3Switch checked={form.is_addon} disabled={readOnly} onChange={(e) => { set('is_addon', e.target.checked); if (e.target.checked && !form.addon_group_name) set('addon_group_name', form.group_name); }} />} label="Add-on" title="Attaches to a booking of a service in the chosen group and is priced the same way" />
          {form.is_addon && (
            <TextField select label="Attaches to group" value={form.addon_group_name} onChange={(e) => set('addon_group_name', e.target.value as ServiceGroup)} size="small" disabled={readOnly} required error={!form.addon_group_name} sx={{ minWidth: 220 }}>
              {SERVICE_GROUPS.map((g) => <MenuItem key={g} value={g}>{g}</MenuItem>)}
            </TextField>
          )}
        </Box>

        <Typography variant="h5" component="h3" sx={{ gridColumn: '1 / -1', mt: 0.5 }}>Composite <Typography component="span" variant="body2" color="text.secondary">· global default set; outlets may override</Typography></Typography>
        <Box sx={{ gridColumn: '1 / -1' }}>
          <ComponentListEditor value={form.components} onChange={(c) => set('components', c)} options={options} cycleFor={cycleFor} disabled={readOnly} />
        </Box>
        {service && (
          <Box sx={{ gridColumn: '1 / -1' }}>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Included in</Typography>
            {includedIn.length ? (
              <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap' }}>
                {includedIn.map((p) => <Chip key={p.id} size="small" icon={<MSymbol name="layers" size={16} />} label={p.name} sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer, fontWeight: 600 }} />)}
              </Box>
            ) : <Typography variant="body2" color="text.secondary">Not part of any composite.</Typography>}
          </Box>
        )}

        <Typography variant="h5" component="h3" sx={{ gridColumn: '1 / -1', mt: 0.5 }}>Presentation</Typography>
        <Autocomplete
          freeSolo
          options={SERVICE_ICONS}
          value={form.icon}
          onInputChange={(_e, v) => set('icon', v)}
          disabled={readOnly}
          renderOption={(props, o) => { const { key, ...rest } = props as React.HTMLAttributes<HTMLLIElement> & { key: string }; return <li key={key} {...rest}><MSymbol name={o} size={20} filled style={{ marginRight: 10 }} />{o}</li>; }}
          renderInput={(params) => <TextField {...params} label="Icon (Material Symbol)" size="small" slotProps={{ input: { ...params.InputProps, startAdornment: <InputAdornment position="start"><MSymbol name={form.icon || 'local_car_wash'} size={20} filled /></InputAdornment> } }} />}
        />
        <TextField select label="Checklist template" value={form.checklist_template_id} onChange={(e) => set('checklist_template_id', e.target.value)} size="small" disabled={readOnly}>
          <MenuItem value="">None</MenuItem>
          {(templates.data ?? []).filter((t) => t.status === 'published').map((t) => <MenuItem key={t.id} value={t.id}>{t.name} · v{t.version}</MenuItem>)}
        </TextField>
        {field('Internal notes', 'notes', { multiline: true, minRows: 2, sx: { gridColumn: '1 / -1' } })}
        <FormControlLabel sx={{ gridColumn: '1 / -1' }} control={<M3Switch checked={form.is_active} disabled={readOnly} onChange={(e) => set('is_active', e.target.checked)} />} label={form.is_active ? 'Active — offered where outlets have it switched on' : 'Inactive — hidden from every outlet and the apps'} />
      </Box>
    </DetailDrawer>
  );
}
