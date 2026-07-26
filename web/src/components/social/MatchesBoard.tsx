'use client';

import Link from 'next/link';
import { useCallback, useState } from 'react';
import { getMatches } from '@/lib/api';
import { cn } from '@/lib/cn';
import { compactCount, plural } from '@/lib/format';
import { collectionHref, profileHref, routes } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { MatchPerson } from '@/lib/types';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Button, ButtonLink } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Skeleton } from '@/components/ui/Skeleton';
import { useSession } from '@/providers/session-provider';
import { FollowButton } from './FollowButton';
import { MessageButton } from './UserActions';
import { BAND_LABELS, MatchRing, matchBand } from './MatchRing';

/**
 * "Collectors like you" — ranked by real overlap in what you both keep, not by
 * who shouted loudest today.
 *
 * `get_matches` recomputes taste server-side when the cache is stale, so the
 * refresh button is a genuine recompute rather than a re-render.
 */
export interface MatchesBoardProps {
  initialMatches: MatchPerson[];
}

export function MatchesBoard({ initialMatches }: MatchesBoardProps) {
  const { supabase } = useSession();
  const [matches, setMatches] = useState(initialMatches);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setFailure(null);
    try {
      setMatches(await getMatches(supabase, 24));
    } catch (error) {
      setFailure(error);
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  return (
    <div className="content-max px-4 py-8 sm:px-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-display2 text-ink">Collectors like you</h1>
          <p className="mt-1 readable-max text-callout text-ink-2 md:mx-0">
            Ranked by how much your taste actually overlaps — shared tags, shared
            subjects, shared obsessions.
          </p>
        </div>
        <Button variant="secondary" iconLeft="repost" loading={loading} onClick={() => void refresh()}>
          Recompute
        </Button>
      </header>

      {failure ? (
        <ErrorState error={failure} onRetry={() => void refresh()} />
      ) : loading && matches.length === 0 ? (
        <div className="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }, (_, index) => (
            <div key={index} className="rounded-xl border border-line-subtle bg-surface-1 p-5">
              <div className="flex items-center gap-3">
                <Skeleton shape="circle" className="size-14" />
                <div className="flex-1">
                  <Skeleton shape="text" className="w-1/2" />
                  <Skeleton shape="text" className="mt-2 w-1/3" />
                </div>
                <Skeleton shape="circle" className="size-14" />
              </div>
              <Skeleton className="mt-4 h-20 w-full" />
            </div>
          ))}
        </div>
      ) : matches.length === 0 ? (
        <EmptyState
          icon="users"
          title="No matches yet"
          description="Matching reads what you save, like and tag. Add a few things to a collection and the overlap appears within a day."
          action={
            <ButtonLink href={routes.create} iconLeft="plus">
              Start collecting
            </ButtonLink>
          }
        />
      ) : (
        <div className="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {matches.map((person) => (
            <MatchCard key={person.id} person={person} />
          ))}
        </div>
      )}
    </div>
  );
}

function MatchCard({ person }: { person: MatchPerson }) {
  const band = matchBand(person.score);
  const tags = person.shared_tags ?? [];
  const top = person.top_collections.slice(0, 3);

  return (
    <article
      className={cn(
        'flex flex-col gap-4 rounded-xl border border-line-subtle bg-surface-1 p-5',
        'transition-colors dur-fast ease-standard hover:border-line',
      )}
    >
      <div className="flex items-start gap-3">
        <Link
          href={profileHref(person.username)}
          className="focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-md"
        >
          <Avatar
            path={person.avatar_path}
            name={person.display_name}
            username={person.username}
            size="lg"
            verified={person.is_verified}
          />
          <span className="min-w-0">
            <span className="block truncate font-display text-title2 text-ink">
              {person.display_name}
            </span>
            <span className="block truncate text-caption text-ink-3">@{person.username}</span>
          </span>
        </Link>

        <span className="flex flex-col items-center gap-1">
          <MatchRing score={person.score} />
          <span className="whitespace-nowrap text-micro text-ink-3">{BAND_LABELS[band]}</span>
        </span>
      </div>

      {person.bio ? (
        <p className="line-clamp-2 text-caption text-ink-2">{person.bio}</p>
      ) : null}

      {tags.length > 0 ? (
        <ChipGroup label="Shared tags">
          {tags.slice(0, 6).map((tag) => (
            <Chip key={tag} href={`/search?q=${encodeURIComponent(tag)}`} tone="neutral">
              #{tag}
            </Chip>
          ))}
        </ChipGroup>
      ) : (
        <p className="text-caption text-ink-3">
          No shared tags yet — the overlap is in what you both keep, not what you both label.
        </p>
      )}

      {top.length > 0 ? (
        <div className="grid grid-cols-3 gap-2">
          {top.map((collection) => (
            <Link
              key={collection.id}
              href={collectionHref(collection.id)}
              className="focus-ring group/tile min-w-0 rounded-md"
              title={collection.name}
            >
              <span className="block overflow-hidden rounded-md border border-line-subtle">
                <BlurhashImage
                  src={mediaUrl(collection.cover_path)}
                  alt={collection.name}
                  blurhash={collection.cover_blurhash}
                  fallbackAspect={1}
                  sizes="(max-width: 768px) 30vw, 120px"
                />
              </span>
              <span className="mt-1 block truncate text-micro text-ink-3 group-hover/tile:text-ink">
                {collection.name}
              </span>
            </Link>
          ))}
        </div>
      ) : null}

      <div className="flex items-center gap-3 text-caption text-ink-3">
        <span className="tabular">
          {compactCount(person.collection_count)}{' '}
          {plural(person.collection_count, 'collection')}
        </span>
        <span aria-hidden>·</span>
        <span className="tabular">
          {compactCount(person.item_count)} {plural(person.item_count, 'item')}
        </span>
        <span aria-hidden>·</span>
        <span className="tabular">
          {compactCount(person.follower_count)} {plural(person.follower_count, 'follower')}
        </span>
      </div>

      <div className="flex items-center gap-2">
        <FollowButton
          userId={person.id}
          followerCount={person.follower_count}
          following={person.viewer_follows}
          className="flex-1"
        />
        <MessageButton userId={person.id} displayName={person.display_name} />
      </div>
    </article>
  );
}
