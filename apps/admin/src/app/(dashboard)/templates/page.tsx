'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import FormControlLabel from '@mui/material/FormControlLabel';
import Checkbox from '@mui/material/Checkbox';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import { LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { fmtDate } from '@/lib/format';
import type { ChecklistStep, ChecklistTemplate, ServiceCategory, StepType } from '@/lib/types';

const STEP_TYPES: { value: StepType; label: string; icon: string }[] = [
  { value: 'confirm', label: 'Confirm', icon: 'check_box' },
  { value: 'text', label: 'Text', icon: 'notes' },
  { value: 'numeric', label: 'Numeric', icon: 'pin' },
  { value: 'select', label: 'Select', icon: 'list' },
  { value: 'photo', label: 'Photo', icon: 'photo_camera' },
  { value: 'ack', label: 'Acknowledge', icon: 'handshake' },
  { value: 'supervisor_verify', label: 'Supervisor verify', icon: 'verified_user' },
];
const stepIcon = (t: StepType) => STEP_TYPES.find((x) => x.value === t)?.icon ?? 'check_box';

function StepEditor({ step, onChange, onRemove, onMove }: { step: ChecklistStep; onChange: (s: ChecklistStep) => void; onRemove: () => void; onMove: (dir: -1 | 1) => void }) {
  return (
    <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1 }}>
      <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
        <MSymbol name={stepIcon(step.type)} size={22} style={{ color: tk.primary }} />
        <TextField label="Title" value={step.title} onChange={(e) => onChange({ ...step, title: e.target.value, key: step.key || e.target.value.toLowerCase().replace(/[^a-z0-9]+/g, '_') })} size="small" sx={{ flex: 1, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
        <TextField select label="Type" value={step.type} onChange={(e) => onChange({ ...step, type: e.target.value as StepType })} size="small" sx={{ width: 170, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }}>
          {STEP_TYPES.map((t) => <MenuItem key={t.value} value={t.value}>{t.label}</MenuItem>)}
        </TextField>
        <IconButton size="small" aria-label="Move up" onClick={() => onMove(-1)}><MSymbol name="arrow_upward" size={18} /></IconButton>
        <IconButton size="small" aria-label="Move down" onClick={() => onMove(1)}><MSymbol name="arrow_downward" size={18} /></IconButton>
        <IconButton size="small" aria-label="Remove step" onClick={onRemove}><MSymbol name="delete" size={18} /></IconButton>
      </Box>
      <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
        <TextField label="Key" value={step.key} onChange={(e) => onChange({ ...step, key: e.target.value })} size="small" sx={{ width: 150, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} slotProps={{ htmlInput: { className: 'mono' } }} />
        <TextField label="Hint" value={step.hint ?? ''} onChange={(e) => onChange({ ...step, hint: e.target.value })} size="small" sx={{ flex: 1, minWidth: 180, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
        {step.type === 'numeric' && (
          <>
            <TextField label="Unit" value={step.unit ?? ''} onChange={(e) => onChange({ ...step, unit: e.target.value })} size="small" sx={{ width: 80, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
            <TextField label="Min" type="number" value={step.min ?? ''} onChange={(e) => onChange({ ...step, min: e.target.value === '' ? undefined : Number(e.target.value) })} size="small" sx={{ width: 80, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
            <TextField label="Max" type="number" value={step.max ?? ''} onChange={(e) => onChange({ ...step, max: e.target.value === '' ? undefined : Number(e.target.value) })} size="small" sx={{ width: 80, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
          </>
        )}
        {step.type === 'select' && <TextField label="Options (comma separated)" value={(step.options ?? []).join(', ')} onChange={(e) => onChange({ ...step, options: e.target.value.split(',').map((x) => x.trim()).filter(Boolean) })} size="small" sx={{ minWidth: 220, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />}
        <FormControlLabel control={<Checkbox checked={step.required} onChange={(e) => onChange({ ...step, required: e.target.checked })} size="small" />} label="Required" />
        {step.type === 'photo' && <FormControlLabel control={<Checkbox checked={step.photo_required ?? true} onChange={(e) => onChange({ ...step, photo_required: e.target.checked })} size="small" />} label="Photo required" />}
      </Box>
    </Tile>
  );
}

function TemplateDrawer({ tpl, open, onClose }: { tpl: ChecklistTemplate | null; open: boolean; onClose: () => void }) {
  return (
    <Drawer anchor="right" open={open} onClose={onClose} slotProps={{ paper: { sx: { width: { xs: '100%', md: 720 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
      {open && <TemplateForm tpl={tpl} onClose={onClose} />}
    </Drawer>
  );
}

function TemplateForm({ tpl, onClose }: { tpl: ChecklistTemplate | null; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [name, setName] = React.useState(tpl?.name ?? '');
  const [category, setCategory] = React.useState<ServiceCategory>(tpl?.category ?? 'car_wash');
  const [steps, setSteps] = React.useState<ChecklistStep[]>(() => (tpl ? tpl.steps.map((s) => ({ ...s })) : [{ key: 'step_1', title: '', type: 'confirm', required: true }]));
  const m = useMutation({
    mutationFn: (publish: boolean) => (tpl ? api.updateTemplate(tpl.id, { name, category, steps, publish }) : api.createTemplate({ name, category, steps })),
    onSuccess: (t, publish) => { toast.success(publish ? `Published ${t.name} v${t.version}` : `Saved ${t.name} draft`); void qc.invalidateQueries({ queryKey: ['templates'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  const valid = name.trim() && steps.length > 0 && steps.every((s) => s.title.trim() && s.key.trim()) && new Set(steps.map((s) => s.key)).size === steps.length;
  const update = (i: number, s: ChecklistStep) => setSteps(steps.map((x, j) => (j === i ? s : x)));
  const move = (i: number, dir: -1 | 1) => { const j = i + dir; if (j < 0 || j >= steps.length) return; const next = [...steps]; [next[i], next[j]] = [next[j], next[i]]; setSteps(next); };
  return (
    <>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
        <Typography variant="h3">{tpl ? `${tpl.name} · v${tpl.version}` : 'New checklist template'}</Typography>
        <IconButton aria-label="Close" onClick={onClose}><MSymbol name="close" /></IconButton>
      </Box>
      <Box sx={{ display: 'flex', gap: 1.5, mb: 2 }}>
        <TextField label="Name" value={name} onChange={(e) => setName(e.target.value)} size="small" sx={{ flex: 1 }} />
        <TextField select label="Category" value={category} onChange={(e) => setCategory(e.target.value as ServiceCategory)} size="small" sx={{ width: 160 }}>
          <MenuItem value="car_wash">Car wash</MenuItem>
          <MenuItem value="auto_body">Auto body</MenuItem>
        </TextField>
      </Box>
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
        {steps.map((s, i) => <StepEditor key={i} step={s} onChange={(x) => update(i, x)} onRemove={() => setSteps(steps.filter((_, j) => j !== i))} onMove={(d) => move(i, d)} />)}
      </Box>
      <Button variant="text" onClick={() => setSteps([...steps, { key: `step_${steps.length + 1}`, title: '', type: 'confirm', required: true }])} startIcon={<MSymbol name="add" size={18} />} sx={{ alignSelf: 'flex-start', mt: 1 }}>Add step</Button>
      <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>Publishing creates a new immutable version; in-flight work orders keep the version they started with (ADM-026).</Typography>
      <Box sx={{ display: 'flex', gap: 1.25, mt: 2 }}>
        <Button variant="outlined" disabled={!valid || m.isPending} onClick={() => m.mutate(false)}>Save draft</Button>
        <Button variant="contained" color="secondary" disabled={!valid || m.isPending} onClick={() => m.mutate(true)} startIcon={<MSymbol name="publish" size={20} />}>Publish {tpl ? `v${Math.max(tpl.version, tpl.status === 'draft' ? tpl.version : tpl.version) + (tpl.status === 'draft' ? 0 : 1)}` : 'v1'}</Button>
      </Box>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

export default function TemplatesPage() {
  const api = useApi();
  const { role } = useAuth();
  const q = useQuery({ queryKey: ['templates'], queryFn: () => api.listTemplates() });
  const [edit, setEdit] = React.useState<ChecklistTemplate | null>(null);
  const [open, setOpen] = React.useState(false);
  const manage = can(role, 'template:manage');
  return (
    <>
      <PageHeader title="Configuration" subtitle="Checklist templates · versioned step definitions used by the staff app" actions={manage ? <NavyPill icon="playlist_add" onClick={() => { setEdit(null); setOpen(true); }}>New template</NavyPill> : undefined} />
      <ConfigTabs />
      {q.isLoading && <LoadingRows rows={3} height={120} />}
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: 'repeat(2, 1fr)' }, gap: '14px' }}>
        {(q.data ?? []).map((t) => (
          <SectionCard
            key={t.id}
            title={<Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}><Typography variant="h4" component="h2">{t.name}</Typography><Chip size="small" label={`v${t.version}`} sx={{ bgcolor: tk.surfaceContainerHigh }} /><StatusChip status={t.status} /></Box>}
            subtitle={`${t.category === 'car_wash' ? 'Car wash' : 'Auto body'} · ${t.steps.length} steps · ${t.steps.filter((s) => s.required).length} required · created ${fmtDate(t.created_at, 'd MMM yyyy')}`}
            actions={manage ? <Button size="small" variant="outlined" onClick={() => { setEdit(t); setOpen(true); }} startIcon={<MSymbol name="edit" size={18} />}>{t.status === 'published' ? 'New version' : 'Edit'}</Button> : undefined}
          >
            <Box component="ol" sx={{ m: 0, pl: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 0.75 }}>
              {t.steps.map((s, i) => (
                <Box component="li" key={s.key} sx={{ display: 'flex', alignItems: 'center', gap: 1.25, px: 1.5, py: 1, borderRadius: '14px', bgcolor: tk.surfaceContainer }}>
                  <Typography variant="caption" sx={{ width: 18, fontWeight: 700, color: tk.onSurfaceVariant }}>{i + 1}</Typography>
                  <MSymbol name={stepIcon(s.type)} size={20} style={{ color: s.type === 'supervisor_verify' ? tk.onWarningContainer : tk.primary }} />
                  <Typography variant="body1" sx={{ flex: 1, fontWeight: 500 }}>{s.title}</Typography>
                  {s.unit && <Chip size="small" label={`${s.min ?? ''}–${s.max ?? ''} ${s.unit}`} sx={{ height: 22, fontSize: 11, bgcolor: tk.surfaceCard }} />}
                  {s.options && <Chip size="small" label={s.options.join(' / ')} sx={{ height: 22, fontSize: 11, bgcolor: tk.surfaceCard }} />}
                  {s.required && <Chip size="small" label="Required" sx={{ height: 22, fontSize: 10.5, bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer }} />}
                </Box>
              ))}
            </Box>
          </SectionCard>
        ))}
      </Box>
      <TemplateDrawer tpl={edit} open={open} onClose={() => setOpen(false)} />
    </>
  );
}
