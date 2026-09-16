'use client';

import * as React from 'react';
import Autocomplete from '@mui/material/Autocomplete';
import Chip from '@mui/material/Chip';
import TextField from '@mui/material/TextField';
import { tk } from '@/theme/tokens';

/**
 * Skills recognised by auto-assignment (services/workflow.ts `skillsForCategory`):
 * car-wash work orders need `wash`, auto-body ones `paint` or `panel`. Anything else is a free tag.
 */
export const KNOWN_SKILLS: { code: string; label: string; hint: string }[] = [
  { code: 'wash', label: 'Wash', hint: 'Car-wash work orders' },
  { code: 'paint', label: 'Paint', hint: 'Auto-body (spray / polish)' },
  { code: 'panel', label: 'Panel', hint: 'Auto-body (dent / panel)' },
  { code: 'detail', label: 'Detail', hint: 'Interior & full detailing' },
  { code: 'engine', label: 'Engine', hint: 'Engine & chassis cleaning' },
];

const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, '_').slice(0, 32);

export function SkillsPicker({ value, onChange, size = 'small', helperText }: { value: string[]; onChange: (skills: string[]) => void; size?: 'small' | 'medium'; helperText?: string }) {
  return (
    <Autocomplete
      multiple
      freeSolo
      size={size}
      options={KNOWN_SKILLS.map((k) => k.code)}
      value={value}
      onChange={(_, v) => onChange(Array.from(new Set(v.map(norm).filter(Boolean))))}
      getOptionLabel={(o) => KNOWN_SKILLS.find((k) => k.code === o)?.label ?? o}
      renderOption={(props, option) => {
        const k = KNOWN_SKILLS.find((x) => x.code === option);
        const { key, ...rest } = props as typeof props & { key: string };
        return (
          <li key={key} {...rest} style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
            <span>{k?.label ?? option}</span>
            {k && <span style={{ color: tk.onSurfaceVariant, fontSize: 12 }}>{k.hint}</span>}
          </li>
        );
      }}
      renderValue={(selected, getTagProps) =>
        selected.map((option, index) => {
          const { key, ...tagProps } = getTagProps({ index });
          return <Chip key={key} label={KNOWN_SKILLS.find((k) => k.code === option)?.label ?? option} size="small" {...tagProps} sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }} />;
        })
      }
      renderInput={(params) => <TextField {...params} label="Skills" placeholder={value.length ? '' : 'wash, paint, panel…'} helperText={helperText ?? 'Auto-assign matches wash → car wash, paint / panel → auto body. Type to add your own.'} />}
    />
  );
}
