'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import { Avatar } from '@/components/ui/Avatar';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextField } from '@/components/ui/TextField';
import { searchAll } from '@/lib/api';
import { cn } from '@/lib/cn';
import { compactCount, shortTimeAgo } from '@/lib/format';
import { postHref } from '@/lib/routes';
import type { PulseEntry, SearchPost } from '@/lib/types';
import { useSession } from '@/providers/session-provider';

/**
 * The Pulse filter drawer (W3): Type and Time chips, the shared-taste toggle,
 * and search-within-pulse — collapsed under the tabs until asked for, because
 * chrome is hidden at rest and one gesture away.
 *
 * Filtering is client-side over the loaded pages (`pulse_feed` has no filter
 * params); search rides `search_all`'s posts section (migration 0021).
 */

export type PulseTypeFilter = 'all' | 'text' | 'photos' | 'collections' | 'quotes';
export type PulseTimeFilter = 'all' | 'today' | 'week' | 'month';

export interface PulseFilters {
  type: PulseTypeFilter;
  time: PulseTimeFilter;
  /** Only entries from collectors who share your taste (`get_matches`). */
  taste: boolean;
  /** Search-within-pulse query. Non-empty swaps the stream for results. */
  q: string;
}

export const DEFAULT_PULSE_FILTERS: PulseFilters = {
  type: 'all',
  time: 'all',
  taste: false,
  q: '',
};

export const PULSE_TYPE_FILTERS: readonly PulseTypeFilter[] = [
  'all',
  'text',
  'photos',
  'collections',
  'quotes',
];

export const PULSE_TYPE_LABELS: Record<PulseTypeFilter, string> = {
  all: 'All',
  text: 'Text',
  photos: 'Photos',
  collections: 'Collections',
  quotes: 'Quotes',
};

export const PULSE_TIME_FILTERS: readonly PulseTimeFilter[] = [
  'today',
  'week',
  'month',
  'all',
];

export const PULSE_TIME_LABELS: Record<PulseTimeFilter, string> = {
  today: 'Today',
  week: 'Week',
  month: 'Month',
  all: 'All time',
};

const HOUR_MS = 3_600_000;
const TIME_WINDOW_MS: Record<Exclude<PulseTimeFilter, 'all'>, number> = {
  today: 24 * HOUR_MS,
  week: 7 * 24 * HOUR_MS,
  month: 30 * 24 * HOUR_MS,
};

export function countActiveFilters(filters: PulseFilters): number {
  return (
    (filters.type === 'all' ? 0 : 1) +
    (filters.time === 'all' ? 0 : 1) +
    (filters.taste ? 1 : 0) +
    (filters.q.trim() ? 1 : 0)
  );
}

/** Does one loaded entry survive the Type/Time/taste filters? */
export function entryMatchesFilters(
  entry: PulseEntry,
  filters: PulseFilters,
  matchIds: ReadonlySet<string> | null,
): boolean {
  if (filters.type !== 'all') {
    const mediaCount = entry.media?.length ?? 0;
    const isQuote = entry.kind === 'quote' || Boolean(entry.quote_text);
    const sharesEntity =
      entry.target_type === 'collection' ||
      entry.target_type === 'subcollection' ||
      entry.target_type === 'item';
    const ok =
      filters.type === 'text'
        ? Boolean(entry.body) && mediaCount === 0 && !entry.target_id
        : filters.type === 'photos'
          ? mediaCount > 0
          : filters.type === 'collections'
            ? sharesEntity
            : isQuote;
    if (!ok) return false;
  }

  if (filters.time !== 'all') {
    const cutoff = Date.now() - TIME_WINDOW_MS[filters.time];
    if (new Date(entry.sort_at).getTime() < cutoff) return false;
  }

  if (filters.taste && matchIds !== null) {
    const actor = entry.actor_id ?? '';
    const reposter = entry.reposter_id ?? '';
    if (!matchIds.has(actor) && !matchIds.has(reposter)) return false;
  }

  return true;
}

export interface PulseFilterDrawerProps {
  open: boolean;
  filters: PulseFilters;
  onChange: (next: PulseFilters) => void;
}

