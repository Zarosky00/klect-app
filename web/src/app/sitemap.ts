import type { MetadataRoute } from 'next';
import { listPublicSitemapEntries } from '@/lib/api';
import { SITE_URL } from '@/lib/env';
import {
  collectionHref,
  itemHref,
  profileHref,
  routes,
  subcollectionHref,
} from '@/lib/routes';
import { createClient } from '@/lib/supabase/server';

/** Regenerated hourly; RLS means only public rows can ever appear here. */
export const revalidate = 3600;

const url = (path: string): string => `${SITE_URL}${path}`;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticEntries: MetadataRoute.Sitemap = [
    { url: url(routes.home), changeFrequency: 'weekly', priority: 1 },
    { url: url(routes.about), changeFrequency: 'monthly', priority: 0.5 },
    { url: url(routes.surf), changeFrequency: 'hourly', priority: 0.9 },
    { url: url(routes.search), changeFrequency: 'weekly', priority: 0.4 },
  ];

  try {
    const supabase = await createClient();
    const entries = await listPublicSitemapEntries(supabase);

    return [
      ...staticEntries,
      ...entries.profiles.map((profile) => ({
        url: url(profileHref(profile.username)),
        lastModified: new Date(profile.updated_at),
        changeFrequency: 'daily' as const,
        priority: 0.7,
      })),
      ...entries.collections.map((collection) => ({
        url: url(collectionHref(collection.id)),
        lastModified: new Date(collection.updated_at),
        changeFrequency: 'daily' as const,
        priority: 0.8,
      })),
      ...entries.subcollections.map((subcollection) => ({
        url: url(subcollectionHref(subcollection.id)),
        lastModified: new Date(subcollection.updated_at),
        changeFrequency: 'daily' as const,
        priority: 0.6,
      })),
      ...entries.items.map((item) => ({
        url: url(itemHref(item.id)),
        lastModified: new Date(item.updated_at),
        changeFrequency: 'weekly' as const,
        priority: 0.6,
      })),
    ];
  } catch {
    // A database hiccup must not take the whole sitemap down.
    return staticEntries;
  }
}
