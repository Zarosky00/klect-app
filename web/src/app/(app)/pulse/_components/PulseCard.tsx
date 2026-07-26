'use client';

import Link from 'next/link';
import { ActionBar } from '@/components/ui/ActionBar';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, entityKey, type EntityType } from '@/lib/entities';
import { compactCount, longTimeAgo, plural, shortTimeAgo } from '@/lib/format';
import type { SocialSeed } from '@/lib/interactions';
import { closeupHref, profileHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { PulseEntry } from '@/lib/types';
import type { AttachmentMap, PulseAttachment } from './attachments';

/**
 * One entry in the Pulse stream.
 *
 * `pulse_feed` mixes three shapes and this renders all of them:
 *   · a post — someone said something;
 *   · a repost — someone put someone else's post in front of you, with a
 *     "reposted" ribbon above the original;
 *   · a quote — the reposter's own words above the thing they are quoting.
 *
 * When an entry carries an entity reference it renders as a rich card, because
 * a collection shared into a feed should still look like a collection.
 */
export interface PulseCardProps {
  entry: PulseEntry;
  attachments: AttachmentMap;
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

export function PulseCard({ entry, attachments }: PulseCardProps) {
  const author = entry.author;
  const attachment =
    entry.target_type && entry.target_id
      ? (attachments.get(entityKey(entry.target_type, entry.target_id)) ?? null)
      : null;

  // A repost of an entity that has no post row still needs something to act on:
  // fall back to the entity itself, so every entry in the stream is social.
  const subject: { type: EntityType; id: string } | null = entry.post_id
    ? { type: 'post', id: entry.post_id }
    : entry.target_type && entry.target_id
      ? { type: entry.target_type, id: entry.target_id }
      : null;

  const isQuote = Boolean(entry.quote_text);

  return (
    <article className="flex flex-col gap-3 border-b border-line-subtle px-4 py-5 sm:px-6">
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
            <time
              dateTime={entry.sort_at}
              title={longTimeAgo(entry.sort_at)}
              className="text-caption text-ink-3"
            >
              {shortTimeAgo(entry.sort_at)}
            </time>
          </p>

          {entry.body ? (
            <p className="whitespace-pre-wrap break-words text-body text-ink-2">{entry.body}</p>
          ) : null}

          {attachment ? <AttachmentCard attachment={attachment} /> : null}

          {subject ? (
            <ActionBar
              type={subject.type}
              id={subject.id}
              seed={seedFor(entry)}
              title={entry.body ?? attachment?.title}
              variant="compact"
              className="-ml-1.5 mt-1"
            />
          ) : null}
        </div>
      </div>
    </article>
  );
}

function AttachmentCard({ attachment }: { attachment: PulseAttachment }) {
  const childLabel =
    attachment.type === 'item'
      ? `${compactCount(attachment.childCount)} ${plural(attachment.childCount, 'photo')}`
      : `${compactCount(attachment.childCount)} ${plural(attachment.childCount, 'item')}`;

  return (
    <Link
      href={closeupHref(attachment.type, attachment.id)}
      className={cn(
        'focus-ring group flex gap-3 overflow-hidden rounded-lg border border-line',
        'bg-surface-1 transition-colors dur-fast ease-standard hover:border-line-strong',
      )}
    >
      <div className="w-28 shrink-0 sm:w-36">
        <BlurhashImage
          src={mediaUrl(attachment.coverPath)}
          alt=""
          width={attachment.width}
          height={attachment.height}
          blurhash={attachment.blurhash}
          fallbackAspect={1}
          sizes="144px"
        />
      </div>

      <div className="flex min-w-0 flex-1 flex-col justify-center gap-1 py-3 pr-3">
        <span className="text-micro uppercase tracking-widest text-ink-3">
          {ENTITY_LABEL[attachment.type]}
        </span>
        <span className="truncate font-display text-title2 text-ink">{attachment.title}</span>
        {attachment.subtitle ? (
          <span className="line-clamp-2 text-caption text-ink-2">{attachment.subtitle}</span>
        ) : null}
        <span className="tabular text-caption text-ink-3">
          {childLabel} · {compactCount(attachment.likeCount)}{' '}
          {plural(attachment.likeCount, 'like')}
        </span>
      </div>
    </Link>
  );
}
