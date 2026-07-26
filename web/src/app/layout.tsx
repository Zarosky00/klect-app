import type { Metadata, Viewport } from 'next';
import { Instrument_Serif, Inter } from 'next/font/google';
import type { ReactNode } from 'react';
import '@/styles/globals.css';
import { defaultMetadata } from '@/lib/seo';
import { getViewerBootstrap } from '@/lib/viewer';
import { AppProviders } from '@/providers/app-providers';
import { THEME_INIT_SCRIPT } from '@/providers/theme-provider';

/** Display — collection names, profile names, empty-state headlines. Nothing else. */
const instrumentSerif = Instrument_Serif({
  subsets: ['latin'],
  weight: '400',
  style: ['normal', 'italic'],
  display: 'swap',
  variable: '--font-instrument-serif',
});

/** UI — everything else. */
const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter',
});

export const metadata: Metadata = defaultMetadata;

/**
 * No `themeColor` here on purpose: a literal hex in application code is a bug.
 * The inline theme script reads `--k-bg-base` off the document and writes the
 * `<meta name="theme-color">` tag itself, so the browser chrome always matches
 * the tokens — including after a manual theme switch.
 */
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
};

export default async function RootLayout({
  children,
  modal,
}: {
  children: ReactNode;
  modal: ReactNode;
}) {
  const viewer = await getViewerBootstrap();

  return (
    <html
      lang="en"
      className={`${inter.variable} ${instrumentSerif.variable}`}
      suppressHydrationWarning
    >
      <head>
        {/* Applies the stored theme before first paint — no flash, ever. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      </head>
      <body>
        <a className="k-skip-link" href="#main">
          Skip to content
        </a>
        <AppProviders
          initialUser={viewer.user}
          initialProfile={viewer.profile}
          initialRoles={viewer.roles}
        >
          {children}
          {modal}
        </AppProviders>
      </body>
    </html>
  );
}
