'use client';

import Link from 'next/link';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Avatar } from '@/components/ui/Avatar';
import { aspect } from '@/design/tokens.g';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL } from '@/lib/entities';
import { compactCount, plural, shortTimeAgo } from '@/lib/format';
import { closeupHref, postHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { PulseMedia, PulseTarget } from '@/lib/types';

/**
 * The pieces of a post's body that Pulse cards and the `/p/[id]` thread page
 * share — the bounded inline media grid and the embedded target card. One
 * module so a post can never render differently in the stream and on its own
 * thread (extracted from `PulseCard` in W3).
 */

/** Where an embedded target deep-links: posts go to their thread, a comment
 *  goes to the discussion it hangs off (0021 `parent_type`/`parent_id`), and
 *  everything else opens its closeup. */
export function targetHref(target: PulseTarget): string {
  if (target.type === 'post') return postHref(target.id);
  if (target.type === 'comment' && target.parent_type && target.parent_id) {
    return target.parent_type === 'post'
      ? postHref(target.parent_id)
      : closeupHref(target.parent_type, target.parent_id);
  }
  return closeupHref(target.type, target.id);
}

/* ── the post's own photos, bounded inline ────────────────────────────────── */

export function PostMediaGrid({ media, href }: { media: PulseMedia[]; href: string | null }) {
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
        // Bounded, never masonry-shaped: `BlurhashImage` clamps the intrinsic
        // ratio into the token band, so one very tall photo cannot own the feed.
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

export function PostTargetCard({ target }: { target: PulseTarget }) {
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
  const targetMedia = (target.media ?? []).slice(0, 4);
  return (
    <div
      className={cn(
        'focus-ring block rounded-lg border border-line bg-surface-1 p-3',
        'transition-colors dur-fast ease-standard hover:border-line-strong',
      )}
    >
      <Link href={targetHref(target)} className="focus-ring block rounded-md">
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
      </Link>

      {targetMedia.length > 0 ? (
        <div className="mt-2">
          <PostMediaGrid media={targetMedia} href={targetHref(target)} />
        </div>
      ) : target.cover_path ? (
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

      {target.attached_target ? (
        <div className="mt-2">
          <PostTargetCard target={target.attached_target} />
        </div>
      ) : null}
    </div>
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
      href={targetHref(target)}
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
