'use client';

import Link from 'next/link';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, entityHref } from '@/lib/entities';
import { compactCount, plural } from '@/lib/format';
import { mediaUrl } from '@/lib/storage';
import { Avatar } from '@/components/ui/Avatar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import type { EntitySummary } from './queries';

/**
 * A collection, subcollection, item or post shared into a conversation,
 * rendered as a rich card rather than a bare link. The same shape serves all
 * four; posts get their own words-first layout below.
 */
export function SharedEntityCard({
  summary,
  className,
}: {
  summary: EntitySummary | null;
  className?: string;
}) {
  if (!summary) {
    return (
      <div
        className={cn(
          'flex items-center gap-2 rounded-lg border border-line-subtle bg-surface-2 px-3 py-2.5 text-caption text-ink-3',
          className,
        )}
      >
        <Icon name="alert" size="sm" />
        This is no longer available.
      </div>
    );
  }

  if (summary.type === 'post') return <SharedPostCard summary={summary} className={className} />;

  const childLabel =
    summary.type === 'item'
      ? `${compactCount(summary.childCount)} ${plural(summary.childCount, 'photo')}`
      : `${compactCount(summary.childCount)} ${plural(summary.childCount, 'item')}`;

  return (
    <Link
      href={entityHref(summary.type, summary.id)}
      className={cn(
        'focus-ring flex w-64 flex-col overflow-hidden rounded-lg border border-line bg-surface-1',
        'transition-colors dur-fast ease-standard hover:border-accent',
        className,
      )}
    >
      <BlurhashImage
        src={mediaUrl(summary.coverPath)}
        alt={summary.title}
        width={summary.width}
        height={summary.height}
        blurhash={summary.coverBlurhash}
        dominantColor={summary.accentColor}
        fallbackAspect={1.6}
        sizes="256px"
      />
      <span className="flex flex-col gap-0.5 p-3">
        <span className="text-micro uppercase tracking-widest text-ink-3">
          {ENTITY_LABEL[summary.type]}
        </span>
        <span className="truncate text-body-strong text-ink">{summary.title}</span>
        <span className="flex items-center gap-2 text-caption text-ink-3">
          <span className="tabular inline-flex items-center gap-1">
            <Icon name="heart" size="xs" />
            {compactCount(summary.likeCount)}
          </span>
          <span aria-hidden>·</span>
          <span className="tabular">{childLabel}</span>
        </span>
      </span>
    </Link>
  );
}

/** A shared post: author byline, body excerpt, first photo — words first. */
function SharedPostCard({
  summary,
  className,
}: {
  summary: EntitySummary;
  className?: string;
}) {
  const author = summary.author ?? null;
  return (
    <Link
      href={entityHref('post', summary.id)}
      className={cn(
        'focus-ring flex w-64 flex-col gap-2 rounded-lg border border-line bg-surface-1 p-3',
        'transition-colors dur-fast ease-standard hover:border-accent',
        className,
      )}
    >
      <span className="flex items-center gap-2">
        <Avatar
          path={author?.avatarPath}
          name={author?.displayName}
          username={author?.username}
          size="xs"
          verified={author?.isVerified ?? false}
        />
        <span className="min-w-0">
          <span className="block truncate text-callout font-medium text-ink">
            {author?.displayName ?? 'Collector'}
          </span>
          <span className="block truncate text-micro text-ink-3">
            @{author?.username ?? 'unknown'}
          </span>
        </span>
      </span>

      {summary.body ? (
        <span className="line-clamp-4 whitespace-pre-wrap break-words text-body text-ink-2">
          {summary.body}
        </span>
      ) : null}

      {summary.coverPath ? (
        <span className="block overflow-hidden rounded-md border border-line-subtle">
          <BlurhashImage
            src={mediaUrl(summary.coverPath)}
            alt=""
            width={summary.width}
            height={summary.height}
            blurhash={summary.coverBlurhash}
            fallbackAspect={1.6}
            sizes="232px"
          />
        </span>
      ) : null}

      <span className="flex items-center gap-2 text-caption text-ink-3">
        <span className="text-micro uppercase tracking-widest">{ENTITY_LABEL.post}</span>
        <span aria-hidden>·</span>
        <span className="tabular inline-flex items-center gap-1">
          <Icon name="heart" size="xs" />
          {compactCount(summary.likeCount)}
        </span>
      </span>
    </Link>
  );
}
