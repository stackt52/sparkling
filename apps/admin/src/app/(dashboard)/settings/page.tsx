'use client';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useColorScheme } from '@mui/material/styles';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import Tile from '@/components/ui/Tile';
import M3Switch from '@/components/ui/M3Switch';
import StatusChip from '@/components/ui/StatusChip';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { env } from '@/lib/env';
import { tk } from '@/theme/tokens';
import { fmtDateTime } from '@/lib/format';
import type { FeatureFlag, IntegrationStatus } from '@/lib/types';

const statusTone = { connected: 'success', sandbox: 'warning', disabled: 'neutral', demo: 'primary', error: 'error' } as const;

/** "MGa1b2…7660" — Messaging Service SIDs are never shown in full. */
function maskSid(sid: string | null | undefined): string {
  if (!sid) return 'not set';
  return sid.length > 8 ? `${sid.slice(0, 2)}…${sid.slice(-4)}` : sid;
}

/** WhatsApp (Twilio) card: provider · Messaging Service · configured, plus the `whatsapp_enabled` flag switch. */
function WhatsAppCard({ integration, flag, manage, pending, onToggle }: { integration: IntegrationStatus; flag: FeatureFlag | undefined; manage: boolean; pending: boolean; onToggle: (enabled: boolean) => void }) {
  const configured = integration.configured ?? integration.status === 'connected';
  const enabled = flag?.enabled ?? integration.enabled ?? false;
  const provider = integration.provider === 'twilio' ? 'Twilio' : (integration.provider ?? 'Provider');
  return (
    <Paper data-testid="integration-whatsapp" sx={{ p: 2, display: 'flex', gap: 1.5, alignItems: 'flex-start', bgcolor: tk.surfaceContainer, border: 'none', borderRadius: '18px', gridColumn: { md: '1 / -1' } }}>
      <IconTile icon={integration.icon} tone={!configured ? 'error' : enabled ? 'success' : 'neutral'} size={44} />
      <Box sx={{ minWidth: 0, flex: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
          <Typography variant="h6">{integration.name}</Typography>
          <StatusChip tone={!configured ? 'error' : enabled ? 'success' : 'neutral'} label={!configured ? 'not configured' : enabled ? 'enabled' : 'paused'} sx={{ height: 22, fontSize: 11 }} />
        </Box>
        <Typography variant="body2" sx={{ mt: 0.25 }}>
          {provider} · Messaging Service <span className="mono">{maskSid(integration.messaging_service)}</span> · {configured ? 'configured' : 'not configured'}
        </Typography>
        <Typography variant="body2" color="text.secondary">{integration.detail}</Typography>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 1.25, flexWrap: 'wrap' }}>
          <M3Switch checked={enabled} disabled={!manage || pending || !flag} onChange={(e) => onToggle(e.target.checked)} slotProps={{ input: { 'aria-label': 'whatsapp_enabled' } }} />
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="subtitle2" className="mono">whatsapp_enabled</Typography>
            <Typography variant="caption" color="text.secondary">
              {enabled ? 'Collection OTPs and booking updates go out by WhatsApp (push stays on).' : 'WhatsApp sending is paused — customers still get push notifications.'}
              {flag ? ` Updated ${fmtDateTime(flag.updated_at)}.` : ''}
              {!manage ? ' Admin-only.' : ''}
            </Typography>
          </Box>
        </Box>
      </Box>
    </Paper>
  );
}

