'use client';

import Link from 'next/link';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, entityHref } from '@/lib/entities';
import { compactCount, plural } from '@/lib/format';
import { mediaUrl } from '@/lib/storage';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import type { EntitySummary } from './queries';

/**
 * A collection, subcollection or item shared into a conversation, rendered as a
 * rich card rather than a bare link. The same shape serves all three levels.
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
