'use client';
import * as React from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import Link from 'next/link';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import DetailDrawer from '@/components/ui/DetailDrawer';
import SectionCard from '@/components/ui/SectionCard';
import Tile from '@/components/ui/Tile';
import M3Switch from '@/components/ui/M3Switch';
import StatusChip from '@/components/ui/StatusChip';
import TierChip from '@/components/ui/TierChip';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill, TonalPill } from '@/components/ui/Pills';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import PlanCard from '@/components/memberships/PlanCard';
import PlanEditorDrawer from '@/components/memberships/PlanEditorDrawer';
import MembersGrid from '@/components/memberships/MembersGrid';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { fmtDateTime, num, rands } from '@/lib/format';
import type { LoyaltyConfig, LoyaltyRules, LoyaltyTierConfig, MembershipPlan } from '@/lib/types';

function earnRate(t: LoyaltyTierConfig, rules: LoyaltyRules) {
  const perR10 = rules.points_per_rand * 10 * t.earn_multiplier;
  return `${Number(perR10.toFixed(2))} pt${perR10 === 1 ? '' : 's'} / R10`;
}

/** One row per tier: "Tier = plan" copy (no points thresholds, no tier discount) plus the earn multiplier. */
function TierRow({ t, rules, plan, editable, onChange }: { t: LoyaltyTierConfig; rules: LoyaltyRules; plan: MembershipPlan | undefined; editable?: boolean; onChange?: (patch: Partial<LoyaltyTierConfig>) => void }) {
  return (
    <Tile sx={{ minHeight: 60, gap: 1.5 }}>
      <TierChip tier={t.tier} sx={{ minWidth: 88 }} />
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography variant="body1" sx={{ fontWeight: 600 }}>
          {t.tier === 'silver' ? 'Tier = no plan · free, earns points only' : plan ? `Tier = ${plan.name} plan · ${rands(plan.monthly_fee_cents)} / month` : `Tier = ${t.name} plan`}
        </Typography>
        <Typography variant="caption" color="text.secondary">
          {t.tier === 'silver' ? 'Everyone without a live membership' : plan ? `${num(plan.member_count ?? 0)} members · discounts and washes come from the plan, not the tier` : 'Set by the membership plan'} · booking discount 0 %
        </Typography>
      </Box>
      {editable ? (
        <TextField type="number" size="small" label="Earn ×" value={t.earn_multiplier} onChange={(e) => onChange?.({ earn_multiplier: Number(e.target.value) })} slotProps={{ htmlInput: { step: 0.05, min: 0, 'aria-label': `${t.name} earn multiplier` } }} sx={{ width: 110, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} />
      ) : (
        <Typography sx={{ fontSize: 15, fontWeight: 700, whiteSpace: 'nowrap' }}>{earnRate(t, rules)}</Typography>
      )}
    </Tile>
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
    if (!p) { out.push(`${d.name} tier added`); continue; }
    if (p.earn_multiplier !== d.earn_multiplier) out.push(`${d.name} earn rate ${Number((published.rules.points_per_rand * 10 * p.earn_multiplier).toFixed(2))} → ${Number((draft.rules.points_per_rand * 10 * d.earn_multiplier).toFixed(2))} pts/R10`);
  }
  if (published.rules.points_per_rand !== draft.rules.points_per_rand) out.push(`Base earn ${published.rules.points_per_rand} → ${draft.rules.points_per_rand} pts per R1`);
  if (published.rules.expiry_months !== draft.rules.expiry_months) out.push(`Points expiry ${published.rules.expiry_months} → ${draft.rules.expiry_months} months`);
  if (published.rules.referral_bonus.points !== draft.rules.referral_bonus.points || published.rules.referral_bonus.enabled !== draft.rules.referral_bonus.enabled) out.push(`Referral bonus ${published.rules.referral_bonus.enabled ? published.rules.referral_bonus.points : 'off'} → ${draft.rules.referral_bonus.enabled ? draft.rules.referral_bonus.points : 'off'} pts`);
  if (published.rules.birthday_bonus.enabled !== draft.rules.birthday_bonus.enabled) out.push(`Birthday bonus ${published.rules.birthday_bonus.enabled ? 'on' : 'off'} → ${draft.rules.birthday_bonus.enabled ? 'on' : 'off'}`);
  return out;
}

export default function MembershipPlansPage() {
  const api = useApi();
  const router = useRouter();
  const params = useSearchParams();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [tab, setTab] = React.useState(params.get('tab') === 'members' ? 1 : 0);
  const plansQ = useQuery({ queryKey: ['membership-plans'], queryFn: () => api.membershipPlans() });
  const q = useQuery({ queryKey: ['loyalty-config'], queryFn: () => api.loyaltyConfig() });
  const [editingPlan, setEditingPlan] = React.useState<MembershipPlan | null>(null);
  const [editing, setEditing] = React.useState(false);
  const [work, setWork] = React.useState<{ tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string } | null>(null);
  const [confirm, setConfirm] = React.useState(false);
  const [auditOpen, setAuditOpen] = React.useState(false);
  const audit = useQuery({ queryKey: ['audit', 'memberships'], queryFn: () => api.listAudit({ limit: 40 }), enabled: auditOpen, select: (page) => ({ ...page, data: page.data.filter((a) => ['loyalty_config', 'membership_plan', 'membership', 'membership_invoice'].includes(a.entity_type)) }) });

  const published = q.data?.published;
  const draft = q.data?.draft ?? null;
  const canDraft = can(role, 'loyalty:draft');
  const canPublish = can(role, 'loyalty:publish');
  const canManage = can(role, 'memberships:manage');
  const plans = plansQ.data ?? [];
  const members = plans.reduce((s, p) => s + (p.member_count ?? 0), 0);
  const mrr = plans.reduce((s, p) => s + (p.mrr_cents ?? 0), 0);

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
  const onToast = (kind: 'success' | 'error' | 'info', message: string | unknown) => (kind === 'success' ? toast.success(String(message)) : kind === 'info' ? toast.info(String(message)) : toast.error(message));

  return (
    <>
      <PageHeader
        title="Membership plans"
        subtitle={`Tier = plan · ${num(members)} live members · MRR ${rands(mrr)} · points earn rules stay versioned and audited`}
        actions={
          <>
            {published && <StatusChip tone="success" icon={<MSymbol name="verified" filled size={18} style={{ color: 'inherit' }} />} label={`Earn rules · v${published.version}`} sx={{ height: 44, px: 1, fontSize: 15, '& .MuiChip-icon': { color: 'inherit' } }} />}
            <TonalPill icon="history" endIcon={null} onClick={() => setAuditOpen(true)}>Audit log</TonalPill>
            {tab === 0 && canDraft && !editing && <NavyPill icon="edit" onClick={startEdit}>{draft ? 'Edit earn rules draft' : 'New earn rules draft'}</NavyPill>}
            {tab === 0 && editing && (
              <>
                <TonalPill endIcon={null} onClick={() => setEditing(false)}>Cancel</TonalPill>
                <NavyPill icon="save" onClick={() => save.mutate()} disabled={save.isPending}>Save draft v{nextVersion}</NavyPill>
              </>
            )}
          </>
        }
      />
      <Tabs value={tab} onChange={(_e, v) => setTab(v)} aria-label="Membership sections" sx={{ mb: -0.5 }}>
        <Tab label={`Plans · ${plans.length}`} />
        <Tab label={`Members · ${num(members)}`} />
      </Tabs>

      {tab === 0 && (
        <>
          {plansQ.isLoading && <LoadingRows rows={1} height={420} />}
          {plansQ.error && <ErrorState error={plansQ.error} onRetry={() => plansQ.refetch()} />}
          {plansQ.isSuccess && (
            <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(3, 1fr)' }, gap: '14px', alignItems: 'stretch' }}>
              {plans.map((p) => <PlanCard key={p.id} plan={p} canEdit={canManage} onEdit={() => setEditingPlan(p)} />)}
            </Box>
          )}

          {q.isLoading && <LoadingRows rows={2} height={160} />}
          {q.error && <ErrorState error={q.error} onRetry={() => q.refetch()} />}
          {view && published && (
            <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.5fr 1fr' }, gap: '14px', alignItems: 'start' }}>
              <SectionCard title="Earning & expiry rules" subtitle="Tiers follow the plan — no points thresholds and a 0 % tier discount; every discount comes from the plan card above">
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
                  {view.tiers.map((t) => (
                    <TierRow key={t.tier} t={t} rules={view.rules} plan={plans.find((p) => p.tier === t.tier)} editable={editing} onChange={(patch) => setWork((w) => (w ? { ...w, tiers: w.tiers.map((x) => (x.tier === t.tier ? { ...x, ...patch } : x)) } : w))} />
                  ))}
                  <RuleTile icon="payments" title={`Base earn — completed paid services only · ${view.rules.points_per_rand} pt per R1`} subtitle="Awarded once per payment via idempotent ledger entry (CUS-064) · member washes earn on the amount actually paid" checked={view.rules.idempotent_award} onChange={editing ? (v) => setWork((w) => (w ? { ...w, rules: { ...w.rules, idempotent_award: v } } : w)) : undefined} />
                  {editing && (
                    <Box sx={{ display: 'flex', gap: 1.5, px: 1, flexWrap: 'wrap' }}>
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
                <Typography variant="h3" component="h2" sx={{ color: 'inherit' }}>Earn rules draft · v{nextVersion}</Typography>
                {draft ? (
                  <>
                    <Box component="ul" sx={{ m: 0, pl: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 0.5, opacity: 0.9, fontSize: 15 }}>
                      {diffs.length ? diffs.map((d) => <li key={d}>{d}</li>) : <li>No differences from v{published.version}</li>}
                    </Box>
                    {draft.change_note && <Typography variant="body2" sx={{ opacity: 0.75 }}>“{draft.change_note}” · {draft.created_by ? `drafted by ${draft.created_by.replace('seed_', '')}` : ''} {fmtDateTime(draft.created_at)}</Typography>}
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, p: 1.5, borderRadius: '14px', bgcolor: 'rgba(255,255,255,0.08)', fontSize: 14 }}>
                      <MSymbol name="published_with_changes" size={22} style={{ color: '#8BD2FF' }} />
                      Publishing is versioned, audited and takes effect server-side within 60 s. Plan fees and entitlements are saved directly on the plan.
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
          )}
        </>
      )}

      {tab === 1 && <MembersGrid plans={plans} canManage={canManage} onToast={onToast} onOpenCustomer={(id) => router.push(`/customers?focus=${id}`)} />}

      <PlanEditorDrawer plan={editingPlan} onClose={() => setEditingPlan(null)} onSaved={(p) => { setEditingPlan(null); toast.success(`${p.name} plan saved · ${rands(p.monthly_fee_cents)} / month from the next invoice`); }} onError={(e) => toast.error(e)} />

      <Dialog open={confirm} onClose={() => setConfirm(false)} aria-labelledby="publish-title">
        <DialogTitle id="publish-title">Publish earn rules v{draft?.version}?</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>v{published?.version} will be archived. New bookings earn with the new rules within 60 seconds; existing ledger entries are never rewritten.</Typography>
          <Box component="ul" sx={{ pl: 2.5, m: 0 }}>{diffs.map((d) => <li key={d}><Typography variant="body2">{d}</Typography></li>)}</Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setConfirm(false)}>Back</Button>
          <Button variant="contained" color="secondary" onClick={() => publish.mutate()} disabled={publish.isPending} startIcon={<MSymbol name="publish" size={20} />}>Publish</Button>
        </DialogActions>
      </Dialog>

      <DetailDrawer
        open={auditOpen}
        onClose={() => setAuditOpen(false)}
        width={{ xs: '100%', sm: 460 }}
        label="Memberships"
        titleId="loyalty-audit-title"
        title={<Typography variant="h3" component="h3">Audit log</Typography>}
        subtitle="Plan edits, enrolments, renewals and earn-rule versions"
        footer={
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 1.5 }}>
            <Typography variant="caption" color="text.secondary">Full history: <Link href="/audit?entity_type=membership" style={{ color: tk.primary, fontWeight: 600 }}>Audit page</Link></Typography>
            <Chip label="ADM-025 · versioned + audited" size="small" sx={{ bgcolor: tk.surfaceContainerHigh }} />
          </Box>
        }
      >
        {audit.isLoading && <LoadingRows rows={4} />}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          {(audit.data?.data ?? []).map((a) => (
            <Tile key={a.id} sx={{ alignItems: 'flex-start' }}>
              <MSymbol name={a.action.endsWith('publish') ? 'publish' : a.action.endsWith('discard') ? 'delete' : a.action.startsWith('membership.') ? 'workspace_premium' : 'edit'} size={22} style={{ color: tk.primary }} />
              <Box sx={{ minWidth: 0 }}>
                <Typography variant="h6">{a.action.replace(/^\w/, (c) => c.toUpperCase()).replace(/[._]/g, ' ')}{a.entity_type === 'loyalty_config' ? ` · v${(a.after as { version?: number } | null)?.version ?? '?'}` : ''}</Typography>
                <Typography variant="body2" color="text.secondary">{a.actor_name} ({a.actor_role}) · {fmtDateTime(a.created_at)}</Typography>
              </Box>
            </Tile>
          ))}
          {audit.data && audit.data.data.length === 0 && <Typography color="text.secondary">No entries.</Typography>}
        </Box>
      </DetailDrawer>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
