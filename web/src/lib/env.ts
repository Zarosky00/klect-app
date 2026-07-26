/**
 * Public environment. Only ever the PUBLISHABLE key — the service-role key must
 * never reach a client bundle, and nothing in `web/` may read it.
 *
 * The `process.env.NEXT_PUBLIC_*` reads are written out literally on purpose:
 * Next inlines them at build time only when they are statically analysable.
 */

function required(name: string, value: string | undefined): string {
  if (!value || value.length === 0) {
    throw new Error(
      `[klect] Missing environment variable ${name}. Copy web/.env.example to web/.env.local.`,
    );
  }
  return value;
}

export const SUPABASE_URL = required(
  'NEXT_PUBLIC_SUPABASE_URL',
  process.env.NEXT_PUBLIC_SUPABASE_URL,
);

export const SUPABASE_PUBLISHABLE_KEY = required(
  'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
);

/** Absolute origin, used for OG images, sitemaps and auth redirects. */
export const SITE_URL = (
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000')
).replace(/\/$/, '');

export const SITE_NAME = 'Klect';
export const SITE_TAGLINE = 'Collections, not posts.';
export const SITE_DESCRIPTION =
  'Klect is a social network where the unit of content is a collection. Build shelves, group them into subcollections, fill them with things — and surf what everyone else is collecting.';
