'use client';
import Image from 'next/image';
import Box from '@mui/material/Box';

/** Sparkling wordmark that swaps between the light and dark asset with the colour scheme. */
export function Logo({ height = 30 }: { height?: number }) {
  return (
    <Box sx={{ position: 'relative', height, width: height * 2.7, display: 'block' }}>
      <Image src="/logo-light.png" alt="Sparkling" fill sizes="120px" style={{ objectFit: 'contain' }} className="logo-light" priority />
      <Image src="/logo-dark.png" alt="" fill sizes="120px" style={{ objectFit: 'contain' }} className="logo-dark" priority />
      <style>{`
        .logo-dark{display:none}
        [data-mui-color-scheme="dark"] .logo-light{display:none}
        [data-mui-color-scheme="dark"] .logo-dark{display:block}
      `}</style>
    </Box>
  );
}

export default Logo;
