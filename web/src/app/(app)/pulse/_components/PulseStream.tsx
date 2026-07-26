'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button, ButtonLink } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Skeleton, SkeletonRow } from '@/components/ui/Skeleton';
import { pulseFeed } from '@/lib/api';
import { entityKey } from '@/lib/entities';
import { routes } from '@/lib/routes';
import type { PulseEntry } from '@/lib/types';
import { useSession } from '@/providers/session-provider';
import { loadAttachments, type AttachmentMap, type PulseAttachment } from './attachments';
import { PulseCard } from './PulseCard';
import { PulseComposer } from './PulseComposer';

/**
 * The X half of Klect.
 *
 * `pulse_feed` is cursor-paginated on `sort_at` rather than offset-paginated,
 * because the stream is chronological and new posts arrive at the head: an
 * offset would silently shift every page under the reader. The cursor is the
 * oldest `sort_at` already rendered, so a page boundary can never duplicate or
 * skip an entry no matter what lands while you read.
 */

const PAGE_SIZE = 25;

export interface PulseStreamProps {
  initialEntries: PulseEntry[];
  /** Resolved on the server so the first paint already has rich cards. */
  initialAttachments: PulseAttachment[];
}

/** Identity of an entry: a repost and its original are two rows, one post id. */
const entryKey = (entry: PulseEntry): string =>
  `${entry.feed_kind}:${entry.reposter_id ?? ''}:${entry.post_id ?? ''}:${entry.sort_at}`;

export function PulseStream({ initialEntries, initialAttachments }: PulseStreamProps) {
  const { supabase, user } = useSession();

  const [entries, setEntries] = useState<PulseEntry[]>(initialEntries);
  const [attachments, setAttachments] = useState<AttachmentMap>(() => {
    const map: AttachmentMap = new Map();
    for (const value of initialAttachments) map.set(entityKey(value.type, value.id), value);
    return map;
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [exhausted, setExhausted] = useState(initialEntries.length < PAGE_SIZE);

  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const inFlight = useRef(false);
  const seen = useRef(new Set(initialEntries.map(entryKey)));

  const loadMore = useCallback(async () => {
    if (inFlight.current || exhausted) return;
    inFlight.current = true;
    setLoading(true);
    setError(null);

    try {
      const oldest = entries[entries.length - 1]?.sort_at;
      const rows = await pulseFeed(supabase, {
        limit: PAGE_SIZE,
        ...(oldest === undefined ? {} : { before: oldest }),
      });

      const fresh = rows.filter((row) => {
        const key = entryKey(row);
        if (seen.current.has(key)) return false;
        seen.current.add(key);
        return true;
      });

      if (fresh.length > 0) {
        const resolved = await loadAttachments(supabase, fresh, attachments);
        setAttachments(resolved);
        setEntries((current) => [...current, ...fresh]);
      }
      if (rows.length < PAGE_SIZE) setExhausted(true);
    } catch (thrown) {
      setError(thrown);
    } finally {
      setLoading(false);
      inFlight.current = false;
    }
  }, [attachments, entries, exhausted, supabase]);

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel || exhausted || typeof IntersectionObserver === 'undefined') return;

    const observer = new IntersectionObserver(
      (observed) => {
        if (observed.some((entry) => entry.isIntersecting) && !error) void loadMore();
      },
      { rootMargin: '600px 0px' },
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [error, exhausted, loadMore]);

  const onPosted = useCallback(
    (post: { id: string; body: string; created_at: string }) => {
      if (!user) return;
      const entry: PulseEntry = {
        feed_kind: 'post',
        post_id: post.id,
        sort_at: post.created_at,
        actor_id: user.id,
        reposter_id: null,
        quote_text: null,
        body: post.body,
        target_type: null,
        target_id: null,
        like_count: 0,
        save_count: 0,
        repost_count: 0,
        comment_count: 0,
        view_count: 0,
        reply_count: 0,
        author: null,
        reposter: null,
        viewer_liked: false,
        viewer_saved: false,
        viewer_reposted: false,
      };
      seen.current.add(entryKey(entry));
      setEntries((current) => [entry, ...current]);
    },
    [user],
  );

  return (
    <div className="flex flex-col">
      <PulseComposer onPosted={onPosted} />

      {entries.length === 0 && !loading ? (
        error ? (
          <ErrorState error={error} onRetry={() => void loadMore()} />
        ) : (
          <EmptyState
            icon="activity"
            title="Your pulse is quiet"
            description="Pulse shows what the collectors you follow are adding, reposting and saying. Follow a few and it fills up fast."
            action={
              <ButtonLink href={routes.matches} variant="secondary">
                Find collectors like you
              </ButtonLink>
            }
          />
        )
      ) : (
        <ol>
          {entries.map((entry) => (
            <li key={entryKey(entry)}>
              <PulseCard entry={entry} attachments={attachments} />
            </li>
          ))}
        </ol>
      )}

      {loading ? (
        <div className="flex flex-col gap-4 px-4 py-5 sm:px-6">
          <SkeletonRow />
          <Skeleton className="h-24 w-full" />
        </div>
      ) : null}

      <div ref={sentinelRef} aria-hidden className="h-px w-full" />

      <div className="flex justify-center py-8">
        {exhausted && entries.length > 0 ? (
          <p className="text-caption text-ink-3">That is everything for now.</p>
        ) : error && entries.length > 0 ? (
          <Button variant="secondary" iconLeft="repost" onClick={() => void loadMore()}>
            Retry
          </Button>
        ) : entries.length > 0 ? (
          <Button variant="ghost" loading={loading} onClick={() => void loadMore()}>
            Load more
          </Button>
        ) : null}
      </div>
    </div>
  );
}
