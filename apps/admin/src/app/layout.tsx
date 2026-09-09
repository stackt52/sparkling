import type * as React from 'react';
import type { Metadata, Viewport } from 'next';
import { Outfit } from 'next/font/google';
import { AppRouterCacheProvider } from '@mui/material-nextjs/v16-appRouter';
import InitColorSchemeScript from '@mui/material/InitColorSchemeScript';
import ThemeRegistry from '@/theme/ThemeRegistry';
import Providers from '@/lib/Providers';
import './globals.css';

const outfit = Outfit({
  variable: '--font-outfit',
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  display: 'swap',
});

export const metadata: Metadata = {
  title: { default: 'Sparkling Admin', template: '%s · Sparkling Admin' },
  description: 'Sparkling multi-outlet car-wash and auto-body operations dashboard.',
  icons: { icon: '/favicon.ico' },
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#F6FAFD' },
    { media: '(prefers-color-scheme: dark)', color: '#0D1524' },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-ZA" className={outfit.variable} suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        {/* Variable icon font (FILL axis) — not available through next/font; `display=block` avoids ligature text flashing. */}
        {/* eslint-disable-next-line @next/next/no-page-custom-font, @next/next/google-font-display */}
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=block"
        />
      </head>
      <body>
        <InitColorSchemeScript attribute="data" defaultMode="system" />
        <AppRouterCacheProvider options={{ key: 'mui' }}>
          <ThemeRegistry>
            <Providers>{children}</Providers>
          </ThemeRegistry>
        </AppRouterCacheProvider>
      </body>
    </html>
  );
}
