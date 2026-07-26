'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, ButtonLink } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Skeleton, SkeletonRow } from '@/components/ui/Skeleton';
import { pulseFeed } from '@/lib/api';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import { PULSE_MODE_LABELS, PULSE_MODES, type PulseEntry, type PulseMode } from '@/lib/types';
import { useSession } from '@/providers/session-provider';
import { PulseCard } from './PulseCard';
import { PulseComposer, type ComposerSubject } from './PulseComposer';

/**
 * The X half of Klect: For-you ▸ Following, each with its own cursor.
 *
 * `pulse_feed` is cursor-paginated on `sort_at` rather than offset-paginated:
 * new posts arrive at the head, so an offset would silently shift every page
 * under the reader. The cursor is the oldest `sort_at` currently on screen —
 * which is also correct for the ranked For-you pages, whose contract is
 * "pass min(sort_at) on screen as the next p_before" (migration 0018).
 *
 * The server renders the first Following page; For-you loads on first switch.
 */

const PAGE_SIZE = 25;

export interface PulseStreamProps {
  initialEntries: PulseEntry[];
}

/** Identity of an entry: a repost and its original are two rows, one post id. */
const entryKey = (entry: PulseEntry): string =>
  `${entry.feed_kind}:${entry.reposter_id ?? ''}:${entry.post_id ?? ''}:${entry.sort_at}`;

interface TabState {
  entries: PulseEntry[];
  exhausted: boolean;
  /** False until the tab has fetched (or was seeded by the server). */
  initialised: boolean;
  error: unknown;
}

