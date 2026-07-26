'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, ButtonLink } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { Skeleton, SkeletonRow } from '@/components/ui/Skeleton';
import { getMatches, pulseFeed } from '@/lib/api';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import {
  PULSE_MODE_LABELS,
  PULSE_MODES,
  pulseEntryKey,
  type PulseEntry,
  type PulseMode,
} from '@/lib/types';
import { useSession } from '@/providers/session-provider';
import { PulseCard } from './PulseCard';
import { PulseComposer, type ComposerSubject } from './PulseComposer';
import {
  countActiveFilters,
  DEFAULT_PULSE_FILTERS,
  entryMatchesFilters,
  PULSE_TIME_FILTERS,
  PULSE_TYPE_FILTERS,
  PulseFilterDrawer,
  PulseSearchResults,
  type PulseFilters,
  type PulseTimeFilter,
  type PulseTypeFilter,
} from './PulseFilterDrawer';

/**
 * The X half of Klect: For-you ▸ Following, each with its own cursor, plus the
 * collapsed filter drawer (W3): Type/Time chips, shared-taste, and
 * search-within-pulse.
 *
 * PAGINATION (migration 0021): `pulse_feed` returns up to `limit + 1`
 * envelopes — the extra row only signals another page exists and is never
 * rendered. Paging is composite-keyset: `(p_before, p_before_id)` = the
 * `(sort_at, cursor_id)` of the minimum row on screen, which stops the
 * same-timestamp skip an equality-only cursor had. Correct for both the
 * chronological Following pages and the score-ordered For-you pages (whose
 * contract is "keep paging with min(sort_at)/its cursor_id on screen").
 */

const PAGE_SIZE = 25;

export interface PulseStreamProps {
  initialEntries: PulseEntry[];
}

/** The composite keyset for the next page. */
interface PulseCursor {
  before: string;
  beforeId: string | null;
}

/** The `(sort_at, cursor_id)` minimum of a page — the next-page cursor. */
function minCursor(rows: PulseEntry[]): PulseCursor | null {
  let best: PulseEntry | null = null;
  for (const row of rows) {
    if (
      best === null ||
      row.sort_at < best.sort_at ||
      (row.sort_at === best.sort_at && (row.cursor_id ?? '') < (best.cursor_id ?? ''))
    ) {
      best = row;
    }
  }
  return best === null ? null : { before: best.sort_at, beforeId: best.cursor_id ?? null };
}

const isTypeFilter = (value: string | null): value is PulseTypeFilter =>
  value !== null && (PULSE_TYPE_FILTERS as readonly string[]).includes(value);
const isTimeFilter = (value: string | null): value is PulseTimeFilter =>
  value !== null && (PULSE_TIME_FILTERS as readonly string[]).includes(value);

interface TabState {
  entries: PulseEntry[];
  exhausted: boolean;
  /** False until the tab has fetched (or was seeded by the server). */
  initialised: boolean;
  error: unknown;
  cursor: PulseCursor | null;
}

