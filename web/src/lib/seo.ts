import type { Metadata } from 'next';
import { SITE_DESCRIPTION, SITE_NAME, SITE_TAGLINE, SITE_URL } from '@/lib/env';
import { truncate } from '@/lib/format';

export function absoluteUrl(path: string): string {
  if (/^https?:\/\//i.test(path)) return path;
  return `${SITE_URL}${path.startsWith('/') ? path : `/${path}`}`;
}

export interface PageMetadataInput {
  title: string;
  description?: string | null;
  path: string;
  /** Absolute or storage-relative image URL. Falls back to the default OG card. */
  image?: string | null;
  imageAlt?: string;
  type?: 'website' | 'article' | 'profile';
  /** Set for content that must never be indexed (settings, admin, DMs). */
  noindex?: boolean;
  publishedTime?: string | null;
  authors?: string[];
}

const MAX_DESCRIPTION = 160;

export function buildMetadata({
  title,
  description,
  path,
  image,
  imageAlt,
  type = 'website',
  noindex = false,
  publishedTime,
  authors,
}: PageMetadataInput): Metadata {
  const url = absoluteUrl(path);
  const resolvedDescription = truncate(
    (description ?? SITE_DESCRIPTION).replace(/\s+/g, ' ').trim(),
    MAX_DESCRIPTION,
  );
  const images = image
    ? [{ url: image, alt: imageAlt ?? title }]
    : [{ url: absoluteUrl('/opengraph-image'), alt: SITE_NAME }];

  return {
    title,
    description: resolvedDescription,
    alternates: { canonical: url },
    openGraph: {
      type: type === 'profile' ? 'profile' : type,
      title,
      description: resolvedDescription,
      url,
      siteName: SITE_NAME,
      images,
      ...(publishedTime ? { publishedTime } : {}),
    },
    twitter: {
      card: 'summary_large_image',
      title,
      description: resolvedDescription,
      images: images.map((entry) => entry.url),
    },
    ...(authors ? { authors: authors.map((name) => ({ name })) } : {}),
    ...(noindex ? { robots: { index: false, follow: false } } : {}),
  };
}

/** The metadata for something that could not be found or is not visible to you. */
export function notFoundMetadata(what: string): Metadata {
  return {
    title: `${what} not found`,
    description: `This ${what.toLowerCase()} is private, deleted, or never existed.`,
    robots: { index: false, follow: false },
  };
}

export const defaultMetadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: `${SITE_NAME} — ${SITE_TAGLINE}`,
    template: `%s · ${SITE_NAME}`,
  },
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  keywords: [
    'collections',
    'collectors',
    'curation',
    'social network',
    'visual discovery',
  ],
  openGraph: {
    type: 'website',
    siteName: SITE_NAME,
    title: `${SITE_NAME} — ${SITE_TAGLINE}`,
    description: SITE_DESCRIPTION,
    url: SITE_URL,
  },
  twitter: { card: 'summary_large_image' },
  formatDetection: { telephone: false, address: false, email: false },
};