export function PulseFilterDrawer({ open, filters, onChange }: PulseFilterDrawerProps) {
  return (
    <div
      className={cn(
        // Animated collapse: the 0fr→1fr grid row transition needs no measured
        // heights and stays compositor-cheap.
        'grid transition-[grid-template-rows] dur-medium ease-standard',
        open ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]',
      )}
    >
      <div className="min-h-0 overflow-hidden">
        <div
          className="flex flex-col gap-3 border-b border-line-subtle px-4 py-3 sm:px-6"
          aria-hidden={!open}
        >
          <TextField
            label="Search in Pulse"
            labelHidden
            iconLeft="search"
            placeholder="Search posts…"
            value={filters.q}
            tabIndex={open ? 0 : -1}
            onChange={(event) => onChange({ ...filters, q: event.target.value })}
            trailing={
              filters.q ? (
                <button
                  type="button"
                  aria-label="Clear search"
                  tabIndex={open ? 0 : -1}
                  onClick={() => onChange({ ...filters, q: '' })}
                  className="focus-ring mr-1 grid size-8 place-items-center rounded-full text-ink-3 hover:text-ink"
                >
                  <Icon name="close" size="md" />
                </button>
              ) : null
            }
          />

          <ChipGroup label="Post type">
            {PULSE_TYPE_FILTERS.map((value) => (
              <Chip
                key={value}
                selected={filters.type === value}
                disabled={!open}
                onClick={() => onChange({ ...filters, type: value })}
              >
                {PULSE_TYPE_LABELS[value]}
              </Chip>
            ))}
          </ChipGroup>

          <ChipGroup label="Time window">
            {PULSE_TIME_FILTERS.map((value) => (
              <Chip
                key={value}
                selected={filters.time === value}
                disabled={!open}
                onClick={() => onChange({ ...filters, time: value })}
              >
                {PULSE_TIME_LABELS[value]}
              </Chip>
            ))}
            <span aria-hidden className="mx-1 h-5 w-px bg-line-subtle" />
            <Chip
              icon="users"
              tone="accent"
              selected={filters.taste}
              disabled={!open}
              onClick={() => onChange({ ...filters, taste: !filters.taste })}
            >
              Shared taste
            </Chip>
          </ChipGroup>
        </div>
      </div>
    </div>
  );
}

/* ── search-within-pulse results ──────────────────────────────────────────── */

const SEARCH_DEBOUNCE_MS = 250;
const SEARCH_LIMIT = 20;

/**
 * Posts matching the drawer query, straight from `search_all` (0021). Each row
 * routes to the post's thread — search finds the conversation, the thread is
 * where it happens.
 */
export function PulseSearchResults({ query }: { query: string }) {
  const { supabase } = useSession();
  const [posts, setPosts] = useState<SearchPost[] | null>(null);
  const [loading, setLoading] = useState(false);
  const sequence = useRef(0);

  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) return;
    const ticket = ++sequence.current;
    setLoading(true);
    const timer = setTimeout(() => {
      void searchAll(supabase, trimmed, SEARCH_LIMIT)
        .then((results) => {
          if (ticket !== sequence.current) return;
          setPosts(results.posts);
        })
        .catch(() => {
          if (ticket !== sequence.current) return;
          setPosts([]);
        })
        .finally(() => {
          if (ticket === sequence.current) setLoading(false);
        });
    }, SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query, supabase]);

  if (loading && posts === null) {
    return (
      <div className="flex flex-col gap-3 px-4 py-5 sm:px-6">
        <SkeletonRow />
        <SkeletonRow />
      </div>
    );
  }

  if (!posts || posts.length === 0) {
    return (
      <EmptyState
        compact
        icon="search"
        title="No posts matched"
        description={`Nothing in Pulse says “${query.trim()}” yet. Try a shorter word.`}
      />
    );
  }

  return (
    <ol aria-label="Matching posts">
      {posts.map((post) => (
        <li key={post.id}>
          <Link
            href={postHref(post.id)}
            className={cn(
              'focus-ring flex gap-3 border-b border-line-subtle px-4 py-4 sm:px-6',
              'transition-colors dur-fast ease-standard hover:bg-surface-1',
            )}
          >
            <Avatar
              path={post.author?.avatar_path}
              name={post.author?.display_name}
              username={post.author?.username}
              size="sm"
              verified={post.author?.is_verified ?? false}
            />
            <span className="min-w-0 flex-1">
              <span className="flex flex-wrap items-baseline gap-x-2">
                <span className="text-body-strong text-ink">
                  {post.author?.display_name ?? 'Collector'}
                </span>
                <span className="text-caption text-ink-3">
                  @{post.author?.username ?? 'unknown'}
                </span>
                <time dateTime={post.created_at} className="text-caption text-ink-3">
                  {shortTimeAgo(post.created_at)}
                </time>
              </span>
              <span className="mt-0.5 line-clamp-3 whitespace-pre-wrap break-words text-body text-ink-2">
                {post.body}
              </span>
              <span className="tabular mt-1 block text-caption text-ink-3">
                {compactCount(post.like_count)} likes · {compactCount(post.comment_count)}{' '}
                comments
              </span>
            </span>
          </Link>
        </li>
      ))}
    </ol>
  );
}
