'use client';

import Link from 'next/link';
import { useState } from 'react';
import { ActionBar } from '@/components/ui/ActionBar';
import { Avatar } from '@/components/ui/Avatar';
import { cn } from '@/lib/cn';
import { compactCount, fullDateTime, plural } from '@/lib/format';
import type { SocialSeed } from '@/lib/interactions';
import { profileHref } from '@/lib/routes';
import type { PostThread } from '@/lib/types';
import {
  useEntitySocial,
  useRealtimeEntity,
  useRecordView,
} from '@/providers/interactions-provider';
import { PostMediaGrid, PostTargetCard } from './post-bits';
import { ThreadComments } from './ThreadComments';

/**
 * The post thread — the X anatomy (W3): author header, full-size body, inline
 * bounded media, the embedded target card, a stats row, the one ActionBar, and
 * the paged discussion with a reply-first composer.
 *
 * Served by both the intercepting modal and the `/p/[id]` full page from the
 * same `get_post_thread` payload, so a deep link and an in-stream tap render
 * identically — exactly the closeup pattern.
 */
export interface PostThreadViewProps {
  thread: PostThread;
  variant?: 'page' | 'modal';
  className?: string;
}

export function PostThreadView({ thread, variant = 'page', className }: PostThreadViewProps) {
  const entry = thread.post;
  const author = entry.author;
  const postId = entry.post_id ?? '';

  const seed: SocialSeed = {
    likeCount: thread.stats.like_count,
    saveCount: thread.stats.save_count,
    repostCount: thread.stats.repost_count,
    commentCount: thread.stats.comment_count,
    viewCount: thread.stats.view_count,
    viewerLiked: entry.viewer_liked,
    viewerSaved: entry.viewer_saved,
    viewerReposted: entry.viewer_reposted,
  };

  // Live counters: the stats row and the ActionBar read the same store record,
  // realtime UPDATEs on the posts row keep both fresh.
  const social = useEntitySocial('post', postId, seed);
  useRealtimeEntity('post', postId);
  useRecordView('post', postId);

  const [focusSignal, setFocusSignal] = useState(0);
  const media = entry.media ?? [];

  return (
    <article className={cn('flex flex-col gap-4 p-4 sm:p-6', className)}>
      {/* Author header */}
      <div className="flex items-center gap-3">
        <Link
          href={author ? profileHref(author.username) : '#'}
          tabIndex={author ? 0 : -1}
          className="focus-ring shrink-0 rounded-full"
        >
          <Avatar
            path={author?.avatar_path}
            name={author?.display_name}
            username={author?.username}
            size="lg"
            verified={author?.is_verified ?? false}
          />
        </Link>
        <div className="min-w-0 flex-1">
          {author ? (
            <Link
              href={profileHref(author.username)}
              className="focus-ring block truncate rounded-sm text-body-strong text-ink hover:underline"
            >
              {author.display_name}
            </Link>
          ) : (
            <p className="truncate text-body-strong text-ink">Collector</p>
          )}
          <p className="truncate text-caption text-ink-3">@{author?.username ?? 'unknown'}</p>
        </div>
      </div>

      {/* Full-size body */}
      {entry.body ? (
        <p className="whitespace-pre-wrap break-words text-title3 font-normal text-ink">
          {entry.body}
        </p>
      ) : null}

      {/* Inline bounded media */}
      {media.length > 0 ? <PostMediaGrid media={media} href={null} /> : null}

      {/* Quoted post / shared shelf */}
      {entry.target ? <PostTargetCard target={entry.target} /> : null}

      {/* Timestamp row */}
      <p className="text-caption text-ink-3">
        <time dateTime={entry.sort_at}>{fullDateTime(entry.sort_at)}</time>
        {social.viewCount > 0 ? (
          <>
            {' · '}
            <span className="tabular">{compactCount(social.viewCount)}</span>{' '}
            {plural(social.viewCount, 'view')}
          </>
        ) : null}
      </p>

      {/* Stats row — live, X-style */}
      <dl className="flex flex-wrap items-center gap-x-5 gap-y-1 border-y border-line-subtle py-2.5">
        <ThreadStat value={social.likeCount} label={plural(social.likeCount, 'Like')} />
        <ThreadStat value={social.repostCount} label={plural(social.repostCount, 'Repost')} />
        <ThreadStat value={social.saveCount} label={plural(social.saveCount, 'Save')} />
        <ThreadStat value={social.commentCount} label={plural(social.commentCount, 'Comment')} />
      </dl>

      {/* The one action bar — same machinery as every other entity */}
      <ActionBar
        type="post"
        id={postId}
        seed={seed}
        title={entry.body ?? undefined}
        showViews={false}
        onComment={() => setFocusSignal((value) => value + 1)}
        className="-mt-2"
      />

      <ThreadComments
        postId={postId}
        initialComments={thread.comments}
        initialHasMore={thread.has_more}
        initialSort="top"
        focusSignal={focusSignal}
        className={cn('border-t border-line-subtle pt-4', variant === 'modal' && 'pb-2')}
      />
    </article>
  );
}

function ThreadStat({ value, label }: { value: number; label: string }) {
  return (
    <div className="flex items-baseline gap-1.5">
      <dt className="sr-only">{label}</dt>
      <dd className="tabular text-body-strong text-ink">{compactCount(value)}</dd>
      <span aria-hidden className="text-caption text-ink-3">
        {label}
      </span>
    </div>
  );
}