export function PulseStream({ initialEntries }: PulseStreamProps) {
  const { supabase, user } = useSession();

  const [mode, setMode] = useState<PulseMode>('foryou');
  const [tabs, setTabs] = useState<Record<PulseMode, TabState>>(() => {
    // Extra-row contract: the server page asked for PAGE_SIZE and may hold
    // PAGE_SIZE + 1 rows — render PAGE_SIZE, the surplus row just means more.
    const rendered = initialEntries.slice(0, PAGE_SIZE);
    return {
      foryou: {
        entries: rendered,
        exhausted: initialEntries.length <= PAGE_SIZE,
        initialised: true,
        error: null,
        cursor: minCursor(rendered),
      },
      following: { entries: [], exhausted: false, initialised: false, error: null, cursor: null },
    };
  });
  const [loading, setLoading] = useState(false);
  const [quote, setQuote] = useState<ComposerSubject | null>(null);
  const [freshKey, setFreshKey] = useState<string | null>(null);

  const [filtersOpen, setFiltersOpen] = useState(false);
  const [filters, setFilters] = useState<PulseFilters>(DEFAULT_PULSE_FILTERS);
  /** Collector ids who share the viewer's taste — fetched when first needed. */
  const [matchIds, setMatchIds] = useState<ReadonlySet<string> | null>(null);

  const composerRef = useRef<HTMLDivElement | null>(null);
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  /** The mode with a request in flight, or null. One load at a time. */
  const inFlight = useRef<PulseMode | null>(null);
  /** Render-fresh mirror so `loadMore` reads cursors without re-binding. */
  const tabsRef = useRef(tabs);
  tabsRef.current = tabs;
  const seen = useRef<Record<PulseMode, Set<string>>>({
    foryou: new Set(initialEntries.slice(0, PAGE_SIZE).map(pulseEntryKey)),
    following: new Set(),
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
        const cursor = tabsRef.current[target].cursor;
        const rows = await pulseFeed(supabase, {
          limit: PAGE_SIZE,
          mode: target,
          ...(cursor === null
            ? {}
            : {
                before: cursor.before,
                ...(cursor.beforeId === null ? {} : { beforeId: cursor.beforeId }),
              }),
        });

        // Extra-row has_more: render PAGE_SIZE, the surplus row is a signal.
        const hasMore = rows.length > PAGE_SIZE;
        const rendered = hasMore ? rows.slice(0, PAGE_SIZE) : rows;

        const known = seen.current[target];
        const fresh = rendered.filter((row) => {
          const key = pulseEntryKey(row);
          if (known.has(key)) return false;
          known.add(key);
          return true;
        });

        setTabs((current) => ({
          ...current,
          [target]: {
            entries:
              fresh.length > 0 ? [...current[target].entries, ...fresh] : current[target].entries,
            exhausted: !hasMore,
            initialised: true,
            error: null,
            // Advance even when every row deduped away, so the next fetch digs
            // deeper instead of spinning on the same page.
            cursor: minCursor(rendered) ?? current[target].cursor,
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

  /* ── filters ────────────────────────────────────────────────────────────── */

  /** Set filters and mirror them into the URL — shareable without navigating. */
  const applyFilters = useCallback((next: PulseFilters) => {
    setFilters(next);
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    if (next.type === 'all') url.searchParams.delete('type');
    else url.searchParams.set('type', next.type);
    if (next.time === 'all') url.searchParams.delete('time');
    else url.searchParams.set('time', next.time);
    if (next.taste) url.searchParams.set('taste', '1');
    else url.searchParams.delete('taste');
    const q = next.q.trim();
    if (q) url.searchParams.set('q', q);
    else url.searchParams.delete('q');
    window.history.replaceState(null, '', url.toString());
  }, []);

  // Honour filter searchParams on a cold deep link.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const params = new URL(window.location.href).searchParams;
    const type = params.get('type');
    const time = params.get('time');
    const next: PulseFilters = {
      type: isTypeFilter(type) ? type : 'all',
      time: isTimeFilter(time) ? time : 'all',
      taste: params.get('taste') === '1',
      q: params.get('q') ?? '',
    };
    if (countActiveFilters(next) > 0) {
      setFilters(next);
      setFiltersOpen(true);
    }
    // Deep-link resolution runs once, on mount.
  }, []);

  // Shared-taste needs the match list; fetch it the first time it is asked for.
  useEffect(() => {
    if (!filters.taste || matchIds !== null) return;
    let cancelled = false;
    getMatches(supabase, 50)
      .then((people) => {
        if (!cancelled) setMatchIds(new Set(people.map((person) => person.id)));
      })
      .catch(() => {
        if (!cancelled) setMatchIds(new Set());
      });
    return () => {
      cancelled = true;
    };
  }, [filters.taste, matchIds, supabase]);

  const query = filters.q.trim();
  const activeCount = countActiveFilters(filters);

  /** The loaded entries that survive the Type/Time/taste filters. */
  const visible = useMemo(
    () => tab.entries.filter((entry) => entryMatchesFilters(entry, filters, matchIds)),
    [filters, matchIds, tab.entries],
  );

  /* ── stream machinery ───────────────────────────────────────────────────── */

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (
      !sentinel ||
      tab.exhausted ||
      query !== '' ||
      typeof IntersectionObserver === 'undefined'
    ) {
      return;
    }

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
  }, [loadMore, mode, query, tab.error, tab.exhausted, tab.initialised]);

  /** `create_post` returns the full envelope — prepend it verbatim. */
  const onPosted = useCallback(
    (entry: PulseEntry) => {
      if (!user) return;
      const key = pulseEntryKey(entry);
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
      <div className="flex items-stretch border-b border-line-subtle">
        <div role="tablist" aria-label="Pulse feeds" className="flex flex-1">
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

        <div className="flex items-center pr-2">
          <button
            type="button"
            aria-label={filtersOpen ? 'Hide filters' : 'Show filters'}
            aria-expanded={filtersOpen}
            aria-controls="pulse-filters"
            onClick={() => setFiltersOpen((open) => !open)}
            className={cn(
              'focus-ring relative grid size-9 shrink-0 place-items-center rounded-full',
              'transition-colors dur-fast ease-standard',
              filtersOpen || activeCount > 0
                ? 'bg-accent-subtle text-accent'
                : 'text-ink-3 hover:bg-surface-1 hover:text-ink',
            )}
          >
            <Icon name="sliders" size="md" />
            {activeCount > 0 ? (
              <span
                className={cn(
                  'tabular absolute -right-0.5 -top-0.5 grid min-w-4 place-items-center',
                  'rounded-full bg-accent px-1 text-micro leading-4 text-ink-on-accent',
                )}
              >
                {activeCount}
              </span>
            ) : null}
          </button>
        </div>
      </div>

      <div id="pulse-filters">
        <PulseFilterDrawer open={filtersOpen} filters={filters} onChange={applyFilters} />
      </div>

      {query !== '' ? (
        // Search-within-pulse swaps the stream for `search_all` post results.
        <PulseSearchResults query={filters.q} />
      ) : (
        <>
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
          ) : visible.length === 0 && tab.entries.length > 0 && !loading ? (
            <EmptyState
              compact
              icon="sliders"
              title="Nothing matches your filters"
              description="Loosen the type or time window — or load more of the stream."
              action={
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => applyFilters(DEFAULT_PULSE_FILTERS)}
                >
                  Clear filters
                </Button>
              }
            />
          ) : (
            <ol>
              {visible.map((entry, index) => {
                const key = pulseEntryKey(entry);
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
        </>
      )}
    </div>
  );
}
