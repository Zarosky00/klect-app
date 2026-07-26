'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { searchAll } from '@/lib/api';
import { cn } from '@/lib/cn';
import { compactCount, plural } from '@/lib/format';
import { collectionHref, itemHref, profileHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import { EMPTY_SEARCH_RESULTS, type SearchResults } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextField } from '@/components/ui/TextField';
import type { ProfileRow } from '@/lib/types';
import { useSession } from '@/providers/session-provider';

/**
 * Instant search over `search_all`: one query, four result sets.
 *
 * Typing is debounced and every in-flight response carries a sequence number,
 * so a slow request for "ani" can never overwrite the results for "anime".
 * `?q=` is kept in sync with `replaceState` — the URL is shareable and the back
 * button still leaves the page rather than replaying keystrokes.
 *
 * The whole result list is one roving-focus listbox: ↑/↓ move, Enter opens,
 * Escape clears. The mouse and the keyboard reach exactly the same rows.
 */

const DEBOUNCE_MS = 200;
const RESULT_LIMIT = 20;

const SEGMENTS = ['all', 'people', 'collections', 'items', 'tags'] as const;
type Segment = (typeof SEGMENTS)[number];

const SEGMENT_LABELS: Record<Segment, string> = {
  all: 'Everything',
  people: 'People',
  collections: 'Collections',
  items: 'Items',
  tags: 'Tags',
};

interface FlatResult {
  key: string;
  href: string;
}

export interface SearchExperienceProps {
  initialQuery: string;
  initialResults: SearchResults;
  popularTags: Array<{ id: string; name: string; slug: string; use_count: number }>;
  suggestedCollectors: ProfileRow[];
}