export default function SettingsPage() {
  const api = useApi();
  const { role, isDemo } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const { mode, setMode } = useColorScheme();
  const flags = useQuery({ queryKey: ['flags'], queryFn: () => api.listFlags() });
  const integrations = useQuery({ queryKey: ['integrations'], queryFn: () => api.integrations() });
  const update = useMutation({
    mutationFn: (v: { key: string; enabled: boolean }) => api.updateFlag(v.key, v.enabled),
    onSuccess: (f) => { toast.success(`${f.key} ${f.enabled ? 'enabled' : 'disabled'} (audited)`); void qc.invalidateQueries({ queryKey: ['flags'] }); void qc.invalidateQueries({ queryKey: ['integrations'] }); },
    onError: (e) => toast.error(e),
  });
  const manage = can(role, 'flags:manage');
  return (
    <>
      <PageHeader title="Configuration" subtitle="Feature flags, integrations and appearance" />
      <ConfigTabs />
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1fr 1fr' }, gap: '14px', alignItems: 'start' }}>
        <SectionCard title="Feature flags" subtitle={manage ? 'Changes take effect immediately and are audited (NFR-013)' : 'Read-only — only admins can change flags'}>
          {flags.isLoading && <LoadingRows rows={4} height={64} />}
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
            {(flags.data ?? []).map((f) => (
              <Tile key={f.key} sx={{ minHeight: 68 }}>
                <MSymbol name={f.enabled ? 'toggle_on' : 'toggle_off'} filled size={26} style={{ color: f.enabled ? tk.primary : tk.onSurfaceVariant }} />
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography variant="h6" className="mono">{f.key}</Typography>
                  <Typography variant="body2" color="text.secondary">{f.description} · updated {fmtDateTime(f.updated_at)}</Typography>
                </Box>
                <M3Switch checked={f.enabled} disabled={!manage || update.isPending} onChange={(e) => update.mutate({ key: f.key, enabled: e.target.checked })} slotProps={{ input: { 'aria-label': f.key } }} />
              </Tile>
            ))}
          </Box>
        </SectionCard>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
          <SectionCard title="Integrations">
            {integrations.isLoading && <LoadingRows rows={4} height={72} />}
            <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }, gap: 1.25 }}>
              {(integrations.data ?? []).map((i) => i.key === 'whatsapp' ? (
                <WhatsAppCard
                  key={i.key}
                  integration={i}
                  flag={flags.data?.find((f) => f.key === 'whatsapp_enabled')}
                  manage={manage}
                  pending={update.isPending}
                  onToggle={(enabled) => update.mutate({ key: 'whatsapp_enabled', enabled })}
                />
              ) : (
                <Paper key={i.key} sx={{ p: 2, display: 'flex', gap: 1.5, alignItems: 'flex-start', bgcolor: tk.surfaceContainer, border: 'none', borderRadius: '18px' }}>
                  <IconTile icon={i.icon} tone={i.status === 'connected' ? 'success' : i.status === 'error' ? 'error' : i.status === 'sandbox' ? 'warning' : 'primary'} size={44} />
                  <Box sx={{ minWidth: 0 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                      <Typography variant="h6">{i.name}</Typography>
                      <StatusChip tone={statusTone[i.status]} label={i.status} sx={{ height: 22, fontSize: 11 }} />
                    </Box>
                    <Typography variant="body2" color="text.secondary">{i.detail}</Typography>
                  </Box>
                </Paper>
              ))}
            </Box>
            <Typography variant="caption" color="text.secondary" sx={{ mt: 1.5 }}>
              Mode: <b>{isDemo ? 'demo (in-memory)' : 'live'}</b> · API base <span className="mono">{env.apiBaseUrl || 'not set'}</span> · Supabase <span className="mono">{env.supabaseUrl}</span>
            </Typography>
          </SectionCard>
          <SectionCard title="Appearance">
            <Box sx={{ display: 'flex', gap: 1 }}>
              {(['light', 'dark', 'system'] as const).map((m) => (
                <Tile key={m} role="radio" aria-checked={mode === m} tabIndex={0} interactive onClick={() => setMode(m)} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setMode(m); } }} tone={mode === m ? 'primary' : 'default'} sx={{ flex: 1, justifyContent: 'center', minHeight: 48 }}>
                  <MSymbol name={m === 'light' ? 'light_mode' : m === 'dark' ? 'dark_mode' : 'contrast'} filled={mode === m} size={20} />
                  <Typography variant="subtitle2" sx={{ textTransform: 'capitalize' }}>{m}</Typography>
                </Tile>
              ))}
            </Box>
            <Typography variant="caption" color="text.secondary" sx={{ mt: 1 }}>Persisted in this browser · follows prefers-color-scheme by default · non-essential motion is disabled when prefers-reduced-motion is set (UX-004).</Typography>
          </SectionCard>
        </Box>
      </Box>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
