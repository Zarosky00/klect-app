'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { ActionBar } from '@/components/ui/ActionBar';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { listStaggerDelay } from '@/design/motion';
import { aspect } from '@/design/tokens.g';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, type EntityType } from '@/lib/entities';
import { compactCount, longTimeAgo, plural, shortTimeAgo } from '@/lib/format';
import type { SocialSeed } from '@/lib/interactions';
import { closeupHref, profileHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { PulseEntry, PulseMedia, PulseTarget } from '@/lib/types';
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
 * The comment pill and the body both open the post closeup (the intercepting
 * `/closeup/post/…` route), which is where the thread lives.
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

  const subjectHref = subject ? closeupHref(subject.type, subject.id) : null;
  const postHref = entry.post_id ? closeupHref('post', entry.post_id) : subjectHref;

  const isQuote = Boolean(entry.quote_text);
  const media = entry.media ?? [];
  const quoteSubject = onQuote ? quoteSubjectOf(entry) : null;

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
            {postHref ? (
              <Link
                href={postHref}
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
            entry.post_id ? (
              <Link href={closeupHref('post', entry.post_id)} className="focus-ring rounded-sm">
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

          {media.length > 0 ? (
            <MediaGrid media={media} href={entry.post_id ? closeupHref('post', entry.post_id) : null} />
          ) : null}

          {entry.target ? <TargetCard target={entry.target} /> : null}

          {subject ? (
            <ActionBar
              type={subject.type}
              id={subject.id}
              seed={seedFor(entry)}
              title={entry.body ?? entry.target?.title ?? undefined}
              variant="compact"
              className="-ml-1.5 mt-1"
              {...(subjectHref
                ? { onComment: () => router.push(subjectHref) }
                : {})}
              {...(quoteSubject ? { onQuote: () => onQuote?.(quoteSubject) } : {})}
            />
          ) : null}
        </div>
      </div>
    </article>
  );
}

/* ── the post's own photos ────────────────────────────────────────────────── */

function MediaGrid({ media, href }: { media: PulseMedia[]; href: string | null }) {
  const cell = (
    photo: PulseMedia,
    options: { intrinsic?: boolean; ratio?: number; className?: string } = {},
  ) => {
    const image = (
      <BlurhashImage
        src={mediaUrl(photo.storage_path)}
        alt={photo.alt_text ?? ''}
        width={options.intrinsic ? photo.width : null}
        height={options.intrinsic ? photo.height : null}
        blurhash={photo.blurhash}
        dominantColor={photo.dominant_color}
        fallbackAspect={options.ratio ?? 1}
        sizes="(max-width: 768px) 90vw, 560px"
        imageClassName="transition-transform dur-medium ease-standard group-hover:scale-[1.02]"
      />
    );
    return href ? (
      <Link
        key={photo.id}
        href={href}
        className={cn('focus-ring group block overflow-hidden', options.className)}
      >
        {image}
      </Link>
    ) : (
      <span key={photo.id} className={cn('block overflow-hidden', options.className)}>
        {image}
      </span>
    );
  };

  const first = media[0];
  if (!first) return null;

  return (
    <div
      className="overflow-hidden rounded-lg border border-line-subtle"
      role="group"
      aria-label={`${media.length} ${plural(media.length, 'photo')}`}
    >
      {media.length === 1 ? (
        cell(first, { intrinsic: true })
      ) : media.length === 2 ? (
        <div className="grid grid-cols-2 gap-px">{media.map((photo) => cell(photo))}</div>
      ) : media.length === 3 ? (
        <div className="flex flex-col gap-px">
          {cell(first, { ratio: aspect.gridMax })}
          <div className="grid grid-cols-2 gap-px">
            {media.slice(1).map((photo) => cell(photo))}
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-px">{media.map((photo) => cell(photo))}</div>
      )}
    </div>
  );
}

/* ── the embedded target ──────────────────────────────────────────────────── */

function TargetCard({ target }: { target: PulseTarget }) {
  if (target.unavailable) {
    return (
      <div className="rounded-lg border border-dashed border-line px-4 py-3 text-caption text-ink-3">
        This {ENTITY_LABEL[target.type].toLowerCase()} is no longer available.
      </div>
    );
  }
  if (target.type === 'post' || target.type === 'comment') {
    return <QuotedPostCard target={target} />;
  }
  return <EntityTargetCard target={target} />;
}

/** A quoted post (or comment): author row, words, first photo. */
function QuotedPostCard({ target }: { target: PulseTarget }) {
  const author = target.author;
  return (
    <Link
      href={closeupHref(target.type, target.id)}
      className={cn(
        'focus-ring block rounded-lg border border-line bg-surface-1 p-3',
        'transition-colors dur-fast ease-standard hover:border-line-strong',
      )}
    >
      <p className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <Avatar
          path={author?.avatar_path}
          name={author?.display_name}
          username={author?.username}
          size="xs"
          verified={author?.is_verified ?? false}
        />
        <span className="text-callout font-medium text-ink">
          {author?.display_name ?? 'Collector'}
        </span>
        <span className="text-caption text-ink-3">@{author?.username ?? 'unknown'}</span>
        {target.created_at ? (
          <time dateTime={target.created_at} className="text-caption text-ink-3">
            {shortTimeAgo(target.created_at)}
          </time>
        ) : null}
      </p>

      {target.body ? (
        <p className="mt-1.5 line-clamp-4 whitespace-pre-wrap break-words text-body text-ink-2">
          {target.body}
        </p>
      ) : null}

      {target.cover_path ? (
        <div className="mt-2 overflow-hidden rounded-md border border-line-subtle">
          <BlurhashImage
            src={mediaUrl(target.cover_path)}
            alt=""
            width={target.cover_width ?? null}
            height={target.cover_height ?? null}
            blurhash={target.cover_blurhash}
            fallbackAspect={aspect.gridMax}
            sizes="(max-width: 768px) 85vw, 520px"
          />
        </div>
      ) : null}
    </Link>
  );
}

/** A shared collection / subcollection / item, rendered like what it is. */
function EntityTargetCard({ target }: { target: PulseTarget }) {
  const childCount = target.child_count ?? 0;
  const likeCount = target.like_count ?? 0;
  const childLabel =
    target.type === 'item'
      ? `${compactCount(childCount)} ${plural(childCount, 'photo')}`
      : `${compactCount(childCount)} ${plural(childCount, 'item')}`;

  return (
    <Link
      href={closeupHref(target.type, target.id)}
      className={cn(
        'focus-ring group flex gap-3 overflow-hidden rounded-lg border border-line',
        'bg-surface-1 transition-colors dur-fast ease-standard hover:border-line-strong',
      )}
    >
      <div className="w-28 shrink-0 sm:w-36">
        <BlurhashImage
          src={mediaUrl(target.cover_path)}
          alt=""
          width={target.cover_width ?? null}
          height={target.cover_height ?? null}
          blurhash={target.cover_blurhash}
          fallbackAspect={1}
          sizes="144px"
        />
      </div>

      <div className="flex min-w-0 flex-1 flex-col justify-center gap-1 py-3 pr-3">
        <span className="text-micro uppercase tracking-widest text-ink-3">
          {ENTITY_LABEL[target.type]}
          {target.author ? ` · @${target.author.username}` : ''}
        </span>
        <span className="truncate font-display text-title2 text-ink">
          {target.title ?? 'Untitled'}
        </span>
        {target.subtitle ? (
          <span className="line-clamp-2 text-caption text-ink-2">{target.subtitle}</span>
        ) : null}
        <span className="tabular text-caption text-ink-3">
          {childLabel} · {compactCount(likeCount)} {plural(likeCount, 'like')}
        </span>
      </div>
    </Link>
  );
}