export function SearchExperience({
  initialQuery,
  initialResults,
  popularTags,
  suggestedCollectors,
}: SearchExperienceProps) {
  const router = useRouter();
  const { supabase } = useSession();

  const [query, setQuery] = useState(initialQuery);
  const [segment, setSegment] = useState<Segment>('all');
  const [results, setResults] = useState<SearchResults>(initialResults);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);
  const [active, setActive] = useState(-1);

  const sequence = useRef(0);
  const rowRefs = useRef<Array<HTMLAnchorElement | null>>([]);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const run = useCallback(
    async (term: string) => {
      const ticket = ++sequence.current;
      const trimmed = term.trim();
      if (!trimmed) {
        setResults(EMPTY_SEARCH_RESULTS);
        setLoading(false);
        setFailure(null);
        return;
      }
      setLoading(true);
      setFailure(null);
      try {
        const next = await searchAll(supabase, trimmed, RESULT_LIMIT);
        // A stale response is dropped rather than rendered.
        if (ticket !== sequence.current) return;
        setResults(next);
      } catch (error) {
        if (ticket !== sequence.current) return;
        setFailure(error);
      } finally {
        if (ticket === sequence.current) setLoading(false);
      }
    },
    [supabase],
  );

  // The first render already has server-rendered results for `initialQuery`;
  // every keystroke after that debounces into `run`.
  const primed = useRef(false);
  useEffect(() => {
    if (!primed.current) {
      primed.current = true;
      return;
    }
    const timer = setTimeout(() => void run(query), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [query, run]);

  // Keep the URL shareable without pushing a history entry per keystroke.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    const trimmed = query.trim();
    if (trimmed) url.searchParams.set('q', trimmed);
    else url.searchParams.delete('q');
    window.history.replaceState(null, '', url.toString());
  }, [query]);

  useEffect(() => setActive(-1), [results, segment]);

  const show = useCallback(
    (which: Exclude<Segment, 'all'>) => segment === 'all' || segment === which,
    [segment],
  );

  const flat = useMemo<FlatResult[]>(() => {
    const list: FlatResult[] = [];
    if (show('people')) {
      for (const person of results.people) {
        list.push({ key: `person:${person.id}`, href: profileHref(person.username) });
      }
    }
    if (show('collections')) {
      for (const collection of results.collections) {
        list.push({ key: `collection:${collection.id}`, href: collectionHref(collection.id) });
      }
    }
    if (show('items')) {
      for (const item of results.items) {
        list.push({ key: `item:${item.id}`, href: itemHref(item.id) });
      }
    }
    if (show('tags')) {
      for (const tag of results.tags) {
        list.push({ key: `tag:${tag.slug}`, href: `/search?q=${encodeURIComponent(tag.name)}` });
      }
    }
    return list;
  }, [results, show]);

  const indexOf = useCallback(
    (key: string) => flat.findIndex((entry) => entry.key === key),
    [flat],
  );

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      if (flat.length === 0) return;
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        setActive((current) => {
          const next = current + 1 >= flat.length ? 0 : current + 1;
          rowRefs.current[next]?.scrollIntoView({ block: 'nearest' });
          return next;
        });
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        setActive((current) => {
          const next = current - 1 < 0 ? flat.length - 1 : current - 1;
          rowRefs.current[next]?.scrollIntoView({ block: 'nearest' });
          return next;
        });
      } else if (event.key === 'Enter') {
        const target = flat[active];
        if (target) {
          event.preventDefault();
          router.push(target.href);
        }
      } else if (event.key === 'Escape') {
        event.preventDefault();
        setQuery('');
        setActive(-1);
        inputRef.current?.focus();
      }
    },
    [active, flat, router],
  );

  const total =
    results.people.length +
    results.collections.length +
    results.items.length +
    results.tags.length;
  const hasQuery = query.trim().length > 0;

  const rowClass = (index: number) =>
    cn(
      'focus-ring flex items-center gap-3 rounded-lg px-3 py-2.5 transition-colors dur-fast ease-standard',
      index === active ? 'bg-surface-2' : 'hover:bg-surface-2',
    );

  let cursor = -1;
  const nextIndex = () => {
    cursor += 1;
    return cursor;
  };

  return (
    <div className="content-max px-4 py-8 sm:px-6" onKeyDown={onKeyDown}>
      <h1 className="font-display text-display2 text-ink">Search</h1>
      <p className="mt-1 text-callout text-ink-2">
        People, collections, items and tags — one query, four result sets.
      </p>

      <div className="sticky top-0 z-sticky -mx-4 mt-6 border-b border-line-subtle bg-base px-4 pb-3 pt-3 sm:-mx-6 sm:px-6">
        <TextField
          ref={inputRef}
          label="Search Klect"
          labelHidden
          value={query}
          autoFocus
          role="combobox"
          aria-expanded={hasQuery}
          aria-controls="search-results"
          aria-autocomplete="list"
          aria-activedescendant={active >= 0 ? flat[active]?.key : undefined}
          onChange={(event) => setQuery(event.target.value)}
          iconLeft="search"
          placeholder="Try “vinyl”, “@aria”, or “jjk”"
          trailing={
            loading ? (
              <span className="pr-2 text-ink-3">
                <Icon name="spinner" size="md" />
              </span>
            ) : query ? (
              <button
                type="button"
                aria-label="Clear search"
                onClick={() => {
                  setQuery('');
                  inputRef.current?.focus();
                }}
                className="focus-ring mr-1 grid size-8 place-items-center rounded-full text-ink-3 hover:text-ink"
              >
                <Icon name="close" size="md" />
              </button>
            ) : null
          }
        />

        <ChipGroup label="Result type" className="mt-3">
          {SEGMENTS.map((value) => (
            <Chip
              key={value}
              selected={segment === value}
              onClick={() => setSegment(value)}
              tone="neutral"
            >
              {SEGMENT_LABELS[value]}
            </Chip>
          ))}
        </ChipGroup>
      </div>

      <div id="search-results" role="listbox" aria-label="Search results" className="mt-2">
        {failure ? (
          <ErrorState error={failure} onRetry={() => void run(query)} compact />
        ) : !hasQuery ? (
          <ZeroState tags={popularTags} collectors={suggestedCollectors} onPick={setQuery} />
        ) : loading && total === 0 ? (
          <div className="flex flex-col gap-3 py-4">
            {Array.from({ length: 6 }, (_, index) => (
              <SkeletonRow key={index} />
            ))}
          </div>
        ) : total === 0 ? (
          <EmptyState
            icon="search"
            title="Nothing matched"
            description={`No people, collections, items or tags for “${query.trim()}”. Try a shorter word, or browse the popular tags below.`}
            action={
              <ChipGroup className="justify-center">
                {popularTags.slice(0, 6).map((tag) => (
                  <Chip key={tag.id} onClick={() => setQuery(tag.name)}>
                    #{tag.name}
                  </Chip>
                ))}
              </ChipGroup>
            }
          />
        ) : (
          <div className="flex flex-col gap-8 py-2">
            {show('people') && results.people.length > 0 ? (
              <Section title="People" count={results.people.length}>
                {results.people.map((person) => {
                  const index = nextIndex();
                  return (
                    <Link
                      key={person.id}
                      id={`person:${person.id}`}
                      role="option"
                      aria-selected={index === active}
                      ref={(node) => {
                        rowRefs.current[index] = node;
                      }}
                      href={profileHref(person.username)}
                      onMouseEnter={() => setActive(indexOf(`person:${person.id}`))}
                      className={rowClass(index)}
                    >
                      <Avatar
                        path={person.avatar_path}
                        name={person.display_name}
                        username={person.username}
                        verified={person.is_verified}
                      />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-body-strong text-ink">
                          {person.display_name}
                        </span>
                        <span className="block truncate text-caption text-ink-3">
                          @{person.username}
                          {person.bio ? ` · ${person.bio}` : ''}
                        </span>
                      </span>
                      <span className="tabular shrink-0 text-caption text-ink-3">
                        {compactCount(person.follower_count)}{' '}
                        {plural(person.follower_count, 'follower')}
                      </span>
                    </Link>
                  );
                })}
              </Section>
            ) : null}

            {show('collections') && results.collections.length > 0 ? (
              <Section title="Collections" count={results.collections.length}>
                {results.collections.map((collection) => {
                  const index = nextIndex();
                  return (
                    <Link
                      key={collection.id}
                      id={`collection:${collection.id}`}
                      role="option"
                      aria-selected={index === active}
                      ref={(node) => {
                        rowRefs.current[index] = node;
                      }}
                      href={collectionHref(collection.id)}
                      onMouseEnter={() => setActive(indexOf(`collection:${collection.id}`))}
                      className={rowClass(index)}
                    >
                      <span className="size-12 shrink-0 overflow-hidden rounded-md">
                        <BlurhashImage
                          src={mediaUrl(collection.cover_path)}
                          alt=""
                          blurhash={collection.cover_blurhash}
                          fallbackAspect={1}
                          sizes="48px"
                        />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-display text-title3 text-ink">
                          {collection.name}
                        </span>
                        <span className="block truncate text-caption text-ink-3">
                          @{collection.username} · {compactCount(collection.item_count)}{' '}
                          {plural(collection.item_count, 'item')}
                        </span>
                      </span>
                      <span className="tabular shrink-0 text-caption text-ink-3">
                        {compactCount(collection.like_count)} ♥
                      </span>
                    </Link>
                  );
                })}
              </Section>
            ) : null}

            {show('items') && results.items.length > 0 ? (
              <Section title="Items" count={results.items.length}>
                {results.items.map((item) => {
                  const index = nextIndex();
                  return (
                    <Link
                      key={item.id}
                      id={`item:${item.id}`}
                      role="option"
                      aria-selected={index === active}
                      ref={(node) => {
                        rowRefs.current[index] = node;
                      }}
                      href={itemHref(item.id)}
                      onMouseEnter={() => setActive(indexOf(`item:${item.id}`))}
                      className={rowClass(index)}
                    >
                      <span className="size-12 shrink-0 overflow-hidden rounded-md">
                        <BlurhashImage
                          src={mediaUrl(item.cover_path)}
                          alt=""
                          width={item.cover_width}
                          height={item.cover_height}
                          blurhash={item.cover_blurhash}
                          fallbackAspect={1}
                          sizes="48px"
                        />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-body-strong text-ink">
                          {item.title}
                        </span>
                        <span className="block truncate text-caption text-ink-3">
                          {item.brand ? `${item.brand} · ` : ''}@{item.username}
                        </span>
                      </span>
                      <span className="tabular shrink-0 text-caption text-ink-3">
                        {compactCount(item.like_count)} ♥
                      </span>
                    </Link>
                  );
                })}
              </Section>
            ) : null}

            {show('tags') && results.tags.length > 0 ? (
              <Section title="Tags" count={results.tags.length}>
                <ChipGroup className="px-3">
                  {results.tags.map((tag) => {
                    const index = nextIndex();
                    return (
                      <Link
                        key={tag.slug}
                        id={`tag:${tag.slug}`}
                        role="option"
                        aria-selected={index === active}
                        ref={(node) => {
                          rowRefs.current[index] = node;
                        }}
                        href={`/search?q=${encodeURIComponent(tag.name)}`}
                        onClick={(event) => {
                          event.preventDefault();
                          setQuery(tag.name);
                        }}
                        onMouseEnter={() => setActive(indexOf(`tag:${tag.slug}`))}
                        className={cn(
                          'focus-ring inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-label',
                          'transition-colors dur-fast ease-standard',
                          index === active
                            ? 'border-accent bg-accent-subtle text-accent'
                            : 'border-line bg-surface-2 text-ink-2 hover:text-ink',
                        )}
                      >
                        #{tag.name}
                        <span className="tabular text-micro text-ink-3">
                          {compactCount(tag.use_count)}
                        </span>
                      </Link>
                    );
                  })}
                </ChipGroup>
              </Section>
            ) : null}
          </div>
        )}
      </div>
    </div>
  );
}