export function PulseStream({ initialEntries }: PulseStreamProps) {
  const { supabase, user } = useSession();

  const [mode, setMode] = useState<PulseMode>('following');
  const [tabs, setTabs] = useState<Record<PulseMode, TabState>>(() => ({
    following: {
      entries: initialEntries,
      exhausted: initialEntries.length < PAGE_SIZE,
      initialised: true,
      error: null,
    },
    foryou: { entries: [], exhausted: false, initialised: false, error: null },
  }));
  const [loading, setLoading] = useState(false);
  const [quote, setQuote] = useState<ComposerSubject | null>(null);
  const [freshKey, setFreshKey] = useState<string | null>(null);

  const composerRef = useRef<HTMLDivElement | null>(null);
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  /** The mode with a request in flight, or null. One load at a time. */
  const inFlight = useRef<PulseMode | null>(null);
  /** Render-fresh mirror so `loadMore` reads cursors without re-binding. */
  const tabsRef = useRef(tabs);
  tabsRef.current = tabs;
  const seen = useRef<Record<PulseMode, Set<string>>>({
    following: new Set(initialEntries.map(entryKey)),
    foryou: new Set(),
  });

  const tab = tabs[mode];

  const loadMore = useCallback(
    async (target: PulseMode) => {
      if (inFlight.current !== null) return;
      inFlight.current = target;
      setLoading(true);
      setTabs((current) => ({
        ...current,
        [target]: { ...current[target], error: null },
      }));

      try {
        // min(sort_at) on screen is the cursor — correct for the chronological
        // Following pages and the contract for ranked For-you pages.
        let before: string | undefined;
        for (const entry of tabsRef.current[target].entries) {
          if (before === undefined || entry.sort_at < before) before = entry.sort_at;
        }

        const rows = await pulseFeed(supabase, {
          limit: PAGE_SIZE,
          mode: target,
          ...(before === undefined ? {} : { before }),
        });

        const known = seen.current[target];
        const fresh = rows.filter((row) => {
          const key = entryKey(row);
          if (known.has(key)) return false;
          known.add(key);
          return true;
        });

        setTabs((current) => ({
          ...current,
          [target]: {
            entries: fresh.length > 0 ? [...current[target].entries, ...fresh] : current[target].entries,
            exhausted: rows.length < PAGE_SIZE,
            initialised: true,
            error: null,
          },
        }));
      } catch (thrown) {
        setTabs((current) => ({
          ...current,
          [target]: { ...current[target], error: thrown },
        }));
      } finally {
        setLoading(false);
        inFlight.current = null;
      }
    },
    [supabase],
  );

  /**
   * First activation of a tab fetches its first page. Re-evaluated whenever a
   * load settles, so switching tabs mid-flight still initialises the new tab.
   */
  useEffect(() => {
    if (!tabs[mode].initialised && tabs[mode].error === null && inFlight.current === null) {
      void loadMore(mode);
    }
  }, [loadMore, loading, mode, tabs]);

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel || tab.exhausted || typeof IntersectionObserver === 'undefined') return;

    const observer = new IntersectionObserver(
      (observed) => {
        if (
          observed.some((entry) => entry.isIntersecting) &&
          tab.error === null &&
          tab.initialised
        ) {
          void loadMore(mode);
        }
      },
      { rootMargin: '600px 0px' },
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [loadMore, mode, tab.error, tab.exhausted, tab.initialised]);

  /** `create_post` returns the full envelope — prepend it verbatim. */
  const onPosted = useCallback(
    (entry: PulseEntry) => {
      if (!user) return;
      const key = entryKey(entry);
      seen.current[mode].add(key);
      setFreshKey(key);
      setTabs((current) => ({
        ...current,
        [mode]: { ...current[mode], entries: [entry, ...current[mode].entries] },
      }));
    },
    [mode, user],
  );

  const onQuote = useCallback((subject: ComposerSubject) => {
    setQuote(subject);
    const reduced =
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    composerRef.current?.scrollIntoView({
      behavior: reduced ? 'auto' : 'smooth',
      block: 'center',
    });
  }, []);

  const switchTab = useCallback((next: PulseMode) => {
    setMode(next);
    setFreshKey(null);
  }, []);

  return (
    <div className="flex flex-col">
      <div role="tablist" aria-label="Pulse feeds" className="flex border-b border-line-subtle">
        {PULSE_MODES.map((candidate) => {
          const active = mode === candidate;
          return (
            <button
              key={candidate}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => switchTab(candidate)}
              className={cn(
                'focus-ring flex-1 py-3 text-center transition-colors dur-fast ease-standard',
                active
                  ? 'text-body-strong text-ink'
                  : 'text-body text-ink-3 hover:bg-surface-1 hover:text-ink-2',
              )}
            >
              <span className="relative inline-block pb-1.5">
                {PULSE_MODE_LABELS[candidate]}
                {active ? (
                  <span
                    aria-hidden
                    className="absolute inset-x-0 bottom-0 h-1 rounded-full bg-accent"
                  />
                ) : null}
              </span>
            </button>
          );
        })}
      </div>

      <div ref={composerRef}>
        <PulseComposer onPosted={onPosted} quote={quote} onClearQuote={() => setQuote(null)} />
      </div>

      {tab.entries.length === 0 && !loading ? (
        tab.error !== null ? (
          <ErrorState error={tab.error} onRetry={() => void loadMore(mode)} />
        ) : mode === 'foryou' ? (
          <EmptyState
            icon="compass"
            title="Nothing to rank yet"
            description="For you learns from what you like, save and follow. Interact with a few collections and this feed starts working for you."
            action={
              <ButtonLink href={routes.surf} variant="secondary">
                Go surf the grid
              </ButtonLink>
            }
          />
        ) : (
          <EmptyState
            icon="activity"
            title="Your pulse is quiet"
            description="Pulse shows what the collectors you follow are adding, reposting and saying. Follow a few and it fills up fast."
            action={
              <ButtonLink href={routes.matches} variant="secondary">
                Find collectors like you
              </ButtonLink>
            }
          />
        )
      ) : (
        <ol>
          {tab.entries.map((entry, index) => {
            const key = entryKey(entry);
            return (
              <li key={key}>
                <PulseCard
                  entry={entry}
                  enterIndex={index % PAGE_SIZE}
                  fresh={key === freshKey}
                  onQuote={onQuote}
                />
              </li>
            );
          })}
        </ol>
      )}

      {loading ? (
        <div className="flex flex-col gap-4 px-4 py-5 sm:px-6">
          <SkeletonRow />
          <Skeleton className="h-24 w-full" />
        </div>
      ) : null}

      <div ref={sentinelRef} aria-hidden className="h-px w-full" />

      <div className="flex justify-center py-8">
        {tab.exhausted && tab.entries.length > 0 ? (
          <p className="text-caption text-ink-3">That is everything for now.</p>
        ) : tab.error !== null && tab.entries.length > 0 ? (
          <Button variant="secondary" iconLeft="repost" onClick={() => void loadMore(mode)}>
            Retry
          </Button>
        ) : tab.entries.length > 0 ? (
          <Button variant="ghost" loading={loading} onClick={() => void loadMore(mode)}>
            Load more
          </Button>
        ) : null}
      </div>
    </div>
  );
}
