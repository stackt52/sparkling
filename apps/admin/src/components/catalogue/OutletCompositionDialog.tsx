'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Radio from '@mui/material/Radio';
import RadioGroup from '@mui/material/RadioGroup';
import FormControlLabel from '@mui/material/FormControlLabel';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import ComponentListEditor, { makeCycleFor } from './ComponentListEditor';
import { tk } from '@/theme/tokens';
import type { OutletServiceOffer, Service, ServiceComponent } from '@/lib/types';

/**
 * Per-outlet "Includes" override: keep the global default set or define a custom set limited to
 * services available at this outlet. Saves via `PUT …/services/:id` with `components: null | []`.
 */
interface Props {
  open: boolean;
  offer: OutletServiceOffer | null;
  /** All offers at this outlet (custom sets may only use available ones). */
  offers: OutletServiceOffer[];
  services: Service[];
  saving?: boolean;
  onClose: () => void;
  onSave: (components: ServiceComponent[] | null) => void;
}

export default function OutletCompositionDialog(props: Props) {
  // Remount the body per opened offer so its state starts from that offer's current composition.
  const [session, setSession] = React.useState(0);
  const [wasOpen, setWasOpen] = React.useState(props.open);
  if (props.open !== wasOpen) {
    setWasOpen(props.open);
    if (props.open) setSession((n) => n + 1);
  }
  return <CompositionDialogBody key={`${session}:${props.offer?.service_id ?? ''}`} {...props} />;
}

function CompositionDialogBody({ open, offer, offers, services, saving, onClose, onSave }: Props) {
  const global = React.useMemo(() => services.find((s) => s.id === offer?.service_id)?.components ?? [], [services, offer]);
  const [mode, setMode] = React.useState<'global' | 'custom'>(() => (offer?.components_source === 'outlet' ? 'custom' : 'global'));
  const [custom, setCustom] = React.useState<ServiceComponent[]>(() => (offer ? offer.includes.map((c, i) => ({ child_service_id: c.service_id, quantity: c.quantity, sort_order: (i + 1) * 10 })) : []));

  const options = React.useMemo(() => offers.filter((o) => o.is_available && o.service_id !== offer?.service_id && o.category === offer?.category).map((o) => ({ id: o.service_id, code: o.code, name: o.name, hint: o.service_name !== o.name ? o.service_name : o.group_name })), [offers, offer]);
  const edges = React.useMemo(() => new Map(offers.map((o) => [o.service_id, o.includes.map((c) => c.service_id)])), [offers]);
  const codeOf = React.useCallback((id: string) => offers.find((o) => o.service_id === id)?.code ?? services.find((s) => s.id === id)?.code ?? id, [offers, services]);
  const cycleFor = React.useMemo(() => makeCycleFor(offer?.service_id ?? '', edges, codeOf), [offer, edges, codeOf]);
  const nameOf = (id: string) => offers.find((o) => o.service_id === id)?.name ?? services.find((s) => s.id === id)?.name ?? id;
  const hasCycle = mode === 'custom' && custom.some((c) => cycleFor(c.child_service_id));

  return (
    <Dialog open={open} onClose={() => !saving && onClose()} fullWidth maxWidth="sm" aria-labelledby="composition-title">
      <DialogTitle id="composition-title">
        <Typography variant="overline" color="text.secondary" component="div">Composition at this outlet</Typography>
        <Typography variant="h3" component="span">{offer?.name}</Typography>
      </DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <RadioGroup value={mode} onChange={(e) => setMode(e.target.value as 'global' | 'custom')}>
          <Tile sx={{ alignItems: 'flex-start', mb: 1, bgcolor: mode === 'global' ? tk.primaryContainer : tk.surfaceContainer }}>
            <FormControlLabel value="global" control={<Radio />} sx={{ m: 0, alignItems: 'flex-start', flex: 1 }} label={(
              <Box>
                <Typography variant="h6" component="p">Use the global set</Typography>
                <Typography variant="body2" color="text.secondary">Follows the service definition — changes made in Services apply here automatically.</Typography>
                <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mt: 1 }}>
                  {global.length ? [...global].sort((a, b) => a.sort_order - b.sort_order).map((c) => <Chip key={c.child_service_id} size="small" label={`${nameOf(c.child_service_id)}${c.quantity > 1 ? ` ×${c.quantity}` : ''}`} sx={{ bgcolor: tk.surfaceCard }} />) : <Typography variant="caption" color="text.secondary">Stand-alone service (no components)</Typography>}
                </Box>
              </Box>
            )} />
          </Tile>
          <Tile sx={{ alignItems: 'flex-start', bgcolor: mode === 'custom' ? tk.primaryContainer : tk.surfaceContainer }}>
            <FormControlLabel value="custom" control={<Radio />} sx={{ m: 0, alignItems: 'flex-start', flex: 1 }} label={(
              <Box>
                <Typography variant="h6" component="p">Custom for this outlet</Typography>
                <Typography variant="body2" color="text.secondary">Only services available at this outlet can be included.</Typography>
              </Box>
            )} />
          </Tile>
        </RadioGroup>
        {mode === 'custom' && (
          <ComponentListEditor value={custom} onChange={setCustom} options={options} cycleFor={cycleFor} label="Includes at this outlet" emptyHint="Pick the services this bundle includes here." />
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose} disabled={saving}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={saving || hasCycle} onClick={() => onSave(mode === 'global' ? null : custom)} startIcon={saving ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="save" size={20} />}>
          {mode === 'global' ? 'Use global set' : `Save custom set (${custom.length})`}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
