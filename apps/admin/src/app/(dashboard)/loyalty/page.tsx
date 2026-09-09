'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import Link from 'next/link';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import Tile from '@/components/ui/Tile';
import M3Switch from '@/components/ui/M3Switch';
import StatusChip from '@/components/ui/StatusChip';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill, TonalPill } from '@/components/ui/Pills';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { fmtDateTime, num } from '@/lib/format';
import type { LoyaltyConfig, LoyaltyRules, LoyaltyTierConfig } from '@/lib/types';

const tierDot = { silver: 'linear-gradient(135deg,#E1EAF2,#C3CFDA)', gold: tk.goldGradient, platinum: 'linear-gradient(135deg,#8BD2FF,#203060)' } as const;

function qualify(t: LoyaltyTierConfig) {
  return t.max_points == null ? `${num(t.min_points)}+ pts` : `${num(t.min_points)} – ${num(t.max_points)} pts`;
}
function earnRate(t: LoyaltyTierConfig, rules: LoyaltyRules) {
  const perR10 = rules.points_per_rand * 10 * t.earn_multiplier;
  return `${Number(perR10.toFixed(2))} pt${perR10 === 1 ? '' : 's'} / R10`;
}
function discount(t: LoyaltyTierConfig) {
  if (t.discount_pct === 0) return '—';
  return t.tier === 'platinum' ? `${t.discount_pct}% + priority slots` : `${t.discount_pct}%`;
}

