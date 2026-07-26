'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, IconButton } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { SkeletonGrid } from '@/components/ui/Skeleton';
import { surfFeed } from '@/lib/api';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import { SURF_FILTERS, SURF_FILTER_LABELS, type SurfFilter } from '@/lib/types';
import { useSession } from '@/providers/session-provider';
import { TileGrid } from './TileGrid';
import { tileFromSurfCard, tileKey, type TileCard } from './tile-card';

/**
 * The Pinterest half of Klect.
 *
 * `surf_feed` interleaves items, subcollections and collections on a fixed
 * cadence, so this grid must render all three card shapes — it never assumes a
 * tile is an item.
 *
 * Pagination is offset-based against one **stable seed** for the whole session.
 * The seed deterministically jitters ranking, so two accounts see different
 * orders while one account's pages stay consistent — that is exactly why the
 * seed is computed once on the server and handed down rather than being
 * regenerated per request. A `Set` of `type:id` keys guarantees no duplicate can
 * survive even if a row shifts between pages.
 */

const PAGE_SIZE = 30;

/**
 * Ceiling on retained cards. Offscreen tiles are cheap (`content-visibility:
 * auto` in `Masonry`), but state, keys and DOM nodes still accumulate on an
 * endless scroll — so the append-only growth stops here and the reader is
 * offered a reseed instead. 20 pages ≈ 40+ screens of tiles.
 */
const MAX_CARDS = PAGE_SIZE * 20;

export interface SurfGridProps {
  initialCards: TileCard[];
  seed: string;
  initialFilter: SurfFilter;
  /** `following` is meaningless signed out — hidden rather than shown empty. */
  canFilterFollowing: boolean;
}

interface FeedState {
  cards: TileCard[];
  offset: number;
  exhausted: boolean;
}

