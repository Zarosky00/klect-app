'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PulseCard } from '@/app/(app)/pulse/_components/PulseCard';
import { PostTargetCard } from '@/components/thread/post-bits';
import { ActionBar } from '@/components/ui/ActionBar';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonGrid, SkeletonRow } from '@/components/ui/Skeleton';
import {
  myProfileReactions,
  profileDiscussionActivity,
  profilePulseActivity,
  deleteComment,
  deletePost,
  toggleRepost,
} from '@/lib/api';
import { cn } from '@/lib/cn';
import { isSurfaceEntityType } from '@/lib/entities';
import { calendarDate, compactCount, plural, shortTimeAgo } from '@/lib/format';
import { closeupHref, postHref } from '@/lib/routes';
import { emitSocialActivityMutation, subscribeSocialActivity } from '@/lib/social-activity';
import { bannerUrl } from '@/lib/storage';
import type {
  CursorPage,
  ProfileDiscussionItem,
  ProfilePulseView,
  ProfileReactionAction,
  ProfileReactionItem,
  ProfileRow,
  ProfileSurface,
  PulseEntry,
} from '@/lib/types';
import { pulseEntryKey } from '@/lib/types';
import { useRealtimeProfile } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { EntityCard } from './EntityCard';
import { FollowButton } from './FollowButton';
import { ProfileEditor } from './ProfileEditor';
import { OverflowMenu } from './OverflowMenu';
import {
  listCollectionSummaries,
  listItemSummaries,
  type EntitySummary,
  type RelationshipState,
} from './queries';
import { MessageButton, UserActions } from './UserActions';

export type ProfileMode = 'surf' | 'pulse' | 'activity';
export type ProfileSurfView = 'collections' | 'items';
export type ProfilePulseSection = 'posts' | 'replies' | 'media';

export interface ProfileInitialState {
  mode: ProfileMode;
  surfView: ProfileSurfView;
  pulseSection: ProfilePulseSection;
  postView: Exclude<ProfilePulseView, 'media'>;
  discussionSurface: ProfileSurface;
  activityAction: ProfileReactionAction;
  reactionSurface: 'surf' | 'pulse';
  summaries: EntitySummary[];
  pulsePage: CursorPage<PulseEntry> | null;
  discussionPage: CursorPage<ProfileDiscussionItem> | null;
  reactionPage: CursorPage<ProfileReactionItem> | null;
}

export interface ProfileScreenProps {
  profile: ProfileRow;
  relationship: RelationshipState;
  initial: ProfileInitialState;
}

const PAGE_SIZE = 24;
const EMPTY_PAGE = <T,>(): CursorPage<T> => ({ items: [], has_more: false, next_cursor: null });

function selectionKey(state: Pick<ProfileInitialState, 'mode' | 'surfView' | 'pulseSection' | 'postView' | 'discussionSurface' | 'activityAction' | 'reactionSurface'>): string {
  if (state.mode === 'surf') return `surf:${state.surfView}`;
  if (state.mode === 'activity') return `activity:${state.activityAction}:${state.reactionSurface}`;
  if (state.pulseSection === 'replies') return `pulse:replies:${state.discussionSurface}`;
  return `pulse:${state.pulseSection}:${state.pulseSection === 'media' ? 'media' : state.postView}`;
}

function cursorItemKey(item: ProfileReactionItem): string {
  return `${item.target_type}:${item.target_id}:${item.acted_at}`;
}

function reactionSummary(item: ProfileReactionItem): EntitySummary | null {
  const target = item.target;
  if (!target || target.unavailable || !isSurfaceEntityType(target.type)) return null;
  const first = target.media?.[0];
  return {
    type: target.type,
    id: target.id,
    ownerId: target.author?.id ?? '',
    title: target.title ?? 'Untitled',
    subtitle: target.subtitle ?? null,
    coverPath: first?.storage_path ?? target.cover_path ?? null,
    coverBlurhash: first?.blurhash ?? target.cover_blurhash ?? null,
    width: first?.width ?? target.cover_width ?? null,
    height: first?.height ?? target.cover_height ?? null,
    accentColor: null,
    likeCount: target.like_count ?? 0,
    saveCount: 0,
    repostCount: 0,
    commentCount: 0,
    viewCount: 0,
    childCount: target.child_count ?? 0,
    createdAt: target.created_at ?? item.acted_at,
    visibility: null,
  };
}