function Section({
  title,
  count,
  children,
}: {
  title: string;
  count: number;
  children: React.ReactNode;
}) {
  return (
    <section>
      <h2 className="px-3 text-label uppercase tracking-widest text-ink-3">
        {title} <span className="tabular">({count})</span>
      </h2>
      <div className="mt-2 flex flex-col gap-0.5">{children}</div>
    </section>
  );
}

/** Never a blank page: popular tags plus collectors worth following. */
function ZeroState({
  tags,
  collectors,
  onPick,
}: {
  tags: Array<{ id: string; name: string; slug: string; use_count: number }>;
  collectors: ProfileRow[];
  onPick: (value: string) => void;
}) {
  return (
    <div className="flex flex-col gap-10 py-6">
      {tags.length > 0 ? (
        <section>
          <h2 className="text-label uppercase tracking-widest text-ink-3">What people tag</h2>
          <ChipGroup className="mt-3">
            {tags.map((tag) => (
              <Chip key={tag.id} onClick={() => onPick(tag.name)} icon="search">
                #{tag.name}
                <span className="tabular ml-1 text-micro text-ink-3">
                  {compactCount(tag.use_count)}
                </span>
              </Chip>
            ))}
          </ChipGroup>
        </section>
      ) : null}

      {collectors.length > 0 ? (
        <section>
          <h2 className="text-label uppercase tracking-widest text-ink-3">
            Collectors worth a look
          </h2>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            {collectors.map((person) => (
              <Link
                key={person.id}
                href={profileHref(person.username)}
                className="focus-ring flex items-center gap-3 rounded-lg border border-line-subtle bg-surface-1 p-3 transition-colors dur-fast hover:bg-surface-2"
              >
                <Avatar
                  path={person.avatar_path}
                  name={person.display_name}
                  username={person.username}
                  verified={person.is_verified}
                />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-body-strong text-ink">
                    {person.display_name}
                  </span>
                  <span className="block truncate text-caption text-ink-3">
                    {compactCount(person.collection_count)}{' '}
                    {plural(person.collection_count, 'collection')} ·{' '}
                    {compactCount(person.follower_count)}{' '}
                    {plural(person.follower_count, 'follower')}
                  </span>
                </span>
              </Link>
            ))}
          </div>
        </section>
      ) : null}

      {tags.length === 0 && collectors.length === 0 ? (
        <EmptyState
          icon="search"
          title="Start typing"
          description="Search finds people, collections, items and tags at once."
        />
      ) : null}
    </div>
  );
}
