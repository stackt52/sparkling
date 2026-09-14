'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Stepper from '@mui/material/Stepper';
import Step from '@mui/material/Step';
import StepButton from '@mui/material/StepButton';
import StepLabel from '@mui/material/StepLabel';
import Typography from '@mui/material/Typography';
import useMediaQuery from '@mui/material/useMediaQuery';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import { TonalPill } from '@/components/ui/Pills';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import CustomerStep from '@/components/bookings/walkin/CustomerStep';
import VehicleStep from '@/components/bookings/walkin/VehicleStep';
import ServiceStep from '@/components/bookings/walkin/ServiceStep';
import PaymentStep from '@/components/bookings/walkin/PaymentStep';
import SuccessPanel from '@/components/bookings/walkin/SuccessPanel';
import WalkInSummary from '@/components/bookings/walkin/WalkInSummary';
import { WALK_IN_STEPS, maxStep, useWalkInDraft } from '@/components/bookings/walkin/useWalkInDraft';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { ApiRequestError } from '@/lib/api';
import { tk } from '@/theme/tokens';
import { vehicleSizeOf } from '@/lib/types';

const HINTS = ['Find or register the customer', 'Choose the vehicle being washed', 'Outlet, service and time', 'Take payment and check in'];

export default function WalkInBookingPage() {
  const router = useRouter();
  const api = useApi();
  const { role } = useAuth();
  const toast = useToast();
  const compact = useMediaQuery('(max-width:899.95px)');
  const { draft, hydrated, patch, setCustomer, reset } = useWalkInDraft();
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const outletName = outlets.data?.find((o) => o.id === draft.outlet_id)?.name ?? null;
  // The customer's live membership drives the service step markers and the pricing preview (docs/MEMBERSHIPS.md).
  const customerId = draft.customer?.id ?? null;
  const membershipQ = useQuery({ queryKey: ['customer-membership', customerId], queryFn: () => api.customerMembership(customerId!), enabled: Boolean(customerId) && !draft.result });
  React.useEffect(() => {
    if (!membershipQ.isSuccess) return;
    if (JSON.stringify(membershipQ.data) !== JSON.stringify(draft.membership)) patch({ membership: membershipQ.data });
  }, [membershipQ.isSuccess, membershipQ.data, draft.membership, patch]);
  const allowed = can(role, 'booking:create');
  const reach = maxStep(draft);
  const step = draft.step;
  const canContinue = reach > step;
  const contentRef = React.useRef<HTMLDivElement>(null);

  const go = React.useCallback((s: 0 | 1 | 2 | 3) => {
    patch({ step: s });
    // Keep the step heading in view and hand focus to it for keyboard / screen-reader users.
    requestAnimationFrame(() => {
      document.getElementById('main')?.scrollTo({ top: 0 });
      contentRef.current?.querySelector<HTMLElement>('h2')?.focus({ preventScroll: true });
    });
  }, [patch]);

  if (!allowed) {
    return (
      <>
        <PageHeader title="Walk-in booking" />
        <SectionCard><ErrorState error={new ApiRequestError(403, { code: 'forbidden', message: 'Walk-in bookings can be created by admins, managers and supervisors.' })} /></SectionCard>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Walk-in booking"
        subtitle="Register or find the customer, pick the vehicle and service, then take payment at the counter."
        actions={<TonalPill icon="arrow_back" endIcon={null} onClick={() => router.push('/bookings')}>Bookings</TonalPill>}
      />

      {!hydrated ? (
        <SectionCard><LoadingRows rows={4} /></SectionCard>
      ) : draft.result ? (
        <SuccessPanel
          result={draft.result}
          onOpenBooking={() => { const id = draft.result!.booking.id; reset(); router.push(`/bookings?focus=${id}`); }}
          onNew={() => { reset(); toast.info('Started a new walk-in'); }}
          onDone={() => { reset(); router.push('/bookings'); }}
        />
      ) : (
        <>
          <SectionCard sx={{ py: 2 }}>
            <Stepper nonLinear activeStep={step} orientation={compact ? 'vertical' : 'horizontal'} sx={{ '& .MuiStepLabel-label': { fontWeight: 600 }, '& .MuiStepIcon-root.Mui-active, & .MuiStepIcon-root.Mui-completed': { color: tk.primary } }}>
              {WALK_IN_STEPS.map((label, i) => (
                <Step key={label} completed={i < step && i < reach} disabled={i > reach}>
                  <StepButton onClick={() => go(i as 0 | 1 | 2 | 3)} optional={!compact && <Typography variant="caption" color="text.secondary">{HINTS[i]}</Typography>}>
                    <StepLabel>{label}</StepLabel>
                  </StepButton>
                </Step>
              ))}
            </Stepper>
          </SectionCard>

          <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: 'minmax(0, 1fr) 320px' }, gap: '14px', alignItems: 'start' }}>
            <SectionCard component="section">
              <Box ref={contentRef}>
                <Typography variant="h2" component="h2" tabIndex={-1} sx={{ outline: 'none', mb: 0.5 }}>Step {step + 1} of 4 · {WALK_IN_STEPS[step]}</Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 2.5 }}>{HINTS[step]}</Typography>

                {step === 0 && <CustomerStep selected={draft.customer} onSelect={(c) => { setCustomer(c); }} onError={toast.error} />}
                {step === 1 && draft.customer && (
                  <VehicleStep
                    customer={draft.customer}
                    selected={draft.vehicle}
                    onSelect={(v) => patch((d) => ({ vehicle: v, vehicle_size: vehicleSizeOf(v), ...(d.vehicle && d.vehicle.id !== v.id ? { service: null, addons: [], slot_start: null } : {}) }))}
                    onCustomerUpdated={(c) => patch({ customer: c })}
                    onError={(e) => (e instanceof Error && !(e instanceof ApiRequestError) ? toast.info(e.message) : toast.error(e))}
                    size={draft.vehicle_size}
                    onSizeChange={(s) => patch({ vehicle_size: s })}
                  />
                )}
                {step === 2 && <ServiceStep draft={draft} patch={patch} onToast={(kind, message) => (kind === 'success' ? toast.success(String(message)) : kind === 'info' ? toast.info(String(message)) : toast.error(message))} />}
                {step === 3 && (
                  <PaymentStep
                    draft={draft}
                    patch={patch}
                    onSuccess={(r) => { patch({ result: r }); toast.success(`${r.booking.ref} confirmed${r.payment?.receipt_no ? ` · ${r.payment.receipt_no}` : ''}`); }}
                    onConflict={(message) => { toast.error(new Error(`${message}. Pick a slot instead.`)); patch({ step: 2, book_now: false, slot_start: null }); }}
                    onError={toast.error}
                  />
                )}

                {step < 3 && (
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 1.5, mt: 3, pt: 2.5, borderTop: `1px solid ${tk.outlineVariant}`, flexWrap: 'wrap' }}>
                    <Button variant="text" disabled={step === 0} onClick={() => go((step - 1) as 0 | 1 | 2)} startIcon={<MSymbol name="arrow_back" size={20} />}>Back</Button>
                    <Button variant="contained" color="secondary" disabled={!canContinue} onClick={() => go((step + 1) as 1 | 2 | 3)} endIcon={<MSymbol name="arrow_forward" size={20} />} sx={{ px: 3 }}>
                      {step === 0 ? 'Choose vehicle' : step === 1 ? 'Choose service' : 'Review & confirm'}
                    </Button>
                  </Box>
                )}
                {step === 3 && (
                  <Box sx={{ mt: 2.5 }}>
                    <Button variant="text" onClick={() => go(2)} startIcon={<MSymbol name="arrow_back" size={20} />} disabled={Boolean(draft.created)}>Back</Button>
                  </Box>
                )}
              </Box>
            </SectionCard>
            <WalkInSummary draft={draft} outletName={outletName} />
          </Box>
        </>
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
