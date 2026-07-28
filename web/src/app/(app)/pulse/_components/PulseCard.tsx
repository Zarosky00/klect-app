'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { PostMediaGrid, PostTargetCard } from '@/components/thread/post-bits';
import { ActionBar } from '@/components/ui/ActionBar';
import { Avatar } from '@/components/ui/Avatar';
import { Icon } from '@/components/ui/Icon';
import { listStaggerDelay } from '@/design/motion';
import { cn } from '@/lib/cn';
import { type EntityType } from '@/lib/entities';
import { longTimeAgo, shortTimeAgo } from '@/lib/format';
import type { SocialSeed } from '@/lib/interactions';
import { closeupHref, postHref, profileHref } from '@/lib/routes';
import type { PulseEntry } from '@/lib/types';
import type { ComposerSubject } from './PulseComposer';

/**
 * One entry in the Pulse stream.
 *
 * `pulse_feed` (migration 0018) embeds everything a card needs server-side:
 * the post's own `media[]` and a `target{}` payload for whatever it quotes,
 * shares or reposts — a quoted post renders with its author and first photo, a
 * shared collection renders as a collection, and content that has vanished or
 * gone private renders as a tombstone, never an empty card.
 *
 * Thread-first (W3): Pulse split visually from Surf. No double-tap immersive,
 * no hero — a plain click on the body, the photos, the timestamp or the
 * comment pill opens the post's thread page (`/p/[id]`, intercepted as a
 * modal in-app), which is where the discussion lives. Media renders bounded
 * inline, never masonry-shaped. Entity reposts without a post row still open
 * the entity's closeup — their discussion hangs off the entity itself.
 */
export interface PulseCardProps {
  entry: PulseEntry;
  /** Index within its page — drives the staggered entrance delay. */
  enterIndex?: number;
  /** True for the post the viewer just composed: slides in from above. */
  fresh?: boolean;
  /** From the repost chooser: open the composer with this subject embedded. */
  onQuote?: (subject: ComposerSubject) => void;
}

function seedFor(entry: PulseEntry): SocialSeed {
  return {
    likeCount: entry.like_count,
    saveCount: entry.save_count,
    repostCount: entry.repost_count,
    quoteCount: entry.quote_count ?? entry.target?.quote_count ?? 0,
    commentCount: entry.comment_count,
    viewCount: entry.view_count,
    viewerLiked: entry.viewer_liked,
    viewerSaved: entry.viewer_saved,
    viewerReposted: entry.viewer_reposted,
  };
}

/** What quoting this entry should embed in the composer. */
function quoteSubjectOf(entry: PulseEntry): ComposerSubject | null {
  if (entry.post_id) {
    const first = entry.media?.[0];
    return {
      type: 'post',
      id: entry.post_id,
      title: null,
      subtitle: null,
      body: entry.body,
      authorUsername: entry.author?.username ?? null,
      coverPath: first?.storage_path ?? null,
      coverBlurhash: first?.blurhash ?? null,
    };
  }
  if (entry.target_type && entry.target_id) {
    return {
      type: entry.target_type,
      id: entry.target_id,
      title: entry.target?.title ?? null,
      subtitle: entry.target?.subtitle ?? null,
      body: entry.target?.body ?? null,
      authorUsername: entry.target?.author?.username ?? null,
      coverPath: entry.target?.cover_path ?? null,
      coverBlurhash: entry.target?.cover_blurhash ?? null,
    };
  }
  return null;
}