export function ProfileScreen({ profile, relationship, initial }: ProfileScreenProps) {
  const { supabase, user } = useSession();
  const isSelf = user?.id === profile.id;
  const [mode, setMode] = useState<ProfileMode>(initial.mode);
  const [surfView, setSurfView] = useState(initial.surfView);
  const [pulseSection, setPulseSection] = useState(initial.pulseSection);
  const [postView, setPostView] = useState(initial.postView);
  const [discussionSurface, setDiscussionSurface] = useState(initial.discussionSurface);
  const [activityAction, setActivityAction] = useState(initial.activityAction);
  const [reactionSurface, setReactionSurface] = useState(initial.reactionSurface);
  const [summaries, setSummaries] = useState(initial.summaries);
  const [pulsePage, setPulsePage] = useState(initial.pulsePage ?? EMPTY_PAGE<PulseEntry>());
  const [discussionPage, setDiscussionPage] = useState(
    initial.discussionPage ?? EMPTY_PAGE<ProfileDiscussionItem>(),
  );
  const [reactionPage, setReactionPage] = useState(
    initial.reactionPage ?? EMPTY_PAGE<ProfileReactionItem>(),
  );
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);
  const [editing, setEditing] = useState(false);
  const [surfDone, setSurfDone] = useState(initial.summaries.length < PAGE_SIZE);
  const request = useRef(0);
  const initialKey = useRef(selectionKey(initial));

  useRealtimeProfile(profile.id);

  const currentSelection = useMemo(
    () => ({ mode, surfView, pulseSection, postView, discussionSurface, activityAction, reactionSurface }),
    [activityAction, discussionSurface, mode, postView, pulseSection, reactionSurface, surfView],
  );
  const currentKey = selectionKey(currentSelection);

  const syncUrl = useCallback((next: typeof currentSelection) => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    url.searchParams.set('mode', next.mode);
    url.searchParams.delete('tab');
    if (next.mode === 'surf') {
      url.searchParams.set('view', next.surfView);
      url.searchParams.delete('filter');
      url.searchParams.delete('surface');
    } else if (next.mode === 'pulse') {
      url.searchParams.set('view', next.pulseSection);
      if (next.pulseSection === 'posts') url.searchParams.set('filter', next.postView);
      else url.searchParams.delete('filter');
      if (next.pulseSection === 'replies') url.searchParams.set('surface', next.discussionSurface);
      else url.searchParams.delete('surface');
    } else {
      url.searchParams.set('view', next.activityAction === 'like' ? 'likes' : 'saves');
      url.searchParams.set('surface', next.reactionSurface);
      url.searchParams.delete('filter');
    }
    window.history.replaceState(null, '', url.toString());
  }, []);

  const load = useCallback(
    async (append = false) => {
      const requestId = ++request.current;
      setLoading(true);
      setFailure(null);
      try {
        if (mode === 'surf') {
          const offset = append ? summaries.length : 0;
          const rows = surfView === 'collections'
            ? await listCollectionSummaries(supabase, profile.id, { limit: PAGE_SIZE, offset })
            : await listItemSummaries(supabase, profile.id, { limit: PAGE_SIZE, offset });
          if (request.current !== requestId) return;
          setSummaries((current) => append ? [...current, ...rows] : rows);
          setSurfDone(rows.length < PAGE_SIZE);
        } else if (mode === 'pulse' && pulseSection === 'replies') {
          const page = await profileDiscussionActivity(supabase, profile.id, discussionSurface, {
            limit: 20,
            cursor: append ? discussionPage.next_cursor : null,
          });
          if (request.current !== requestId) return;
          setDiscussionPage((current) => ({
            ...page,
            items: append ? dedupe([...current.items, ...page.items], (item) => item.id) : page.items,
          }));
        } else if (mode === 'pulse') {
          const view: ProfilePulseView = pulseSection === 'media' ? 'media' : postView;
          const page = await profilePulseActivity(supabase, profile.id, view, {
            limit: 20,
            cursor: append ? pulsePage.next_cursor : null,
          });
          if (request.current !== requestId) return;
          setPulsePage((current) => ({
            ...page,
            items: append
              ? dedupe([...current.items, ...page.items], pulseEntryKey)
              : page.items,
          }));
        } else if (isSelf) {
          const page = await myProfileReactions(supabase, activityAction, reactionSurface, {
            limit: PAGE_SIZE,
            cursor: append ? reactionPage.next_cursor : null,
          });
          if (request.current !== requestId) return;
          setReactionPage((current) => ({
            ...page,
            items: append
              ? dedupe([...current.items, ...page.items], cursorItemKey)
              : page.items,
          }));
        }
      } catch (thrown) {
        if (request.current === requestId) setFailure(thrown);
      } finally {
        if (request.current === requestId) setLoading(false);
      }
    }, [activityAction, discussionPage.next_cursor, discussionSurface, isSelf, mode, postView, profile.id, pulsePage.next_cursor, pulseSection, reactionPage.next_cursor, reactionSurface, summaries.length, supabase, surfView],
  );

  useEffect(() => {
    syncUrl(currentSelection);
    if (initialKey.current === currentKey) {
      initialKey.current = '';
      return;
    }
    void load(false);
    // load changes as cursors change; selection alone initiates a fresh head.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentKey, syncUrl]);

  useEffect(
    () => subscribeSocialActivity((mutation) => {
      if (!isSelf || mutation.actorId !== profile.id) return;
      const affectsCurrent =
        (mode === 'activity' && (mutation.kind === 'like' || mutation.kind === 'save')) ||
        (mode === 'pulse' && ['post', 'quote', 'repost', 'comment', 'delete'].includes(mutation.kind));
      if (affectsCurrent) void load(false);
    }),
    [isSelf, load, mode, profile.id],
  );

  const changeMode = (next: ProfileMode) => {
    if (next === 'activity' && !isSelf) return;
    setMode(next);
  };

  const empty = emptyCopy(mode, surfView, pulseSection, activityAction, isSelf, profile.display_name);
  const banner = bannerUrl(profile.banner_path);
  const surfReactionSummaries = reactionPage.items
    .map(reactionSummary)
    .filter((summary): summary is EntitySummary => summary !== null);

  return (
    <div className="pb-16">
      <div className="relative">
        <div className={cn('aspect-[3/1] w-full overflow-hidden bg-surface-2 sm:aspect-[4/1]', !banner && 'border-b border-line-subtle')}>
          {banner ? (
            // Profile banners can use arbitrary user-configured storage hosts.
            // eslint-disable-next-line @next/next/no-img-element
            <img src={banner} alt={`${profile.display_name}'s banner`} className="size-full object-cover" />
          ) : null}
        </div>
      </div>

      <header className="content-max px-4 sm:px-6">
        <div className="-mt-12 flex flex-wrap items-end gap-4 sm:-mt-14">
          <span className="rounded-full ring-4 ring-base">
            <Avatar path={profile.avatar_path} name={profile.display_name} username={profile.username} size="2xl" verified={profile.is_verified} />
          </span>
          <div className="flex flex-1 flex-wrap items-center justify-end gap-2 pb-1">
            {isSelf ? (
              <Button variant="secondary" iconLeft="sliders" onClick={() => setEditing(true)}>Edit profile</Button>
            ) : (
              <>
                <MessageButton userId={profile.id} displayName={profile.display_name} />
                <FollowButton userId={profile.id} followerCount={profile.follower_count} following={relationship.following} />
              </>
            )}
            <UserActions userId={profile.id} username={profile.username} displayName={profile.display_name} relationship={relationship} />
          </div>
        </div>

        <div className="mt-4 flex flex-col gap-3">
          <div className="flex min-w-0 flex-wrap items-center gap-2">
            <h1 className="min-w-0 break-words font-display text-title1 leading-tight text-ink sm:text-display2">{profile.display_name}</h1>
            {profile.is_verified ? <span className="text-accent"><Icon name="verified" size="lg" title="Verified collector" /></span> : null}
            {profile.account_visibility !== 'public' ? <span className="inline-flex items-center gap-1 rounded-full border border-line bg-surface-2 px-2 py-0.5 text-micro text-ink-2"><Icon name="lock" size="xs" />{profile.account_visibility === 'private' ? 'Private' : 'Followers only'}</span> : null}
          </div>
          <p className="text-callout text-ink-3">@{profile.username}</p>
          {profile.bio ? <p className="readable-max whitespace-pre-line text-body text-ink-2">{profile.bio}</p> : null}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-caption text-ink-3">
            {profile.location ? <span className="inline-flex items-center gap-1"><Icon name="compass" size="xs" />{profile.location}</span> : null}
            {profile.website ? <a href={profile.website} target="_blank" rel="noopener noreferrer nofollow" className="focus-ring inline-flex items-center gap-1 rounded-sm text-accent hover:underline"><Icon name="link" size="xs" />{profile.website.replace(/^https?:\/\//, '')}</a> : null}
            <span className="inline-flex items-center gap-1"><Icon name="user" size="xs" />Collecting since {calendarDate(profile.created_at)}</span>
          </div>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
            <Stat label={plural(profile.collection_count, 'Collection')} value={profile.collection_count} />
            <Stat label={plural(profile.item_count, 'Item')} value={profile.item_count} />
            <Stat label={plural(profile.follower_count, 'Follower')} value={profile.follower_count} />
            <Stat label="Following" value={profile.following_count} />
          </dl>
        </div>

        <TabRail label="Profile modes" value={mode} values={isSelf ? ['surf', 'pulse', 'activity'] : ['surf', 'pulse']} labels={{ surf: 'Surf', pulse: 'Pulse', activity: 'Activity' }} onChange={changeMode} prominent />
      </header>

      <section className="content-max px-4 pt-5 sm:px-6">
        {mode === 'surf' ? (
          <TabRail label="Surf profile views" value={surfView} values={['collections', 'items']} labels={{ collections: 'Collections', items: 'Items' }} onChange={setSurfView} />
        ) : mode === 'pulse' ? (
          <>
            <TabRail label="Pulse profile views" value={pulseSection} values={['posts', 'replies', 'media']} labels={{ posts: 'Posts', replies: 'Replies', media: 'Media' }} onChange={setPulseSection} />
            {pulseSection === 'posts' ? <FilterChips value={postView} values={['all', 'originals', 'reposts', 'quotes']} labels={{ all: 'All', originals: 'Originals', reposts: 'Reposts', quotes: 'Quotes' }} onChange={setPostView} /> : null}
            {pulseSection === 'replies' ? <FilterChips value={discussionSurface} values={['all', 'surf', 'pulse']} labels={{ all: 'All', surf: 'Surf', pulse: 'Pulse' }} onChange={setDiscussionSurface} /> : null}
          </>
        ) : (
          <>
            <TabRail label="Private activity" value={activityAction} values={['like', 'save']} labels={{ like: 'Likes', save: 'Saves' }} onChange={setActivityAction} />
            <FilterChips value={reactionSurface} values={['surf', 'pulse']} labels={{ surf: 'Surf', pulse: 'Pulse' }} onChange={setReactionSurface} />
          </>
        )}

        <div className="mt-5" aria-live="polite">
          {failure ? <ErrorState error={failure} onRetry={() => void load(false)} /> : loading && contentCount(mode, pulseSection, summaries, pulsePage, discussionPage, reactionPage) === 0 ? (mode === 'surf' || (mode === 'activity' && reactionSurface === 'surf') ? <SkeletonGrid count={8} /> : <div className="mx-auto flex max-w-160 flex-col gap-4"><SkeletonRow /><SkeletonRow /></div>) : contentCount(mode, pulseSection, summaries, pulsePage, discussionPage, reactionPage) === 0 ? <EmptyState icon={mode === 'surf' ? 'grid' : mode === 'activity' ? 'heart' : 'activity'} title={empty.title} description={empty.description} /> : mode === 'surf' ? (
            <div className="k-masonry">{summaries.map((summary, index) => <EntityCard key={`${summary.type}:${summary.id}`} summary={summary} priority={index < 4} />)}</div>
          ) : mode === 'pulse' && pulseSection === 'replies' ? (
            <ol className="mx-auto max-w-160 divide-y divide-line-subtle border-y border-line-subtle">{discussionPage.items.map((item) => <DiscussionCard key={item.id} item={item} canManage={isSelf} onRemoved={() => setDiscussionPage((current) => ({ ...current, items: current.items.filter((candidate) => candidate.id !== item.id) }))} />)}</ol>
          ) : mode === 'pulse' ? (
            <ol className="mx-auto max-w-160 border-t border-line-subtle">{pulsePage.items.map((entry, index) => <ProfilePulseRow key={pulseEntryKey(entry)} entry={entry} enterIndex={index % 20} canManage={isSelf} onRemoved={() => setPulsePage((current) => ({ ...current, items: current.items.filter((candidate) => pulseEntryKey(candidate) !== pulseEntryKey(entry)) }))} />)}</ol>
          ) : reactionSurface === 'surf' ? (
            <div className="k-masonry">{surfReactionSummaries.map((summary, index) => <EntityCard key={`${summary.type}:${summary.id}`} summary={summary} priority={index < 4} />)}</div>
          ) : (
            <ol className="mx-auto max-w-160 divide-y divide-line-subtle border-y border-line-subtle">{reactionPage.items.map((item, index) => <li key={cursorItemKey(item)}>{item.entry ? <PulseCard entry={item.entry} enterIndex={index % 20} /> : item.target ? <div className="p-4 sm:p-6"><PostTargetCard target={item.target} /></div> : null}</li>)}</ol>
          )}

          {hasMore(mode, surfDone, pulseSection, pulsePage, discussionPage, reactionPage) ? <div className="mt-8 flex justify-center"><Button variant="secondary" loading={loading} onClick={() => void load(true)}>Load more</Button></div> : null}
        </div>
      </section>

      {isSelf ? <ProfileEditor open={editing} onClose={() => setEditing(false)} profile={profile} /> : null}
    </div>
  );
}

function ProfilePulseRow({ entry, enterIndex, canManage, onRemoved }: { entry: PulseEntry; enterIndex: number; canManage: boolean; onRemoved: () => void }) {
  const { supabase, user } = useSession();
  const { success, fromError } = useToast();
  const [confirming, setConfirming] = useState(false);
  const isRepost = entry.feed_kind === 'repost';
  const subject = entry.post_id
    ? { type: 'post' as const, id: entry.post_id }
    : entry.target_type && entry.target_id
      ? { type: entry.target_type, id: entry.target_id }
      : null;
  const href = subject
    ? subject.type === 'post'
      ? postHref(subject.id)
      : closeupHref(subject.type, subject.id)
    : null;

  const items = href && subject
    ? [
        { key: 'open', label: 'Open original', icon: 'arrow-left' as const, onSelect: () => window.location.assign(href) },
        { key: 'copy', label: 'Copy link', icon: 'link' as const, onSelect: () => void copyPath(href, success, fromError) },
        ...(isRepost
          ? [{
              key: 'undo',
              label: 'Undo repost',
              icon: 'repost' as const,
              onSelect: () => {
                void toggleRepost(supabase, subject.type, subject.id)
                  .then((result) => {
                    if (!result.active) onRemoved();
                    emitSocialActivityMutation({ kind: 'repost', type: subject.type, id: subject.id, actorId: user?.id });
                    success(result.active ? 'Repost restored' : 'Repost removed');
                  })
                  .catch(fromError);
              },
            }]
          : entry.post_id
            ? [{ key: 'delete', label: 'Delete post', icon: 'trash' as const, destructive: true, onSelect: () => setConfirming(true) }]
            : []),
      ]
    : [];

  return (
    <>
      <li className="relative">
        <PulseCard entry={entry} enterIndex={enterIndex} />
        {canManage && items.length > 0 ? (
          <OverflowMenu
            className="absolute right-3 top-3 z-raised"
            label={isRepost ? 'Manage repost' : 'Manage post'}
            items={items}
          />
        ) : null}
      </li>
      <ConfirmDialog
        open={confirming}
        onCancel={() => setConfirming(false)}
        title="Delete this post?"
        description="The post and its media will be removed from Pulse. This cannot be undone."
        confirmLabel="Delete"
        destructive
        onConfirm={async () => {
          if (!entry.post_id) return;
          try {
            const result = await deletePost(supabase, entry.post_id);
            if (result.deleted) onRemoved();
            emitSocialActivityMutation({ kind: 'delete', type: 'post', id: entry.post_id, actorId: user?.id });
            success('Post deleted');
            setConfirming(false);
          } catch (error) {
            fromError(error);
          }
        }}
      />
    </>
  );
}

function DiscussionCard({ item, canManage, onRemoved }: { item: ProfileDiscussionItem; canManage: boolean; onRemoved: () => void }) {
  const { supabase, user } = useSession();
  const { success, fromError } = useToast();
  const [confirming, setConfirming] = useState(false);
  const href = item.destination.type === 'post'
    ? postHref(item.destination.id)
    : closeupHref(item.destination.type, item.destination.id);
  const destination = `${href}?comment=${encodeURIComponent(item.destination.highlight_comment_id)}`;
  return (
    <>
    <li className="k-feed-enter flex gap-3 px-4 py-5 sm:px-6">
      <Avatar path={item.author?.avatar_path} name={item.author?.display_name} username={item.author?.username} verified={item.author?.is_verified ?? false} size="md" />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span className="text-body-strong text-ink">{item.author?.display_name ?? 'Collector'}</span>
          <span className="text-caption text-ink-3">@{item.author?.username ?? 'unknown'}</span>
          <span className="rounded-full bg-surface-2 px-2 py-0.5 text-micro uppercase tracking-widest text-ink-3">{item.surface}</span>
          <time className="text-caption text-ink-3" dateTime={item.created_at}>{shortTimeAgo(item.created_at)}</time>
          {canManage ? <OverflowMenu className="ml-auto" label="Manage reply" items={[{ key: 'open', label: 'Open discussion', icon: 'comment', onSelect: () => window.location.assign(destination) }, { key: 'copy', label: 'Copy link', icon: 'link', onSelect: () => void copyPath(destination, success, fromError) }, { key: 'delete', label: 'Delete reply', icon: 'trash', destructive: true, onSelect: () => setConfirming(true) }]} /> : null}
        </div>
        <p className="mt-2 whitespace-pre-wrap break-words text-body text-ink-2">{item.body}</p>
        <Link href={destination} className="focus-ring mt-3 block rounded-md border border-line-subtle bg-surface-1 p-3 transition-colors dur-fast hover:border-line-strong">
          <span className="text-micro uppercase tracking-widest text-ink-3">{item.parent_id ? `Replying in ${item.surface}` : `On ${item.surface}`}</span>
          {item.context.unavailable ? <span className="mt-1 block text-caption text-ink-3">This discussion is no longer available.</span> : <><span className="mt-1 block truncate text-callout text-ink">{item.context.title ?? item.context.author?.display_name ?? 'Discussion'}</span>{item.context.body ? <span className="mt-1 line-clamp-2 text-caption text-ink-3">{item.context.body}</span> : null}</>}
        </Link>
        <ActionBar type="comment" id={item.id} seed={{ likeCount: item.counts.like, saveCount: item.counts.save, repostCount: item.counts.repost, commentCount: item.counts.reply, viewerLiked: item.viewer.liked, viewerSaved: item.viewer.saved, viewerReposted: item.viewer.reposted }} variant="compact" showViews={false} showComment={false} className="-ml-1.5 mt-2" />
      </div>
    </li>
    <ConfirmDialog
      open={confirming}
      onCancel={() => setConfirming(false)}
      title="Delete this reply?"
      description="It will be removed from the discussion and your Pulse activity."
      confirmLabel="Delete"
      destructive
      onConfirm={async () => {
        try {
          await deleteComment(supabase, item.id);
          onRemoved();
          emitSocialActivityMutation({ kind: 'delete', type: 'comment', id: item.id, actorId: user?.id });
          success('Reply deleted');
          setConfirming(false);
        } catch (error) {
          fromError(error);
        }
      }}
    />
    </>
  );
}

async function copyPath(
  path: string,
  success: (title: string, description?: string) => void,
  fromError: (error: unknown) => void,
): Promise<void> {
  try {
    await navigator.clipboard.writeText(new URL(path, window.location.origin).toString());
    success('Link copied');
  } catch (error) {
    fromError(error);
  }
}

function TabRail<T extends string>({ label, value, values, labels, onChange, prominent = false }: { label: string; value: T; values: readonly T[]; labels: Record<T, string>; onChange: (value: T) => void; prominent?: boolean }) {
  return <div role="tablist" aria-label={label} className={cn('flex overflow-x-auto border-b border-line-subtle', prominent && '-mx-4 mt-6 px-4 sm:mx-0 sm:px-0')}>{values.map((candidate) => { const active = candidate === value; return <button key={candidate} type="button" role="tab" aria-selected={active} onClick={() => onChange(candidate)} className={cn('focus-ring -mb-px shrink-0 border-b-2 px-4 py-3 text-body-strong transition-colors dur-fast', active ? 'border-accent text-ink' : 'border-transparent text-ink-3 hover:text-ink')}>{labels[candidate]}</button>; })}</div>;
}

function FilterChips<T extends string>({ value, values, labels, onChange }: { value: T; values: readonly T[]; labels: Record<T, string>; onChange: (value: T) => void }) {
  return <div role="group" className="mt-3 flex flex-wrap gap-2" aria-label="Filter">{values.map((candidate) => <button key={candidate} type="button" aria-pressed={candidate === value} onClick={() => onChange(candidate)} className={cn('focus-ring rounded-full border px-3 py-1.5 text-caption transition-colors dur-fast', candidate === value ? 'border-accent bg-accent-subtle text-accent' : 'border-line bg-surface-1 text-ink-3 hover:text-ink')}>{labels[candidate]}</button>)}</div>;
}

function dedupe<T>(items: T[], keyOf: (item: T) => string): T[] { const seen = new Set<string>(); return items.filter((item) => { const key = keyOf(item); if (seen.has(key)) return false; seen.add(key); return true; }); }
function contentCount(mode: ProfileMode, pulseSection: ProfilePulseSection, summaries: EntitySummary[], pulse: CursorPage<PulseEntry>, discussions: CursorPage<ProfileDiscussionItem>, reactions: CursorPage<ProfileReactionItem>): number { return mode === 'surf' ? summaries.length : mode === 'activity' ? reactions.items.length : pulseSection === 'replies' ? discussions.items.length : pulse.items.length; }
function hasMore(mode: ProfileMode, surfDone: boolean, pulseSection: ProfilePulseSection, pulse: CursorPage<PulseEntry>, discussions: CursorPage<ProfileDiscussionItem>, reactions: CursorPage<ProfileReactionItem>): boolean { return mode === 'surf' ? !surfDone : mode === 'activity' ? reactions.has_more : pulseSection === 'replies' ? discussions.has_more : pulse.has_more; }
function emptyCopy(mode: ProfileMode, surf: ProfileSurfView, pulse: ProfilePulseSection, action: ProfileReactionAction, self: boolean, name: string): { title: string; description: string } { if (mode === 'surf') return { title: surf === 'collections' ? (self ? 'No collections yet' : 'Nothing public here yet') : 'No items to show', description: self ? 'Build your hierarchy in Create and it will appear here.' : `${name} has not published anything in this view.` }; if (mode === 'activity') return { title: `Nothing ${action === 'like' ? 'liked' : 'saved'} yet`, description: `Your private ${action === 'like' ? 'likes' : 'saves'} will appear here.` }; return { title: pulse === 'replies' ? 'No replies yet' : pulse === 'media' ? 'No Pulse media yet' : 'Nothing said yet', description: self ? 'Posts, reposts, quotes and discussions you create will appear here.' : `${name} has no visible activity in this view.` }; }
function Stat({ label, value }: { label: string; value: number }) { return <div className="min-w-0"><dt className="sr-only">{label}</dt><dd className="tabular text-title3 text-ink">{compactCount(value)}</dd><span aria-hidden className="block truncate text-caption text-ink-3">{label}</span></div>; }
