import type { Metadata } from 'next';
import { SurfGrid } from '@/components/surf/SurfGrid';
import { tileFromSurfCard, type TileCard } from '@/components/surf/tile-card';
import { surfFeed } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { SURF_FILTERS, type SurfFilter } from '@/lib/types';
import { getViewerBootstrap } from '@/lib/viewer';

export const metadata: Metadata = buildMetadata({
  title: 'Surf',
  description:
    'A masonry grid of collections, subcollections and items from collectors worth watching.',
  path: routes.surf,
});

/** The first page is rendered on the server, so the grid paints with content. */
const FIRST_PAGE = 30;

interface PageProps {
  searchParams: Promise<{ filter?: string }>;
}

function parseFilter(value: string | undefined): SurfFilter {
  return SURF_FILTERS.includes(value as SurfFilter) ? (value as SurfFilter) : 'all';
}

/**
 * The seed must be stable for the whole session or pagination develops holes:
 * `surf_feed` jitters ranking deterministically from it, so page 2 only lines
 * up with page 1 when both pages were asked for with the same seed. Signed in,
 * the user id is the natural constant — and it is also what makes two accounts
 * see visibly different orders. Signed out, the calendar day is: different
 * enough that the grid is not frozen forever, stable enough that one scroll
 * never repeats or skips.
 */
function seedFor(userId: string | null): string {
  if (userId) return userId;
  return `anon-${new Date().toISOString().slice(0, 10)}`;
}

export default async function SurfPage({ searchParams }: PageProps) {
  const [{ filter: rawFilter }, viewer] = await Promise.all([
    searchParams,
    getViewerBootstrap(),
  ]);

  const filter = parseFilter(rawFilter);
  const seed = seedFor(viewer.user?.id ?? null);
  const supabase = await createClient();

  let initialCards: TileCard[] = [];
  try {
    const rows = await surfFeed(supabase, {
      limit: FIRST_PAGE,
      offset: 0,
      seed,
      filter,
    });
    initialCards = rows.map(tileFromSurfCard);
  } catch {
    // The client re-requests page 0 on mount and owns the error surface, so a
    // cold database or a dropped connection lands on a retryable state rather
    // than a 500.
    initialCards = [];
  }

  return (
    <div className="content-max px-4 sm:px-6">
      <h1 className="sr-only">Surf</h1>
      <SurfGrid
        initialCards={initialCards}
        seed={seed}
        initialFilter={filter}
        canFilterFollowing={viewer.user !== null}
      />
    </div>
  );
}
