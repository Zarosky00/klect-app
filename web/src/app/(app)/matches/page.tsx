import type { Metadata } from 'next';
import { getMatches } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import type { MatchPerson } from '@/lib/types';
import { MatchesBoard } from '@/components/social/MatchesBoard';

export const metadata: Metadata = buildMetadata({
  title: 'Collectors like you',
  description: 'Collectors ranked by how much your taste actually overlaps.',
  path: routes.matches,
  noindex: true,
});

/**
 * `get_matches` is a signed-in-only RPC and `/matches` is in
 * `PROTECTED_PREFIXES`, so middleware has already bounced anonymous visitors.
 * A failure here still degrades to an empty board rather than a 500 — the
 * client offers a recompute.
 */
export default async function MatchesPage() {
  const supabase = await createClient();

  let matches: MatchPerson[] = [];
  try {
    matches = await getMatches(supabase, 24);
  } catch {
    // The board renders its own empty/error affordance with a retry.
  }

  return <MatchesBoard initialMatches={matches} />;
}
