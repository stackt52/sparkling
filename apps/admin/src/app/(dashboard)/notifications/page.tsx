'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Tooltip from '@mui/material/Tooltip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Paper from '@mui/material/Paper';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip, { type Tone } from '@/components/ui/StatusChip';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { LiveChip } from '@/components/ui/Pills';
import { EmptyState, ErrorState } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useLive, useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { fmtDateTime, num, titleCase } from '@/lib/format';
import type { NotificationRow, NotifyChannel, NotifyStatus } from '@/lib/types';

const STATUSES: (NotifyStatus | 'all')[] = ['all', 'queued', 'sent', 'delivered', 'failed', 'suppressed'];
const CHANNELS: (NotifyChannel | 'all')[] = ['all', 'whatsapp', 'push', 'sms', 'email'];

const channelMeta: Record<NotifyChannel, { label: string; icon: string; tone: Tone }> = {
  whatsapp: { label: 'WhatsApp', icon: 'chat', tone: 'success' },
  push: { label: 'Push', icon: 'notifications', tone: 'primary' },
  sms: { label: 'SMS', icon: 'sms', tone: 'secondary' },
  email: { label: 'Email', icon: 'mail', tone: 'neutral' },
};

const statusTone: Record<NotifyStatus, Tone> = { queued: 'warning', sent: 'primary', delivered: 'success', failed: 'error', suppressed: 'neutral' };

function ChannelChip({ channel }: { channel: NotifyChannel }) {
  const m = channelMeta[channel];
  return <StatusChip tone={m.tone} label={m.label} icon={<MSymbol name={m.icon} filled size={16} style={{ color: 'inherit' }} />} sx={{ '& .MuiChip-icon': { color: 'inherit', ml: '6px' } }} />;
}

function SummaryTile({ icon, tone, value, label }: { icon: string; tone: 'primary' | 'success' | 'error' | 'warning'; value: number; label: string }) {
  return (
    <Paper sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 1.5, minHeight: 88 }}>
      <IconTile icon={icon} tone={tone} size={48} />
      <Box>
        <Typography sx={{ fontSize: 26, fontWeight: 700, lineHeight: 1.1, color: tone === 'error' ? tk.error : tk.onSurface }}>{num(value)}</Typography>
        <Typography variant="body2" color="text.secondary">{label}</Typography>
      </Box>
    </Paper>
  );
}

function ResendDialog({ row, onClose, onConfirm, busy }: { row: NotificationRow | null; onClose: () => void; onConfirm: () => void; busy: boolean }) {
  return (
    <Dialog open={Boolean(row)} onClose={busy ? undefined : onClose} aria-labelledby="resend-title" fullWidth maxWidth="xs">
      {row && (
        <>
          <DialogTitle id="resend-title">Resend {titleCase(row.template_key)}?</DialogTitle>
          <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
            <Typography variant="body2">
              To <b>{row.recipient_name ?? row.recipient_id}</b> via {channelMeta[row.channel].label}
              {row.channel === 'whatsapp' ? ' (Twilio)' : ''} · attempt {row.attempts + 1}.
            </Typography>
            <Paper sx={{ p: 1.5, bgcolor: tk.surfaceContainer, border: 'none', borderRadius: '14px' }}>
              <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>{row.body}</Typography>
            </Paper>
            {row.provider_error_code && (
              <Typography variant="caption" sx={{ color: tk.error }}>
                Last error {row.provider_error_code}: {row.error}
              </Typography>
            )}
            <Typography variant="caption" color="text.secondary">The resend is audited (notification.resend) and the customer receives the message again.</Typography>
          </DialogContent>
          <DialogActions sx={{ p: 2.5, pt: 0 }}>
            <Button onClick={onClose} disabled={busy}>Cancel</Button>
            <Button variant="contained" color="secondary" onClick={onConfirm} disabled={busy} startIcon={<MSymbol name="forward_to_inbox" size={18} />}>Resend</Button>
          </DialogActions>
        </>
      )}
    </Dialog>
  );
}