export function PulseCard({ entry, enterIndex, fresh = false, onQuote }: PulseCardProps) {
  const router = useRouter();
  const author = entry.author;

  // A repost of an entity that has no post row still needs something to act on:
  // fall back to the entity itself, so every entry in the stream is social.
  const subject: { type: EntityType; id: string } | null = entry.post_id
    ? { type: 'post', id: entry.post_id }
    : entry.target_type && entry.target_id
      ? { type: entry.target_type, id: entry.target_id }
      : null;

  // W3: posts open their thread; entity reposts open the entity's closeup.
  const subjectHref = entry.post_id
    ? postHref(entry.post_id)
    : subject
      ? closeupHref(subject.type, subject.id)
      : null;
  const threadHref = entry.post_id ? postHref(entry.post_id) : null;

  const isQuote = Boolean(entry.quote_text);
  // Repost envelopes also carry target media for older clients. The canonical
  // target card owns that media; only an authored post renders entry.media.
  const media = entry.feed_kind === 'post' ? (entry.media ?? []) : [];
  const quoteSubject = onQuote ? quoteSubjectOf(entry) : null;
  const actions = subject ? (
    <ActionBar
      type={subject.type}
      id={subject.id}
      seed={seedFor(entry)}
      title={entry.body ?? entry.target?.title ?? undefined}
      variant="compact"
      className="-ml-1.5 mt-1"
      {...(subjectHref ? { onComment: () => router.push(subjectHref) } : {})}
      {...(quoteSubject ? { onQuote: () => onQuote?.(quoteSubject) } : {})}
    />
  ) : null;

  // A plain repost has no independent content. If its source becomes private
  // or disappears, omit the envelope instead of showing an identity-less row.
  if (entry.feed_kind === 'repost' && (!entry.target || entry.target.unavailable)) return null;

  return (
    <article
      className={cn(
        'flex flex-col gap-3 border-b border-line-subtle px-4 py-5 sm:px-6',
        fresh ? 'k-post-in' : 'k-feed-enter',
      )}
      style={
        fresh || enterIndex === undefined
          ? undefined
          : { animationDelay: `${listStaggerDelay(enterIndex)}s` }
      }
    >
      {entry.feed_kind === 'repost' && entry.reposter ? (
        <p className="flex items-center gap-2 text-caption text-ink-3">
          <Icon name="repost" size="xs" />
          <span>
            {entry.reposter.display_name} {isQuote ? 'quoted' : 'reposted'}
          </span>
        </p>
      ) : null}

      {isQuote ? (
        <p className="whitespace-pre-wrap text-body text-ink">{entry.quote_text}</p>
      ) : null}

      {entry.feed_kind === 'repost' && entry.target ? (
        <div className="min-w-0 pl-0 sm:pl-7">
          <PostTargetCard target={entry.target} />
          {actions}
        </div>
      ) : (
      <div className={cn('flex gap-3', isQuote && 'rounded-lg border border-line-subtle p-3')}>
        <Link
          href={author ? profileHref(author.username) : '#'}
          tabIndex={author ? 0 : -1}
          className="focus-ring h-fit shrink-0 rounded-full"
        >
          <Avatar
            path={author?.avatar_path}
            name={author?.display_name}
            username={author?.username}
            size="md"
            verified={author?.is_verified ?? false}
          />
        </Link>

        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <p className="flex flex-wrap items-baseline gap-x-2">
            <span className="text-body-strong text-ink">
              {author?.display_name ?? 'Collector'}
            </span>
            <span className="text-caption text-ink-3">@{author?.username ?? 'unknown'}</span>
            <span aria-hidden className="text-caption text-ink-3">
              ·
            </span>
            {subjectHref ? (
              <Link
                href={subjectHref}
                className="focus-ring rounded-sm text-caption text-ink-3 transition-colors dur-fast hover:text-ink"
              >
                <time dateTime={entry.sort_at} title={longTimeAgo(entry.sort_at)}>
                  {shortTimeAgo(entry.sort_at)}
                </time>
              </Link>
            ) : (
              <time
                dateTime={entry.sort_at}
                title={longTimeAgo(entry.sort_at)}
                className="text-caption text-ink-3"
              >
                {shortTimeAgo(entry.sort_at)}
              </time>
            )}
          </p>

          {entry.body ? (
            threadHref ? (
              <Link href={threadHref} className="focus-ring rounded-sm">
                <p className="whitespace-pre-wrap break-words text-body text-ink-2">
                  {entry.body}
                </p>
              </Link>
            ) : (
              <p className="whitespace-pre-wrap break-words text-body text-ink-2">
                {entry.body}
              </p>
            )
          ) : null}

          {media.length > 0 ? <PostMediaGrid media={media} href={threadHref} /> : null}

          {entry.target ? <PostTargetCard target={entry.target} /> : null}

          {actions}
        </div>
      </div>
      )}
    </article>
  );
}
