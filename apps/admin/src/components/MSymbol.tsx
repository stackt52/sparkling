import * as React from 'react';

export interface MSymbolProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Material Symbols glyph name, e.g. "dashboard". */
  name: string;
  /** FILL=1 for active/filled, FILL=0 for neutral (README iconography). */
  filled?: boolean;
  size?: number;
  weight?: 300 | 400 | 500 | 600 | 700;
  /** Accessible label — omit for purely decorative icons. */
  label?: string;
}

/** Material Symbols Rounded glyph using font-variation-settings for FILL. */
export default function MSymbol({
  name,
  filled = false,
  size = 24,
  weight = 500,
  label,
  style,
  className,
  ...rest
}: MSymbolProps) {
  return (
    <span
      className={['msym', className].filter(Boolean).join(' ')}
      aria-hidden={label ? undefined : true}
      role={label ? 'img' : undefined}
      aria-label={label}
      style={{
        fontSize: size,
        width: size,
        height: size,
        fontVariationSettings: `'FILL' ${filled ? 1 : 0}, 'wght' ${weight}, 'GRAD' 0, 'opsz' ${Math.min(48, Math.max(20, size))}`,
        ...style,
      }}
      {...rest}
    >
      {name}
    </span>
  );
}