export default function NotificationsPage() {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const { updatedAt, mode } = useLive(['notifications']);
  const [status, setStatus] = React.useState<NotifyStatus | 'all'>('all');
  const [channel, setChannel] = React.useState<NotifyChannel | 'all'>('all');
  const [cursor, setCursor] = React.useState<string | null>(null);
  const [history, setHistory] = React.useState<(string | null)[]>([]);
  const [resend, setResend] = React.useState<NotificationRow | null>(null);
  const canResend = can(role, 'notification:resend');

  const q = useQuery({ queryKey: ['notifications', status, channel, cursor], queryFn: () => api.listNotifications({ status, channel, cursor, limit: 25 }) });
  const all = useQuery({ queryKey: ['notifications', 'summary'], queryFn: () => api.listNotifications({ limit: 500 }) });
  const m = useMutation({
    mutationFn: (id: string) => api.resendNotification(id),
    onSuccess: (n) => { toast.success(`${titleCase(n.template_key)} re-sent to ${n.recipient_name ?? n.recipient_id} (attempt ${n.attempts})`); setResend(null); void qc.invalidateQueries({ queryKey: ['notifications'] }); },
    onError: (e) => toast.error(e),
  });

  const rows = q.data?.data ?? [];
  const summary = all.data?.data ?? [];
  const failed = summary.filter((n) => n.status === 'failed').length;
  const delivered = summary.filter((n) => n.status === 'delivered').length;
  const whatsapp = summary.filter((n) => n.channel === 'whatsapp').length;

  const resetPaging = () => { setCursor(null); setHistory([]); };

  const columns: GridColDef<NotificationRow>[] = [
    { field: 'recipient_name', headerName: 'Recipient', flex: 1.2, minWidth: 170, renderCell: (p) => (
      <Box className="cell-stack">
        <Typography variant="body2" sx={{ fontWeight: 700 }} noWrap>{p.row.recipient_name ?? p.row.recipient_id}</Typography>
        <Typography variant="caption" color="text.secondary" className="mono" noWrap>{p.row.recipient_id}</Typography>
      </Box>
    ) },
    { field: 'channel', headerName: 'Channel', flex: 0.8, minWidth: 130, renderCell: (p) => <ChannelChip channel={p.row.channel} /> },
    { field: 'template_key', headerName: 'Template', flex: 1.1, minWidth: 160, renderCell: (p) => (
      <Tooltip title={p.row.body} enterDelay={400}>
        <Box className="cell-stack">
          <Typography variant="body2" className="mono" sx={{ fontWeight: 600 }} noWrap>{p.row.template_key}</Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ maxWidth: 260 }}>{p.row.title ?? p.row.body}</Typography>
        </Box>
      </Tooltip>
    ) },
    { field: 'status', headerName: 'Status', flex: 1, minWidth: 150, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
        <StatusChip tone={statusTone[p.row.status]} label={titleCase(p.row.status)} icon={p.row.status === 'delivered' ? <MSymbol name="done_all" size={16} style={{ color: 'inherit' }} /> : undefined} sx={{ '& .MuiChip-icon': { color: 'inherit', ml: '6px' } }} />
        {p.row.provider_status && p.row.provider_status !== p.row.status && (
          <Typography variant="caption" color="text.secondary" className="mono" title="Provider status (Twilio)" sx={{ lineHeight: 1.4 }}>{p.row.provider_status}</Typography>
        )}
      </Box>
    ) },
    { field: 'attempts', headerName: 'Attempts', flex: 0.5, minWidth: 90, align: 'center', headerAlign: 'center', renderCell: (p) => <span style={{ fontWeight: 600 }}>{p.row.attempts}</span> },
    { field: 'sent_at', headerName: 'Sent / delivered', flex: 1.1, minWidth: 170, renderCell: (p) => (
      <Box className="cell-stack">
        <Typography variant="body2" noWrap>{p.row.sent_at ? fmtDateTime(p.row.sent_at) : '—'}</Typography>
        <Typography variant="caption" noWrap sx={{ color: p.row.delivered_at ? tk.success : tk.onSurfaceVariant }}>{p.row.delivered_at ? `delivered ${fmtDateTime(p.row.delivered_at)}` : p.row.read_at ? `read ${fmtDateTime(p.row.read_at)}` : `created ${fmtDateTime(p.row.created_at)}`}</Typography>
      </Box>
    ) },
    { field: 'error', headerName: 'Error', flex: 1.4, minWidth: 200, renderCell: (p) => p.row.error ? (
      <Tooltip title={p.row.error}>
        <Typography variant="body2" noWrap sx={{ minWidth: 0, lineHeight: 1.4, color: p.row.status === 'failed' ? tk.error : tk.onSurfaceVariant }}>
          {p.row.provider_error_code && <span className="mono" style={{ fontWeight: 700 }}>{p.row.provider_error_code} · </span>}
          {p.row.error.split('—')[0].trim()}
        </Typography>
      </Tooltip>
    ) : <Typography variant="body2" color="text.secondary">—</Typography> },
    { field: 'actions', headerName: '', sortable: false, width: 120, align: 'right', renderCell: (p) => (
      canResend && p.row.status !== 'delivered' && p.row.status !== 'queued' ? (
        <Button size="small" variant={p.row.status === 'failed' ? 'contained' : 'outlined'} color={p.row.status === 'failed' ? 'secondary' : 'primary'} startIcon={<MSymbol name="forward_to_inbox" size={16} />} onClick={(e) => { e.stopPropagation(); setResend(p.row); }} aria-label={`Resend ${p.row.template_key} to ${p.row.recipient_name ?? p.row.recipient_id}`}>
          Resend
        </Button>
      ) : null
    ) },
  ];

  return (
    <>
      <PageHeader
        title="Messages"
        subtitle={<Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center', flexWrap: 'wrap' }}><span>Push &amp; WhatsApp notifications with provider delivery status (Twilio)</span><LiveChip updatedAt={updatedAt} mode={mode} /></Box>}
        actions={!canResend ? <StatusChip tone="neutral" label="Read-only" icon={<MSymbol name="visibility" size={16} style={{ color: 'inherit' }} />} sx={{ '& .MuiChip-icon': { color: 'inherit', ml: '6px' } }} /> : undefined}
      />
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr 1fr', md: 'repeat(4, 1fr)' }, gap: '14px' }}>
        <SummaryTile icon="forum" tone="primary" value={summary.length} label="Messages (all time)" />
        <SummaryTile icon="done_all" tone="success" value={delivered} label="Delivered" />
        <SummaryTile icon="sms_failed" tone="error" value={failed} label="Failed · needs resend" />
        <SummaryTile icon="chat" tone="warning" value={whatsapp} label="Via WhatsApp" />
      </Box>
      <SectionCard
        flush
        title="Delivery log"
        subtitle={q.data ? `Page of ${rows.length} · ${q.data.next_cursor ? 'more available' : 'end of log'}` : undefined}
        actions={
          <>
            <TextField select label="Status" value={status} onChange={(e) => { setStatus(e.target.value as NotifyStatus | 'all'); resetPaging(); }} size="small" sx={{ minWidth: 150, '& .MuiOutlinedInput-root': { bgcolor: 'transparent' } }}>
              {STATUSES.map((s) => <MenuItem key={s} value={s}>{s === 'all' ? 'All statuses' : titleCase(s)}</MenuItem>)}
            </TextField>
            <TextField select label="Channel" value={channel} onChange={(e) => { setChannel(e.target.value as NotifyChannel | 'all'); resetPaging(); }} size="small" sx={{ minWidth: 150, '& .MuiOutlinedInput-root': { bgcolor: 'transparent' } }}>
              {CHANNELS.map((c) => <MenuItem key={c} value={c}>{c === 'all' ? 'All channels' : channelMeta[c].label}</MenuItem>)}
            </TextField>
          </>
        }
      >
        <Box sx={{ px: 1.5, pb: 1 }}>
          {q.isError ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : !q.isLoading && rows.length === 0 ? (
            <EmptyState icon="forum" title="No messages match" description="Try another status or channel." />
          ) : (
            <AdminGrid<NotificationRow>
              rows={rows}
              columns={columns}
              loading={q.isLoading}
              rowHeight={64}
              getRowClassName={(p) => (p.row.status === 'failed' ? 'row-error' : p.row.status === 'queued' ? 'row-warning' : '')}
              sx={{ '& .cell-stack': { display: 'flex', flexDirection: 'column', justifyContent: 'center', minWidth: 0, maxWidth: '100%', lineHeight: 1.4, '& > *': { lineHeight: 1.4 } } }}
            />
          )}
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 1, p: 1.5, flexWrap: 'wrap' }}>
            <Typography variant="caption" color="text.secondary" sx={{ fontFamily: fonts.sans }}>
              Provider statuses come from Twilio status callbacks · <span className="mono">63016</span> = template required outside the 24 h session window.
            </Typography>
            <Box sx={{ display: 'flex', gap: 1 }}>
              <Button size="small" variant="outlined" disabled={history.length === 0} onClick={() => { const prev = [...history]; const c = prev.pop() ?? null; setHistory(prev); setCursor(c); }} startIcon={<MSymbol name="chevron_left" size={18} />}>Previous</Button>
              <Button size="small" variant="outlined" disabled={!q.data?.next_cursor} onClick={() => { setHistory([...history, cursor]); setCursor(q.data!.next_cursor); }} endIcon={<MSymbol name="chevron_right" size={18} />}>Next</Button>
            </Box>
          </Box>
        </Box>
      </SectionCard>
      <ResendDialog row={resend} onClose={() => setResend(null)} onConfirm={() => resend && m.mutate(resend.id)} busy={m.isPending} />
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
