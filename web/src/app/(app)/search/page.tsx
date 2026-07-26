import type { Metadata } from 'next';
import { listPopularTags, listSuggestedCollectors, searchAll } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { EMPTY_SEARCH_RESULTS } from '@/lib/types';
import { getViewerBootstrap } from '@/lib/viewer';
import { SearchExperience } from '@/components/social/SearchExperience';

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function firstParam(value: string | string[] | undefined): string {
  return (Array.isArray(value) ? value[0] : value)?.trim() ?? '';
}

export async function generateMetadata({ searchParams }: PageProps): Promise<Metadata> {
  const query = await searchParams;
  const q = firstParam(query['q']);

  return buildMetadata({
    title: q ? `Search: ${q}` : 'Search',
    description: 'Find collectors, collections, items and tags across Klect.',
    path: q ? `${routes.search}?q=${encodeURIComponent(q)}` : routes.search,
    // A results page is a view of the index, not a document worth indexing.
    noindex: Boolean(q),
  });
}

/**
 * The first paint is server-rendered, so a shared `?q=` link shows real results
 * rather than a spinner. Everything typed after that is instant and local.
 */
export default async function SearchPage({ searchParams }: PageProps) {
  const query = await searchParams;
  const q = firstParam(query['q']);

  const supabase = await createClient();
  const { user } = await getViewerBootstrap();

  const [results, tags, collectors] = await Promise.all([
    q ? searchAll(supabase, q) : Promise.resolve(EMPTY_SEARCH_RESULTS),
    listPopularTags(supabase, 18),
    listSuggestedCollectors(supabase, {
      limit: 6,
      ...(user ? { excludeUserId: user.id } : {}),
    }),
  ]);

  return (
    <SearchExperience
      initialQuery={q}
      initialResults={results}
      popularTags={tags}
      suggestedCollectors={collectors}
    />
  );
}
