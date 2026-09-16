'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import TextField from '@mui/material/TextField';
import Autocomplete, { type AutocompleteRenderInputParams, createFilterOptions } from '@mui/material/Autocomplete';
import InputAdornment from '@mui/material/InputAdornment';
import Typography from '@mui/material/Typography';
import type { SxProps, Theme } from '@mui/material/styles';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import MSymbol from '@/components/MSymbol';
import { COUNTRIES, DEFAULT_COUNTRY, type Country } from '@/lib/countries';
import { formatNational, splitPhone } from '@/lib/phone';
import { useStorageValue, writeStorage } from '@/lib/hooks';
import { fonts, tk } from '@/theme/tokens';

const STORAGE_KEY = 'sparkling.phone.country';

export interface PhoneFieldMeta {
  /** True when the number is a valid number for the selected country (any type — mobile or landline). */
  valid: boolean;
  /** ISO 3166-1 alpha-2 of the picker. */
  country: string;
  /** Digits typed in the national box (as typed, may carry a trunk "0"). */
  national: string;
}

export interface PhoneFieldProps {
  /** E.164 (`+27821234567`) or `''`. While the number is incomplete the field reports the E.164 candidate with `meta.valid === false`. */
  value: string;
  onChange: (e164: string, meta: PhoneFieldMeta) => void;
  label?: string;
  required?: boolean;
  helperText?: React.ReactNode;
  size?: 'small' | 'medium';
  disabled?: boolean;
  autoFocus?: boolean;
  /** Force the error state (e.g. after a 400 from the API). */
  error?: boolean;
  /** `mobile` (default) words the error as "mobile number"; `any` (outlet landlines) says "phone number". */
  kind?: 'mobile' | 'any';
  /** Picker default when `value` is empty and nothing has been remembered yet. */
  defaultCountry?: string;
  placeholder?: string;
  id?: string;
  name?: string;
  sx?: SxProps<Theme>;
}

const byIso = (iso: string): Country | undefined => COUNTRIES.find((c) => c.iso === iso);
const fallbackCountry = byIso(DEFAULT_COUNTRY) ?? COUNTRIES[0];


const defaultFilter = createFilterOptions<Country>({ stringify: (o) => `${o.name} ${o.iso} +${o.dial} ${o.dial}` });
/** Matches by name (substring), by dial code (`27`, `+27`) or by ISO code (`za`). Digit queries rank exact dial codes first. */
function filterCountries(options: Country[], state: { inputValue: string; getOptionLabel: (o: Country) => string }): Country[] {
  const q = state.inputValue.trim().toLowerCase().replace(/^\+/, '');
  if (!q) return options;
  if (/^\d+$/.test(q)) return options.filter((o) => o.dial.startsWith(q)).sort((a, b) => (a.dial === q ? -1 : b.dial === q ? 1 : a.dial.length - b.dial.length || a.name.localeCompare(b.name)));
  const matches = defaultFilter(options, state).filter((o) => o.name.toLowerCase().includes(q) || o.iso.toLowerCase() === q);
  return matches.sort((a, b) => Number(b.iso.toLowerCase() === q) - Number(a.iso.toLowerCase() === q) || Number(b.name.toLowerCase().startsWith(q)) - Number(a.name.toLowerCase().startsWith(q)));
}

/**
 * Phone number field that outputs E.164: a searchable country picker (flag · name · +dial) as the start
 * adornment and a national-number box formatted as you type. Pasting a full `+…` number into the box
 * switches the country automatically; the last picked country is remembered in `localStorage`.
 */
