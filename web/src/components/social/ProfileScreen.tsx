'use client';

import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { PulseCard } from '@/app/(app)/pulse/_components/PulseCard';
import { userPosts } from '@/lib/api';
import { cn } from '@/lib/cn';
import { calendarDate, compactCount, plural } from '@/lib/format';
import { bannerUrl } from '@/lib/storage';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonGrid, SkeletonRow } from '@/components/ui/Skeleton';
import { useRealtimeProfile } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { pulseEntryKey, type ProfileRow, type PulseEntry } from '@/lib/types';
import { EntityCard } from './EntityCard';
import { FollowButton } from './FollowButton';
import { ProfileEditor } from './ProfileEditor';
import { MessageButton, UserActions } from './UserActions';
import {
  listCollectionSummaries,
  listInteractedSummaries,
  listItemSummaries,
  type EntitySummary,
  type RelationshipState,
} from './queries';

/**
 * The profile: banner, avatar, serif display name, bio, live counts, and five
 * tabs — collections, items, posts, likes and saves. The entity tabs share one
 * card component; Posts renders `user_posts` pulse envelopes (migration 0021)
 * through the same `PulseCard` the stream uses, so a post can never look
 * different on a profile than it does in Pulse.
 *
 * The header is server-rendered for SEO and first paint; this component takes
 * over for the tabs, the optimistic follow and the overflow actions.
 */

const TABS = ['collections', 'posts', 'items', 'likes', 'saves'] as const;
export type ProfileTab = (typeof TABS)[number];

const TAB_LABELS: Record<ProfileTab, string> = {
  collections: 'Collections',
  items: 'Items',
  posts: 'Posts',
  likes: 'Likes',
  saves: 'Saves',
};

const PAGE_SIZE = 24;
/** `user_posts` page size — extra-row has_more contract (migration 0021). */
const POSTS_PAGE_SIZE = 20;

export interface ProfileScreenProps {
  profile: ProfileRow;
  relationship: RelationshipState;
  /** First page of the default tab, rendered on the server. */
  initialTab: ProfileTab;
  initialSummaries: EntitySummary[];
  /** First `user_posts` page (raw, may hold the extra has_more row) when the
   *  Posts tab was deep-linked; null lets the client fetch on first select. */
  initialPosts?: PulseEntry[] | null;
}

function isProfileTab(value: string | null): value is ProfileTab {
  return value !== null && (TABS as readonly string[]).includes(value);
}

