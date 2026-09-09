'use client';
import { styled } from '@mui/material/styles';
import Switch, { type SwitchProps } from '@mui/material/Switch';
import { tk } from '@/theme/tokens';

/** Material 3 switch (46×26 track, 22px thumb, primary when on). */
const M3Switch = styled((props: SwitchProps) => <Switch disableRipple {...props} />)(() => ({
  width: 52,
  height: 32,
  padding: 3,
  '& .MuiSwitch-switchBase': {
    padding: 5,
    '&.Mui-checked': {
      transform: 'translateX(20px)',
      color: '#fff',
      '& + .MuiSwitch-track': { backgroundColor: tk.primary, opacity: 1, border: 0 },
      '& .MuiSwitch-thumb': { backgroundColor: tk.onPrimary },
      '&.Mui-disabled + .MuiSwitch-track': { opacity: 0.4 },
    },
    '&.Mui-disabled .MuiSwitch-thumb': { opacity: 0.6 },
    '&.Mui-focusVisible .MuiSwitch-thumb': { outline: `3px solid ${tk.primary}`, outlineOffset: 2 },
  },
  '& .MuiSwitch-thumb': { boxSizing: 'border-box', width: 22, height: 22, backgroundColor: tk.onSurfaceVariant, boxShadow: 'none' },
  '& .MuiSwitch-track': { borderRadius: 999, backgroundColor: tk.surfaceContainerHigh, border: `2px solid ${tk.outline}`, opacity: 1, transition: 'background-color 200ms' },
}));

export default M3Switch;