export function SurfGrid({
  initialCards,
  seed,
  initialFilter,
  canFilterFollowing,
}: SurfGridProps) {
  const { supabase } = useSession();

  const [filter, setFilter] = useState<SurfFilter>(initialFilter);
  const [seedSuffix, setSeedSuffix] = useState(0);
  const [state, setState] = useState<FeedState>({
    cards: initialCards,
    offset: initialCards.length,
    exhausted: initialCards.length === 0,
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const seenKeys = useRef(new Set(initialCards.map(tileKey)));
  /** Guards against two observers firing for the same page. */
  const inFlight = useRef(false);
  const requestId = useRef(0);

  const activeSeed = seedSuffix === 0 ? seed : `${seed}#${seedSuffix}`;

  const filters = useMemo(
    () => SURF_FILTERS.filter((value) => value !== 'following' || canFilterFollowing),
    [canFilterFollowing],
  );

  const reset = useCallback(
    (nextFilter: SurfFilter, nextSeedSuffix: number) => {
      requestId.current += 1;
      seenKeys.current = new Set();
      inFlight.current = false;
      setError(null);
      setState({ cards: [], offset: 0, exhausted: false });
      setFilter(nextFilter);
      setSeedSuffix(nextSeedSuffix);
    },
    [],
  );

  const atCapacity = state.cards.length >= MAX_CARDS;

  const loadMore = useCallback(async () => {
    if (inFlight.current) return;
    if (state.cards.length >= MAX_CARDS) return;
    inFlight.current = true;
    const ticket = requestId.current;
    setLoading(true);
    setError(null);

    try {
      const rows = await surfFeed(supabase, {
        limit: PAGE_SIZE,
        offset: state.offset,
        seed: activeSeed,
        filter,
      });
      if (ticket !== requestId.current) return;

      const fresh: TileCard[] = [];
      for (const row of rows) {
        const card = tileFromSurfCard(row);
        const key = tileKey(card);
        if (seenKeys.current.has(key)) continue;
        seenKeys.current.add(key);
        fresh.push(card);
      }

      setState((current) => ({
        cards: [...current.cards, ...fresh],
        offset: current.offset + rows.length,
        // An empty page is the only reliable end-of-feed signal: the RPC
        // interleaves three entity types, so a short page is not the end.
        exhausted: rows.length === 0,
      }));
    } catch (thrown) {
      if (ticket === requestId.current) setError(thrown);
    } finally {
      if (ticket === requestId.current) setLoading(false);
      inFlight.current = false;
    }
  }, [activeSeed, filter, state.cards.length, state.offset, supabase]);

  // Refill after a filter change or a reseed.
  useEffect(() => {
    if (state.cards.length === 0 && !state.exhausted && !loading && !error) {
      void loadMore();
    }
  }, [error, loadMore, loading, state.cards.length, state.exhausted]);

  // Infinite scroll. `rootMargin` starts the next page a screen early so the
  // reader never actually reaches the bottom.
  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel || typeof IntersectionObserver === 'undefined') return;
    if (state.exhausted || atCapacity) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting) && !error) void loadMore();
      },
      { rootMargin: '900px 0px' },
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [atCapacity, error, loadMore, state.exhausted]);

  const changeFilter = useCallback(
    (next: SurfFilter) => {
      if (next === filter) return;
      reset(next, seedSuffix);
      if (typeof window !== 'undefined') {
        const url = next === 'all' ? routes.surf : `${routes.surf}?filter=${next}`;
        window.history.replaceState(null, '', url);
      }
    },
    [filter, reset, seedSuffix],
  );

  const reseed = useCallback(() => {
    reset(filter, seedSuffix + 1);
    if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' });
  }, [filter, reset, seedSuffix]);

  const showInitialSkeleton = state.cards.length === 0 && loading;

  return (
    <div className="flex flex-col gap-4">
      <div
        className={cn(
          'glass sticky top-0 z-sticky -mx-4 flex items-center gap-3 px-4 py-3 sm:-mx-6 sm:px-6',
          'border-b border-line-subtle',
        )}
      >
        <ChipGroup label="Filter the feed" className="min-w-0 flex-1 flex-nowrap overflow-x-auto">
          {filters.map((value) => (
            <Chip
              key={value}
              selected={filter === value}
              onClick={() => changeFilter(value)}
            >
              {SURF_FILTER_LABELS[value]}
            </Chip>
          ))}
        </ChipGroup>

        <IconButton
          icon="repost"
          label="Fresh picks"
          variant="ghost"
          size="sm"
          onClick={reseed}
        />
      </div>

      {showInitialSkeleton ? (
        <SkeletonGrid count={12} />
      ) : (
        <TileGrid
          cards={state.cards}
          emptyState={
            error ? null : (
              <EmptyState
                icon="compass"
                title="Nothing here yet"
                description={
                  filter === 'following'
                    ? 'Follow a few collectors and their shelves will show up here.'
                    : 'The feed is empty right now. Try another filter, or start a collection of your own.'
                }
                action={
                  <Button variant="secondary" onClick={reseed} iconLeft="repost">
                    Try again
                  </Button>
                }
              />
            )
          }
        />
      )}

      {error && state.cards.length === 0 ? (
        <ErrorState error={error} onRetry={() => void loadMore()} />
      ) : null}

      <div ref={sentinelRef} aria-hidden className="h-px w-full" />

      <div className="flex justify-center pb-10 pt-2">
        {state.exhausted && state.cards.length > 0 ? (
          <p className="text-caption text-ink-3">You have reached the end of the feed.</p>
        ) : atCapacity ? (
          <div className="flex flex-col items-center gap-3">
            <p className="text-caption text-ink-3">
              That is a lot of surfing. Reshuffle for fresh picks.
            </p>
            <Button variant="secondary" onClick={reseed} iconLeft="repost">
              Fresh picks
            </Button>
          </div>
        ) : error && state.cards.length > 0 ? (
          <Button variant="secondary" onClick={() => void loadMore()} iconLeft="repost">
            Retry
          </Button>
        ) : state.cards.length > 0 ? (
          <Button
            variant="ghost"
            onClick={() => void loadMore()}
            loading={loading}
            aria-label="Load more"
          >
            {loading ? 'Loading' : 'Load more'}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