interface TierRowProps {
  t: LoyaltyTierConfig;
  label: string;
  value: string;
  field?: keyof LoyaltyTierConfig;
  step?: number;
  highlight?: boolean;
  editable?: boolean;
  onChange?: (patch: Partial<LoyaltyTierConfig>) => void;
}
function TierRow({ t, label, value, field, step = 1, highlight, editable, onChange }: TierRowProps) {
  return (
    <Tile tone={highlight ? 'gold' : 'default'} sx={{ justifyContent: 'space-between', minHeight: 54 }}>
      <Typography sx={{ fontSize: 15, color: tk.onSurfaceVariant }}>{label}</Typography>
      {editable && field ? (
        <TextField type="number" size="small" value={t[field] ?? ''} onChange={(e) => onChange?.({ [field]: e.target.value === '' ? null : Number(e.target.value) })} slotProps={{ htmlInput: { step, 'aria-label': `${t.name} ${label}` } }} sx={{ width: 120, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
      ) : (
        <Typography sx={{ fontSize: 15.5, fontWeight: 700 }}>{value}</Typography>
      )}
    </Tile>
  );
}

function TierCard({ t, rules, highlight, editable, onChange }: { t: LoyaltyTierConfig; rules: LoyaltyRules; highlight?: boolean; editable?: boolean; onChange?: (patch: Partial<LoyaltyTierConfig>) => void }) {
  const rowProps = { t, highlight, editable, onChange };
  return (
    <Paper sx={{ p: 2, display: 'flex', flexDirection: 'column', gap: 1.25, ...(highlight && { border: `2px solid ${tk.gold}` }) }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, px: 0.5, py: 0.5 }}>
        <Box sx={{ width: 22, height: 22, borderRadius: '50%', background: tierDot[t.tier], boxShadow: highlight ? `0 0 0 3px color-mix(in srgb, ${tk.gold} 30%, transparent)` : 'none' }} />
        <Typography variant="h3" component="h2" sx={{ color: highlight ? tk.onGold : tk.onSurface, fontSize: 20 }}>{t.name}</Typography>
        <Box sx={{ flex: 1 }} />
        <Typography variant="body1" color="text.secondary">{num(t.members ?? 0)} members</Typography>
      </Box>
      <TierRow {...rowProps} label="Qualify" value={qualify(t)} field="min_points" />
      {editable && t.max_points != null && <TierRow {...rowProps} label="Up to" value="" field="max_points" />}
      <TierRow {...rowProps} label="Earn rate" value={earnRate(t, rules)} field="earn_multiplier" step={0.05} />
      <TierRow {...rowProps} label="Booking discount" value={discount(t)} field="discount_pct" />
    </Paper>
  );
}

function RuleTile({ icon, title, subtitle, checked, disabled, onChange }: { icon: string; title: string; subtitle: string; checked: boolean; disabled?: boolean; onChange?: (v: boolean) => void }) {
  return (
    <Tile sx={{ minHeight: 76, opacity: disabled ? 0.6 : 1 }}>
      <MSymbol name={icon} filled size={26} style={{ color: disabled ? tk.onSurfaceVariant : tk.primary }} />
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography variant="h5" component="h3">{title}</Typography>
        <Typography variant="body2" color="text.secondary">{subtitle}</Typography>
      </Box>
      <M3Switch checked={checked} disabled={disabled || !onChange} onChange={(e) => onChange?.(e.target.checked)} slotProps={{ input: { 'aria-label': title } }} />
    </Tile>
  );
}

function diffSummary(published: LoyaltyConfig, draft: LoyaltyConfig): string[] {
  const out: string[] = [];
  for (const d of draft.tiers) {
    const p = published.tiers.find((t) => t.tier === d.tier);
    if (!p) continue;
    if (p.min_points !== d.min_points) out.push(`${d.name} qualify ${num(p.min_points)} → ${num(d.min_points)} pts`);
    if (p.earn_multiplier !== d.earn_multiplier) out.push(`${d.name} earn rate ${Number((published.rules.points_per_rand * 10 * p.earn_multiplier).toFixed(2))} → ${Number((draft.rules.points_per_rand * 10 * d.earn_multiplier).toFixed(2))} pts/R10`);
    if (p.discount_pct !== d.discount_pct) out.push(`${d.name} discount ${p.discount_pct}% → ${d.discount_pct}%`);
  }
  if (published.rules.points_per_rand !== draft.rules.points_per_rand) out.push(`Base earn ${published.rules.points_per_rand} → ${draft.rules.points_per_rand} pts per R1`);
  if (published.rules.expiry_months !== draft.rules.expiry_months) out.push(`Points expiry ${published.rules.expiry_months} → ${draft.rules.expiry_months} months`);
  if (published.rules.referral_bonus.points !== draft.rules.referral_bonus.points || published.rules.referral_bonus.enabled !== draft.rules.referral_bonus.enabled) out.push(`Referral bonus ${published.rules.referral_bonus.enabled ? published.rules.referral_bonus.points : 'off'} → ${draft.rules.referral_bonus.enabled ? draft.rules.referral_bonus.points : 'off'} pts`);
  if (published.rules.birthday_bonus.enabled !== draft.rules.birthday_bonus.enabled) out.push(`Birthday bonus ${published.rules.birthday_bonus.enabled ? 'on' : 'off'} → ${draft.rules.birthday_bonus.enabled ? 'on' : 'off'}`);
  return out;
}

export default function LoyaltyPage() {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const q = useQuery({ queryKey: ['loyalty-config'], queryFn: () => api.loyaltyConfig() });
  const [editing, setEditing] = React.useState(false);
  const [work, setWork] = React.useState<{ tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string } | null>(null);
  const [confirm, setConfirm] = React.useState(false);
  const [auditOpen, setAuditOpen] = React.useState(false);
  const audit = useQuery({ queryKey: ['audit', 'loyalty_config'], queryFn: () => api.listAudit({ entity_type: 'loyalty_config', limit: 20 }), enabled: auditOpen });

  const published = q.data?.published;
  const draft = q.data?.draft ?? null;
  const canDraft = can(role, 'loyalty:draft');
  const canPublish = can(role, 'loyalty:publish');

  const startEdit = () => {
    const base = draft ?? published!;
    setWork({ tiers: base.tiers.map((t) => ({ ...t })), rules: JSON.parse(JSON.stringify(base.rules)) as LoyaltyRules, change_note: draft?.change_note ?? '' });
    setEditing(true);
  };
  const invalidate = () => { void qc.invalidateQueries({ queryKey: ['loyalty-config'] }); void qc.invalidateQueries({ queryKey: ['audit'] }); };
  const save = useMutation({ mutationFn: () => api.saveLoyaltyDraft(work!), onSuccess: (d) => { toast.success(`Draft v${d.version} saved`); setEditing(false); invalidate(); }, onError: (e) => toast.error(e) });
  const publish = useMutation({ mutationFn: () => api.publishLoyalty(), onSuccess: (d) => { toast.success(`v${d.version} published — takes effect server-side within 60 s`); setConfirm(false); invalidate(); }, onError: (e) => { setConfirm(false); toast.error(e); } });
  const discard = useMutation({ mutationFn: () => api.discardLoyalty(), onSuccess: () => { toast.info('Draft discarded'); setEditing(false); invalidate(); }, onError: (e) => toast.error(e) });

  const view = editing && work ? { tiers: work.tiers, rules: work.rules } : draft ?? published;
  const diffs = published && draft ? diffSummary(published, draft) : [];
  const nextVersion = draft?.version ?? (published ? published.version + 1 : 1);

  return (
    <>
      <PageHeader
        title="Loyalty program"
        subtitle="Tiers, earning and redemption rules · applied server-side, no app release needed"
        actions={
          <>
            {published && <StatusChip tone="success" icon={<MSymbol name="verified" filled size={18} style={{ color: 'inherit' }} />} label={`Published · v${published.version}`} sx={{ height: 44, px: 1, fontSize: 15, '& .MuiChip-icon': { color: 'inherit' } }} />}
            <TonalPill icon="history" endIcon={null} onClick={() => setAuditOpen(true)}>Audit log</TonalPill>
            {canDraft && !editing && <NavyPill icon="edit" onClick={startEdit}>{draft ? 'Edit draft' : 'New draft'}</NavyPill>}
            {editing && (
              <>
                <TonalPill endIcon={null} onClick={() => setEditing(false)}>Cancel</TonalPill>
                <NavyPill icon="save" onClick={() => save.mutate()} disabled={save.isPending}>Save draft v{nextVersion}</NavyPill>
              </>
            )}
          </>
        }
      />
      {q.isLoading && <LoadingRows rows={3} height={200} />}
      {q.error && <ErrorState error={q.error} onRetry={() => q.refetch()} />}
      {view && published && (
        <>
          <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(3, 1fr)' }, gap: '14px' }}>
            {view.tiers.map((t) => (
              <TierCard
                key={t.tier}
                t={t}
                rules={view.rules}
                highlight={t.tier === 'gold'}
                editable={editing}
                onChange={(patch) => setWork((w) => (w ? { ...w, tiers: w.tiers.map((x) => (x.tier === t.tier ? { ...x, ...patch } : x)) } : w))}
              />
            ))}
          </Box>
          <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.5fr 1fr' }, gap: '14px', alignItems: 'start' }}>
            <SectionCard title="Earning & expiry rules">
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
                <RuleTile icon="payments" title={`Base earn — completed paid services only · ${view.rules.points_per_rand} pt per R1`} subtitle="Awarded once per payment via idempotent ledger entry (CUS-064)" checked={view.rules.idempotent_award} onChange={editing ? (v) => setWork((w) => (w ? { ...w, rules: { ...w.rules, idempotent_award: v } } : w)) : undefined} />
                {editing && (
                  <Box sx={{ display: 'flex', gap: 1.5, px: 1 }}>
                    <TextField label="Points per R1" type="number" size="small" value={work?.rules.points_per_rand ?? ''} onChange={(e) => setWork((w) => (w ? { ...w, rules: { ...w.rules, points_per_rand: Number(e.target.value) } } : w))} slotProps={{ htmlInput: { step: 0.01, min: 0 } }} />
                    <TextField label="Expiry (months)" type="number" size="small" value={work?.rules.expiry_months ?? ''} onChange={(e) => setWork((w) => (w ? { ...w, rules: { ...w.rules, expiry_months: Number(e.target.value) } } : w))} />
                    <TextField label="Referral points" type="number" size="small" value={work?.rules.referral_bonus.points ?? ''} onChange={(e) => setWork((w) => (w ? { ...w, rules: { ...w.rules, referral_bonus: { ...w.rules.referral_bonus, points: Number(e.target.value) } } } : w))} />
                  </Box>
                )}
                <RuleTile icon="hourglass_top" title={`Points expiry — ${view.rules.expiry_months} months rolling`} subtitle="Customer notified 60 & 30 days before expiry" checked={view.rules.expiry_months > 0} onChange={editing ? (v) => setWork((w) => (w ? { ...w, rules: { ...w.rules, expiry_months: v ? 24 : 0 } } : w)) : undefined} />
                <RuleTile icon="group_add" title={`Referral bonus — ${view.rules.referral_bonus.points} pts`} subtitle="Awarded to the referrer after the referred customer's first paid service" checked={view.rules.referral_bonus.enabled} onChange={editing ? (v) => setWork((w) => (w ? { ...w, rules: { ...w.rules, referral_bonus: { ...w.rules.referral_bonus, enabled: v } } } : w)) : undefined} />
                <RuleTile icon="cake" title="Birthday bonus — 2× earn week" subtitle={view.rules.birthday_bonus.reason ? `Off — ${view.rules.birthday_bonus.reason.replace(' (ADM-042)', '').toLowerCase()} (ADM-042)` : `${view.rules.birthday_bonus.points} pts`} checked={view.rules.birthday_bonus.enabled} disabled />
              </Box>
              {editing && <TextField label="Change note" value={work?.change_note ?? ''} onChange={(e) => setWork((w) => (w ? { ...w, change_note: e.target.value } : w))} sx={{ mt: 2 }} fullWidth />}
            </SectionCard>

            <Paper sx={{ p: 3, bgcolor: tk.navy, color: '#FFFFFF', border: 'none', display: 'flex', flexDirection: 'column', gap: 1.5, minHeight: 320, '[data-mui-color-scheme="dark"] &': { bgcolor: tk.surfaceContainerHigh } }}>
              <Typography variant="h3" component="h2" sx={{ color: 'inherit' }}>Draft changes · v{nextVersion}</Typography>
              {draft ? (
                <>
                  <Box component="ul" sx={{ m: 0, pl: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 0.5, opacity: 0.9, fontSize: 15 }}>
                    {diffs.length ? diffs.map((d) => <li key={d}>{d}</li>) : <li>No differences from v{published.version}</li>}
                  </Box>
                  {draft.change_note && <Typography variant="body2" sx={{ opacity: 0.75 }}>“{draft.change_note}” · {draft.created_by ? `drafted by ${draft.created_by.replace('seed_', '')}` : ''} {fmtDateTime(draft.created_at)}</Typography>}
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, p: 1.5, borderRadius: '14px', bgcolor: 'rgba(255,255,255,0.08)', fontSize: 14 }}>
                    <MSymbol name="published_with_changes" size={22} style={{ color: '#8BD2FF' }} />
                    Publishing is versioned, audited and takes effect server-side within 60 s.
                  </Box>
                  <Box sx={{ flex: 1 }} />
                  <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.25 }}>
                    <Button variant="outlined" onClick={() => discard.mutate()} disabled={!canDraft || discard.isPending} sx={{ color: '#fff', borderColor: 'rgba(255,255,255,0.35)', '&:hover': { borderColor: '#fff', bgcolor: 'rgba(255,255,255,0.06)' } }}>Discard</Button>
                    <Button variant="contained" onClick={() => setConfirm(true)} disabled={!canPublish || diffs.length === 0} sx={{ bgcolor: '#8BD2FF', color: '#203060', '&:hover': { bgcolor: '#A8DEFF' }, '&.Mui-disabled': { bgcolor: 'rgba(139,210,255,0.3)', color: 'rgba(255,255,255,0.5)' } }}>
                      Publish v{draft.version}
                    </Button>
                  </Box>
                  {!canPublish && <Typography variant="caption" sx={{ opacity: 0.7 }}>Only admins can publish. Managers can prepare drafts.</Typography>}
                </>
              ) : (
                <>
                  <Typography sx={{ opacity: 0.85 }}>No draft in progress. v{published.version} has been live since {fmtDateTime(published.published_at)}.</Typography>
                  <Box sx={{ flex: 1 }} />
                  {canDraft && !editing && <Button variant="contained" onClick={startEdit} sx={{ bgcolor: '#8BD2FF', color: '#203060', '&:hover': { bgcolor: '#A8DEFF' } }}>Start draft v{nextVersion}</Button>}
                </>
              )}
            </Paper>
          </Box>
        </>
      )}

      <Dialog open={confirm} onClose={() => setConfirm(false)} aria-labelledby="publish-title">
        <DialogTitle id="publish-title">Publish loyalty config v{draft?.version}?</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>v{published?.version} will be archived. New bookings price with the new tiers within 60 seconds; existing ledger entries are never rewritten.</Typography>
          <Box component="ul" sx={{ pl: 2.5, m: 0 }}>{diffs.map((d) => <li key={d}><Typography variant="body2">{d}</Typography></li>)}</Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setConfirm(false)}>Back</Button>
          <Button variant="contained" color="secondary" onClick={() => publish.mutate()} disabled={publish.isPending} startIcon={<MSymbol name="publish" size={20} />}>Publish</Button>
        </DialogActions>
      </Dialog>

      <Drawer anchor="right" open={auditOpen} onClose={() => setAuditOpen(false)} slotProps={{ paper: { sx: { width: { xs: '100%', sm: 440 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
          <Typography variant="h3">Loyalty audit log</Typography>
          <IconButton aria-label="Close" onClick={() => setAuditOpen(false)}><MSymbol name="close" /></IconButton>
        </Box>
        {audit.isLoading && <LoadingRows rows={4} />}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          {(audit.data?.data ?? []).map((a) => (
            <Tile key={a.id} sx={{ alignItems: 'flex-start' }}>
              <MSymbol name={a.action.endsWith('publish') ? 'publish' : a.action.endsWith('discard') ? 'delete' : 'edit'} size={22} style={{ color: tk.primary }} />
              <Box>
                <Typography variant="h6">{a.action.replace('loyalty_config.', '').replace(/^\w/, (c) => c.toUpperCase())} · v{(a.after as { version?: number } | null)?.version ?? '?'}</Typography>
                <Typography variant="body2" color="text.secondary">{a.actor_name} ({a.actor_role}) · {fmtDateTime(a.created_at)}</Typography>
              </Box>
            </Tile>
          ))}
          {audit.data && audit.data.data.length === 0 && <Typography color="text.secondary">No entries.</Typography>}
        </Box>
        <Typography variant="caption" color="text.secondary" sx={{ mt: 2 }}>Full history: <Link href="/audit?entity_type=loyalty_config" style={{ color: tk.primary, fontWeight: 600 }}>Audit page</Link></Typography>
        <Chip label="ADM-025 · versioned + audited" size="small" sx={{ mt: 2, alignSelf: 'flex-start', bgcolor: tk.surfaceContainerHigh }} />
      </Drawer>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