export function ProfileScreen({
  profile,
  relationship,
  initialTab,
  initialSummaries,
  initialPosts = null,
}: ProfileScreenProps) {
  const { supabase, user } = useSession();
  const isSelf = user?.id === profile.id;

  const [tab, setTab] = useState<ProfileTab>(initialTab);
  const [cache, setCache] = useState<Partial<Record<ProfileTab, EntitySummary[]>>>({
    [initialTab]: initialSummaries,
  });
  const [exhausted, setExhausted] = useState<Partial<Record<ProfileTab, boolean>>>({
    [initialTab]: initialSummaries.length < PAGE_SIZE,
  });
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);
  const [editing, setEditing] = useState(false);

  // The Posts tab is envelope-shaped, not summary-shaped — its own state.
  // Extra-row contract: render POSTS_PAGE_SIZE, the surplus row means more.
  const [posts, setPosts] = useState<PulseEntry[] | null>(() =>
    initialPosts === null ? null : initialPosts.slice(0, POSTS_PAGE_SIZE),
  );
  const [postsHasMore, setPostsHasMore] = useState(
    () => initialPosts !== null && initialPosts.length > POSTS_PAGE_SIZE,
  );
  const [postsLoading, setPostsLoading] = useState(false);
  const [postsFailure, setPostsFailure] = useState<unknown>(null);

  // Follower count stays live while you sit on the page.
  useRealtimeProfile(profile.id);

  const load = useCallback(
    async (target: ProfileTab, offset: number) => {
      setLoading(true);
      setFailure(null);
      try {
        const params = { limit: PAGE_SIZE, offset };
        const page =
          target === 'collections'
            ? await listCollectionSummaries(supabase, profile.id, params)
            : target === 'items'
              ? await listItemSummaries(supabase, profile.id, params)
              : await listInteractedSummaries(
                  supabase,
                  target === 'likes' ? 'likes' : 'saves',
                  profile.id,
                  params,
                );

        setCache((current) => ({
          ...current,
          [target]: offset === 0 ? page : [...(current[target] ?? []), ...page],
        }));
        setExhausted((current) => ({ ...current, [target]: page.length < PAGE_SIZE }));
      } catch (error) {
        setFailure(error);
      } finally {
        setLoading(false);
      }
    },
    [profile.id, supabase],
  );

  /** First page (no `before`) or the next one (`before` = min sort_at loaded). */
  const loadPosts = useCallback(
    async (before?: string) => {
      setPostsLoading(true);
      setPostsFailure(null);
      try {
        const rows = await userPosts(supabase, profile.id, {
          limit: POSTS_PAGE_SIZE,
          ...(before === undefined ? {} : { before }),
        });
        const hasMore = rows.length > POSTS_PAGE_SIZE;
        const rendered = hasMore ? rows.slice(0, POSTS_PAGE_SIZE) : rows;
        setPosts((current) => {
          const existing = before === undefined ? [] : (current ?? []);
          const known = new Set(existing.map(pulseEntryKey));
          return [...existing, ...rendered.filter((row) => !known.has(pulseEntryKey(row)))];
        });
        setPostsHasMore(hasMore);
      } catch (error) {
        setPostsFailure(error);
      } finally {
        setPostsLoading(false);
      }
    },
    [profile.id, supabase],
  );

  const requested = useRef(new Set<ProfileTab>([initialTab]));

  const select = useCallback(
    (next: ProfileTab) => {
      setTab(next);
      // Shareable without a navigation: the tab is a view, not a page.
      if (typeof window !== 'undefined') {
        const url = new URL(window.location.href);
        if (next === 'collections') url.searchParams.delete('tab');
        else url.searchParams.set('tab', next);
        window.history.replaceState(null, '', url.toString());
      }
      if (!requested.current.has(next)) {
        requested.current.add(next);
        if (next === 'posts') void loadPosts();
        else void load(next, 0);
      }
    },
    [load, loadPosts],
  );

  // Honour ?tab= on a cold deep link.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const requestedTab = new URL(window.location.href).searchParams.get('tab');
    if (isProfileTab(requestedTab) && requestedTab !== initialTab) select(requestedTab);
    // Deep-link resolution runs once, on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const summaries = cache[tab] ?? [];
  const done = exhausted[tab] ?? false;

  const emptyCopy: Record<ProfileTab, { title: string; description: string }> = {
    collections: {
      title: isSelf ? 'No collections yet' : 'Nothing public here yet',
      description: isSelf
        ? 'A collection is a shelf. Start one, then group it into subcollections and fill it with things.'
        : `${profile.display_name} has not published a collection you can see.`,
    },
    items: {
      title: isSelf ? 'No items yet' : 'No items to show',
      description: isSelf
        ? 'Items are the things themselves — one item, one to many photos.'
        : `${profile.display_name} has not published an item you can see.`,
    },
    posts: {
      title: isSelf ? 'Nothing said yet' : 'No posts yet',
      description: isSelf
        ? 'Posts, quotes and reposts you make in Pulse land here.'
        : `${profile.display_name} has not posted anything you can see.`,
    },
    likes: {
      title: isSelf ? 'Nothing liked yet' : 'Likes are private here',
      description: isSelf
        ? 'Everything you like lands here, whatever level of the hierarchy it lives at.'
        : `${profile.display_name}'s likes are not visible to you.`,
    },
    saves: {
      title: isSelf ? 'Nothing saved yet' : 'Saves are private here',
      description: isSelf
        ? 'Saving is the brand action — it is how a collection of collections gets built.'
        : `${profile.display_name}'s saves are not visible to you.`,
    },
  };

  const banner = bannerUrl(profile.banner_path);

  return (
    <div className="pb-16">
      <div className="relative">
        <div
          className={cn(
            'aspect-[3/1] w-full overflow-hidden bg-surface-2 sm:aspect-[4/1]',
            !banner && 'border-b border-line-subtle',
          )}
        >
          {banner ? (
            /* eslint-disable-next-line @next/next/no-img-element -- banners come
               from arbitrary storage hosts; see BlurhashImage for the rationale. */
            <img
              src={banner}
              alt={`${profile.display_name}'s banner`}
              className="size-full object-cover"
            />
          ) : null}
        </div>
      </div>

      <header className="content-max px-4 sm:px-6">
        <div className="-mt-12 flex flex-wrap items-end gap-4 sm:-mt-14">
          <span className="rounded-full ring-4 ring-base">
            <Avatar
              path={profile.avatar_path}
              name={profile.display_name}
              username={profile.username}
              size="2xl"
              verified={profile.is_verified}
            />
          </span>

          <div className="flex flex-1 flex-wrap items-center justify-end gap-2 pb-1">
            {isSelf ? (
              <Button variant="secondary" iconLeft="sliders" onClick={() => setEditing(true)}>
                Edit profile
              </Button>
            ) : (
              <>
                <MessageButton userId={profile.id} displayName={profile.display_name} />
                <FollowButton
                  userId={profile.id}
                  followerCount={profile.follower_count}
                  following={relationship.following}
                />
              </>
            )}
            <UserActions
              userId={profile.id}
              username={profile.username}
              displayName={profile.display_name}
              relationship={relationship}
              extraItems={
                isSelf
                  ? [
                      {
                        key: 'edit',
                        label: 'Edit profile',
                        icon: 'sliders',
                        onSelect: () => setEditing(true),
                      },
                    ]
                  : []
              }
            />
          </div>
        </div>

        <div className="mt-4 flex flex-col gap-3">
          <div className="min-w-0">
            <div className="flex min-w-0 flex-wrap items-center gap-2">
              <h1 className="min-w-0 break-words font-display text-title1 leading-tight text-ink sm:text-display2">
                {profile.display_name}
              </h1>
            {profile.is_verified ? (
              <span className="text-accent" title="Verified collector">
                <Icon name="verified" size="lg" title="Verified collector" />
              </span>
            ) : null}
              {profile.account_visibility !== 'public' ? (
              <span className="inline-flex items-center gap-1 rounded-full border border-line bg-surface-2 px-2 py-0.5 text-micro text-ink-2">
                <Icon name="lock" size="xs" />
                {profile.account_visibility === 'private' ? 'Private' : 'Followers only'}
              </span>
              ) : null}
            </div>
          </div>

          <p className="text-callout text-ink-3">@{profile.username}</p>

          {profile.bio ? (
            <p className="readable-max whitespace-pre-line text-body text-ink-2 md:mx-0">
              {profile.bio}
            </p>
          ) : null}

          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-caption text-ink-3">
            {profile.location ? (
              <span className="inline-flex items-center gap-1">
                <Icon name="compass" size="xs" />
                {profile.location}
              </span>
            ) : null}
            {profile.website ? (
              <a
                href={profile.website}
                target="_blank"
                rel="noopener noreferrer nofollow"
                className="focus-ring inline-flex items-center gap-1 rounded-sm text-accent hover:underline"
              >
                <Icon name="link" size="xs" />
                {profile.website.replace(/^https?:\/\//, '')}
              </a>
            ) : null}
            <span className="inline-flex items-center gap-1">
              <Icon name="user" size="xs" />
              Collecting since {calendarDate(profile.created_at)}
            </span>
          </div>

          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
            <Stat label={plural(profile.collection_count, 'Collection')} value={profile.collection_count} />
            <Stat label={plural(profile.item_count, 'Item')} value={profile.item_count} />
            <Stat label={plural(profile.follower_count, 'Follower')} value={profile.follower_count} />
            <Stat label="Following" value={profile.following_count} />
          </dl>
        </div>

        <div
          role="tablist"
          aria-label="Profile sections"
          className="-mx-4 mt-6 flex snap-x gap-1 overflow-x-auto border-b border-line-subtle px-4 sm:mx-0 sm:px-0"
        >
          {TABS.map((value) => {
            const active = tab === value;
            return (
              <button
                key={value}
                type="button"
                role="tab"
                id={`profile-tab-${value}`}
                aria-selected={active}
                aria-controls={`profile-panel-${value}`}
                tabIndex={active ? 0 : -1}
                onClick={() => select(value)}
                onKeyDown={(event) => {
                  const index = TABS.indexOf(value);
                  if (event.key === 'ArrowRight') {
                    event.preventDefault();
                    select(TABS[(index + 1) % TABS.length] as ProfileTab);
                  } else if (event.key === 'ArrowLeft') {
                    event.preventDefault();
                    select(TABS[(index - 1 + TABS.length) % TABS.length] as ProfileTab);
                  }
                }}
                className={cn(
                  'focus-ring -mb-px shrink-0 snap-start whitespace-nowrap border-b-2 px-4 py-3 text-body-strong',
                  'transition-colors dur-fast ease-standard',
                  active
                    ? 'border-accent text-ink'
                    : 'border-transparent text-ink-3 hover:text-ink',
                )}
              >
                {TAB_LABELS[value]}
              </button>
            );
          })}
        </div>
      </header>

      <section
        role="tabpanel"
        id={`profile-panel-${tab}`}
        aria-labelledby={`profile-tab-${tab}`}
        className="content-max px-4 pt-6 sm:px-6"
      >
        {tab === 'posts' ? (
          postsFailure ? (
            <ErrorState error={postsFailure} onRetry={() => void loadPosts()} />
          ) : posts === null ? (
            <div className="mx-auto flex w-full max-w-160 flex-col gap-4">
              <SkeletonRow />
              <SkeletonRow />
            </div>
          ) : posts.length === 0 ? (
            <EmptyState
              icon="activity"
              title={emptyCopy.posts.title}
              description={emptyCopy.posts.description}
            />
          ) : (
            <div className="mx-auto w-full max-w-160">
              <ol className="border-t border-line-subtle">
                {posts.map((entry, index) => (
                  <li key={pulseEntryKey(entry)}>
                    <PulseCard entry={entry} enterIndex={index % POSTS_PAGE_SIZE} />
                  </li>
                ))}
              </ol>

              {postsHasMore ? (
                <div className="mt-8 flex justify-center">
                  <Button
                    variant="secondary"
                    loading={postsLoading}
                    onClick={() => {
                      // `user_posts` pages on p_before = min(sort_at) loaded.
                      let before: string | undefined;
                      for (const row of posts) {
                        if (before === undefined || row.sort_at < before) before = row.sort_at;
                      }
                      void loadPosts(before);
                    }}
                  >
                    Load more
                  </Button>
                </div>
              ) : null}
            </div>
          )
        ) : failure ? (
          <ErrorState error={failure} onRetry={() => void load(tab, 0)} />
        ) : loading && summaries.length === 0 ? (
          <SkeletonGrid count={9} />
        ) : summaries.length === 0 ? (
          <EmptyState
            icon={tab === 'collections' ? 'grid' : tab === 'items' ? 'image' : tab === 'likes' ? 'heart' : 'bookmark'}
            title={emptyCopy[tab].title}
            description={emptyCopy[tab].description}
            action={
              isSelf && (tab === 'collections' || tab === 'items') ? (
                <Link
                  href="/create"
                  className="focus-ring k-pressable inline-flex items-center gap-2 rounded-md bg-accent px-5 py-3 text-body-strong text-ink-on-accent"
                >
                  <Icon name="plus" size="md" />
                  Start a collection
                </Link>
              ) : null
            }
          />
        ) : (
          <>
            <div className="k-masonry">
              {summaries.map((summary, index) => (
                <EntityCard
                  key={`${summary.type}:${summary.id}`}
                  summary={summary}
                  priority={index < 4}
                />
              ))}
            </div>

            {!done ? (
              <div className="mt-8 flex justify-center">
                <Button
                  variant="secondary"
                  loading={loading}
                  onClick={() => void load(tab, summaries.length)}
                >
                  Load more
                </Button>
              </div>
            ) : null}
          </>
        )}
      </section>

      {isSelf ? (
        <ProfileEditor open={editing} onClose={() => setEditing(false)} profile={profile} />
      ) : null}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="min-w-0">
      <dt className="sr-only">{label}</dt>
      <dd className="tabular text-title3 text-ink">{compactCount(value)}</dd>
      <span aria-hidden className="block truncate text-caption text-ink-3">
        {label}
      </span>
    </div>
  );
}
