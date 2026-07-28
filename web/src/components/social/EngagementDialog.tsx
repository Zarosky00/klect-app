'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PulseCard } from '@/app/(app)/pulse/_components/PulseCard';
import { Button } from '@/components/ui/Button';
import { Avatar } from '@/components/ui/Avatar';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Modal } from '@/components/ui/Modal';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { socialEngagement } from '@/lib/api';
import { cn } from '@/lib/cn';
import type { EntityType } from '@/lib/entities';
import { compactCount, shortTimeAgo } from '@/lib/format';
import { pulseEntryKey, type EngagementItem, type EngagementSummary, type EngagementTab, type SocialCursor } from '@/lib/types';
import { profileHref } from '@/lib/routes';
import { useSession } from '@/providers/session-provider';
import { FollowButton } from './FollowButton';

const TABS: readonly EngagementTab[] = ['like', 'repost', 'quote'];
const LABELS: Record<EngagementTab, string> = {
  like: 'Likes',
  repost: 'Reposts',
  quote: 'Quotes',
};

const EMPTY_SUMMARY: EngagementSummary = {
  like_count: 0,
  repost_count: 0,
  quote_count: 0,
};

export interface EngagementDialogProps {
  open: boolean;
  onClose: () => void;
  type: EntityType;
  id: string;
  initialTab: EngagementTab;
  initialSummary?: Partial<EngagementSummary>;
}

function itemKey(item: EngagementItem): string {
  return item.kind === 'actor'
    ? `actor:${item.user.id}`
    : `quote:${pulseEntryKey(item.entry)}`;
}

export function EngagementDialog({
  open,
  onClose,
  type,
  id,
  initialTab,
  initialSummary,
}: EngagementDialogProps) {
  const { supabase } = useSession();
  const [tab, setTab] = useState<EngagementTab>(initialTab);
  const [summary, setSummary] = useState<EngagementSummary>({
    ...EMPTY_SUMMARY,
    ...initialSummary,
  });
  const [items, setItems] = useState<EngagementItem[]>([]);
  const [cursor, setCursor] = useState<SocialCursor | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const requestId = useRef(0);

  const load = useCallback(
    async (nextTab: EngagementTab, nextCursor: SocialCursor | null) => {
      const currentRequest = ++requestId.current;
      setLoading(true);
      setError(null);
      try {
        const page = await socialEngagement(supabase, type, id, nextTab, {
          cursor: nextCursor,
        });
        if (requestId.current !== currentRequest) return;
        setSummary(page.summary);
        setItems((current) => {
          const base = nextCursor === null ? [] : current;
          const known = new Set(base.map(itemKey));
          return [...base, ...page.items.filter((item) => !known.has(itemKey(item)))];
        });
        setCursor(page.next_cursor);
        setHasMore(page.has_more);
      } catch (thrown) {
        if (requestId.current === currentRequest) setError(thrown);
      } finally {
        if (requestId.current === currentRequest) setLoading(false);
      }
    },
    [id, supabase, type],
  );

  useEffect(() => {
    if (!open) return;
    setTab(initialTab);
    setItems([]);
    setCursor(null);
    setSummary({ ...EMPTY_SUMMARY, ...initialSummary });
    void load(initialTab, null);
  }, [initialSummary, initialTab, load, open]);

  const counts = useMemo<Record<EngagementTab, number>>(
    () => ({
      like: summary.like_count,
      repost: summary.repost_count,
      quote: summary.quote_count,
    }),
    [summary],
  );

  const select = (next: EngagementTab) => {
    if (next === tab) return;
    setTab(next);
    setItems([]);
    setCursor(null);
    void load(next, null);
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Engagement"
      description={`${compactCount(summary.like_count)} likes · ${compactCount(summary.repost_count)} reposts · ${compactCount(summary.quote_count)} quotes`}
      size="lg"
      className="h-full sm:h-auto sm:min-h-128"
      contentClassName="flex flex-col overflow-hidden"
    >
      <div
        role="tablist"
        aria-label="Engagement type"
        className="grid shrink-0 grid-cols-3 border-b border-line-subtle px-3 sm:px-6"
      >
        {TABS.map((value) => {
          const active = value === tab;
          return (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={active}
              aria-controls="engagement-panel"
              onClick={() => select(value)}
              className={cn(
                'focus-ring relative flex min-w-0 items-center justify-center gap-1.5 px-2 py-3 text-callout',
                'transition-colors dur-fast ease-standard',
                active ? 'text-ink' : 'text-ink-3 hover:text-ink',
              )}
            >
              <span>{LABELS[value]}</span>
              <span className="tabular text-caption">{compactCount(counts[value])}</span>
              <span
                aria-hidden
                className={cn(
                  'absolute inset-x-3 bottom-0 h-0.5 rounded-full bg-accent transition-transform dur-medium ease-standard',
                  active ? 'scale-x-100' : 'scale-x-0',
                )}
              />
            </button>
          );
        })}
      </div>

      <div
        id="engagement-panel"
        role="tabpanel"
        aria-live="polite"
        className="min-h-0 flex-1 overflow-y-auto"
      >
        {error && items.length === 0 ? (
          <div className="p-6">
            <ErrorState error={error} onRetry={() => void load(tab, null)} />
          </div>
        ) : loading && items.length === 0 ? (
          <div className="flex flex-col gap-4 p-5 sm:p-6">
            <SkeletonRow />
            <SkeletonRow />
            <SkeletonRow />
          </div>
        ) : items.length === 0 ? (
          <EmptyState
            icon={tab === 'like' ? 'heart' : 'repost'}
            title={`No ${LABELS[tab].toLowerCase()} yet`}
            description={
              tab === 'quote'
                ? 'Quotes with commentary will appear here.'
                : `Accounts that ${tab === 'like' ? 'like' : 'repost'} this will appear here.`
            }
          />
        ) : (
          <ol className="divide-y divide-line-subtle">
            {items.map((item, index) =>
              item.kind === 'actor' ? (
                <li
                  key={itemKey(item)}
                  className="k-feed-enter flex items-center gap-3 px-4 py-3 sm:px-6"
                >
                  <Link
                    href={profileHref(item.user.username)}
                    className="focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-md"
                  >
                    <Avatar
                      path={item.user.avatar_path}
                      name={item.user.display_name}
                      username={item.user.username}
                      verified={item.user.is_verified}
                      size="md"
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-body-strong text-ink">
                        {item.user.display_name}
                      </span>
                      <span className="block truncate text-caption text-ink-3">
                        @{item.user.username} · {shortTimeAgo(item.acted_at)}
                      </span>
                    </span>
                  </Link>
                  <FollowButton
                    userId={item.user.id}
                    following={item.viewer_follows}
                    size="sm"
                  />
                </li>
              ) : (
                <li key={itemKey(item)}>
                  <PulseCard entry={item.entry} enterIndex={index} />
                </li>
              ),
            )}
          </ol>
        )}

        {hasMore && items.length > 0 ? (
          <div className="flex justify-center p-5">
            <Button
              variant="secondary"
              loading={loading}
              onClick={() => void load(tab, cursor)}
            >
              Load more
            </Button>
          </div>
        ) : null}
      </div>
    </Modal>
  );
}