export default function PhoneField({ value, onChange, label = 'Phone', required, helperText, size = 'medium', disabled, autoFocus, error, kind = 'mobile', defaultCountry = DEFAULT_COUNTRY, placeholder, id, name, sx }: PhoneFieldProps) {
  const reactId = React.useId();
  const inputId = id ?? `phone-${reactId}`;
  // The last country picked in any form (null on the server / before hydration, so no mismatch).
  const stored = useStorageValue(STORAGE_KEY);
  const rememberedCountry = stored && byIso(stored) ? stored : null;
  const [picked, setPicked] = React.useState<string | null>(() => (value ? splitPhone(value, defaultCountry).country : null));
  const [national, setNational] = React.useState<string>(() => splitPhone(value, defaultCountry).national);
  const [touched, setTouched] = React.useState(false);
  const [focused, setFocused] = React.useState(false);
  const [prevValue, setPrevValue] = React.useState(value);
  const inputRef = React.useRef<HTMLInputElement>(null);

  const country = picked ?? rememberedCountry ?? (byIso(defaultCountry) ? defaultCountry : DEFAULT_COUNTRY);
  const current = byIso(country) ?? fallbackCountry;
  const formatted = React.useMemo(() => formatNational(current.iso, national), [current.iso, national]);

  // Follow an external `value` (initial load, form reset, a number set elsewhere) — but not our own echo.
  if (value !== prevValue) {
    setPrevValue(value);
    if (value !== (national ? formatted.e164 : '')) {
      const next = splitPhone(value, country);
      setPicked(value ? next.country : null);
      setNational(next.national);
      setTouched(false);
    }
  }

  const showError = Boolean(error) || (national !== '' && !formatted.valid && (touched || !focused));
  const errorText = `Enter a valid ${current.name} ${kind === 'any' ? 'phone' : 'mobile'} number`;

  const emit = (iso: string, digits: string) => {
    const f = formatNational(iso, digits);
    onChange(digits ? f.e164 : '', { valid: digits !== '' && f.valid, country: iso, national: digits });
  };

  const pickCountry = (c: Country | null) => {
    if (!c) return;
    setPicked(c.iso);
    writeStorage(STORAGE_KEY, c.iso);
    emit(c.iso, national);
    // Hand focus to the number box so the staff member can keep typing.
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const handleNumber = (raw: string) => {
    const trimmed = raw.trim();
    if (/^(\+|00)/.test(trimmed)) {
      // A full international number was pasted (or typed): move the country code into the picker.
      const s = trimmed.replace(/[\s\-().]/g, '').replace(/^00/, '+');
      const parsed = parsePhoneNumberFromString(s);
      if (parsed) {
        const split = splitPhone(parsed.number, country);
        setPicked(split.country);
        writeStorage(STORAGE_KEY, split.country);
        setNational(split.national);
        emit(split.country, split.national);
        return;
      }
    }
    const digits = raw.replace(/\D/g, '');
    setNational(digits);
    emit(current.iso, digits);
  };

  const renderPicker = (params: AutocompleteRenderInputParams) => (
    <TextField
      {...params}
      variant="standard"
      size={size}
      placeholder="Country"
      slotProps={{
        input: { ...params.InputProps, disableUnderline: true, sx: { fontSize: size === 'small' ? 14 : 15, fontWeight: 600, py: 0 } },
        htmlInput: { ...params.inputProps, 'aria-label': 'Country code', autoComplete: 'off', style: { width: 78, padding: 0 } },
      }}
    />
  );

  return (
    <TextField
      id={inputId}
      name={name}
      label={label}
      type="tel"
      value={formatted.display}
      onChange={(e) => handleNumber(e.target.value)}
      onFocus={() => setFocused(true)}
      onBlur={() => { setFocused(false); setTouched(true); }}
      inputRef={inputRef}
      required={required}
      disabled={disabled}
      autoFocus={autoFocus}
      size={size}
      error={showError}
      helperText={showError ? errorText : helperText}
      placeholder={placeholder ?? (current.iso === 'ZA' ? '82 123 4567' : kind === 'any' ? 'Phone number' : 'Mobile number')}
      sx={sx}
      slotProps={{
        inputLabel: { shrink: true },
        htmlInput: { inputMode: 'tel', autoComplete: 'tel-national', 'aria-invalid': showError || undefined, 'aria-describedby': showError ? `${inputId}-helper-text` : undefined },
        input: {
          startAdornment: (
            <InputAdornment position="start" sx={{ maxHeight: 'none', height: 'auto', mr: 0, alignSelf: 'stretch', alignItems: 'center' }}>
              <Autocomplete<Country, false, true, false>
                options={COUNTRIES as Country[]}
                value={current}
                onChange={(_e, c) => pickCountry(c)}
                disabled={disabled}
                disableClearable
                autoHighlight
                selectOnFocus
                handleHomeEndKeys
                filterOptions={filterCountries}
                getOptionLabel={(o) => `${o.flag} +${o.dial}`}
                isOptionEqualToValue={(a, b) => a.iso === b.iso}
                getOptionKey={(o) => o.iso}
                noOptionsText="No country matches"
                popupIcon={<MSymbol name="arrow_drop_down" size={22} />}
                renderInput={renderPicker}
                renderOption={(props, o, { selected }) => {
                  const { key, ...rest } = props as React.HTMLAttributes<HTMLLIElement> & { key: string };
                  return (
                    <li key={key} {...rest} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <span aria-hidden style={{ fontSize: 20, lineHeight: 1 }}>{o.flag}</span>
                      <Typography component="span" variant="body2" sx={{ flex: 1, minWidth: 0, fontWeight: selected ? 700 : 500 }} noWrap>{o.name}</Typography>
                      <Typography component="span" variant="body2" sx={{ fontFamily: fonts.mono, color: tk.onSurfaceVariant }}>+{o.dial}</Typography>
                    </li>
                  );
                }}
                slotProps={{
                  popper: { style: { width: 340 }, placement: 'bottom-start' },
                  paper: { sx: { borderRadius: '16px', mt: 0.75, border: `1px solid ${tk.outlineVariant}` } },
                  listbox: { sx: { maxHeight: 320, py: 0.5 }, 'aria-label': 'Countries' },
                  popupIndicator: { size: 'small', sx: { p: 0.25, mr: 0, color: tk.onSurfaceVariant }, 'aria-label': 'Choose country' },
                }}
                sx={{ width: 'auto', '& .MuiAutocomplete-inputRoot': { pr: '0 !important', flexWrap: 'nowrap' } }}
              />
              <Box aria-hidden sx={{ width: '1px', alignSelf: 'stretch', my: 1.25, mx: 1.25, bgcolor: tk.outline, flexShrink: 0 }} />
            </InputAdornment>
          ),
        },
      }}
    />
  );
}
