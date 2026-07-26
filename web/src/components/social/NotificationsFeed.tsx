'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { markNotificationsRead } from '@/lib/api';
import { cn } from '@/lib/cn';
import { calendarDate, shortTimeAgo } from '@/lib/format';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { useNotifications } from '@/providers/notifications-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import {
  NOTIFICATION_FALLBACK_TEXT,
  NOTIFICATION_TYPE_ICON,
  NOTIFICATION_TYPE_TONE,
  notificationTargetHref,
} from './notification-meta';
import { listNotificationEntries, type NotificationEntry } from './queries';

/**
 * Everything that happened to your collections while you were away.
 *
 * Grouped by day, colour-coded per type, and live: arrivals come from the
 * shell-level `NotificationsProvider` channel (one channel per session, shared
 * with the badge and the banner) and slide in at the top without a refetch.
 * Reading one marks just that one; "Mark all read" calls
 * `mark_notifications_read(null)`.
 */

const PAGE_SIZE = 40;

function dayKey(iso: string): string {
  const date = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  const same = (a: Date, b: Date) =>
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate();
  if (same(date, today)) return 'Today';
  if (same(date, yesterday)) return 'Yesterday';
  return calendarDate(iso);
}

export interface NotificationsFeedProps {
  initialEntries: NotificationEntry[];
  viewerId: string;
}

export function NotificationsFeed({ initialEntries }: NotificationsFeedProps) {
  const { supabase } = useSession();
  const { fromError, success } = useToast();
  const { subscribe } = useNotifications();

  const [entries, setEntries] = useState(initialEntries);
  const [loading, setLoading] = useState(false);
  const [exhausted, setExhausted] = useState(initialEntries.length < PAGE_SIZE);
  const [failure, setFailure] = useState<unknown>(null);
  const seen = useRef(new Set(initialEntries.map((entry) => entry.notification.id)));

  /* Realtime arrival — via the one shell channel, already hydrated. */
  useEffect(
    () =>
      subscribe((entry) => {
        if (seen.current.has(entry.notification.id)) return;
        seen.current.add(entry.notification.id);
        setEntries((current) => [entry, ...current]);
      }),
    [subscribe],
  );

  const loadMore = useCallback(async () => {
    const oldest = entries[entries.length - 1]?.notification.created_at;
    if (!oldest) return;
    setLoading(true);
    setFailure(null);
    try {
      const page = await listNotificationEntries(supabase, {
        limit: PAGE_SIZE,
        before: oldest,
      });
      for (const entry of page) seen.current.add(entry.notification.id);
      setEntries((current) => [...current, ...page]);
      setExhausted(page.length < PAGE_SIZE);
    } catch (error) {
      setFailure(error);
    } finally {
      setLoading(false);
    }
  }, [entries, supabase]);

  const markOne = useCallback(
    (id: string) => {
      setEntries((current) =>
        current.map((entry) =>
          entry.notification.id === id && entry.notification.read_at === null
            ? {
                ...entry,
                notification: { ...entry.notification, read_at: new Date().toISOString() },
              }
            : entry,
        ),
      );
      void markNotificationsRead(supabase, [id]).catch(() => {
        // A failed read-marker is not worth interrupting the reader; the next
        // page load will show the true state.
      });
    },
    [supabase],
  );

  const markAll = useCallback(async () => {
    const now = new Date().toISOString();
    const previous = entries;
    setEntries((current) =>
      current.map((entry) => ({
        ...entry,
        notification: { ...entry.notification, read_at: entry.notification.read_at ?? now },
      })),
    );
    try {
      const changed = await markNotificationsRead(supabase);
      success(changed > 0 ? `Marked ${changed} as read` : 'Everything was already read');
    } catch (error) {
      setEntries(previous);
      fromError(error);
    }
  }, [entries, fromError, success, supabase]);

  const unread = entries.filter((entry) => entry.notification.read_at === null).length;

  const groups = useMemo(() => {
    const map = new Map<string, NotificationEntry[]>();
    for (const entry of entries) {
      const key = dayKey(entry.notification.created_at);
      const bucket = map.get(key);
      if (bucket) bucket.push(entry);
      else map.set(key, [entry]);
    }
    return [...map.entries()];
  }, [entries]);

  return (
    <div className="content-max px-4 py-8 sm:px-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-display2 text-ink">Notifications</h1>
          <p className="mt-1 text-callout text-ink-2">
            {unread > 0
              ? `${unread} unread`
              : 'You are all caught up.'}
          </p>
        </div>
        <Button
          variant="secondary"
          iconLeft="check"
          disabled={unread === 0}
          onClick={() => void markAll()}
        >
          Mark all read
        </Button>
      </header>

      {failure ? (
        <ErrorState error={failure} onRetry={() => void loadMore()} compact />
      ) : entries.length === 0 ? (
        <EmptyState
          icon="bell"
          title="Nothing yet"
          description="Likes, saves, reposts, comments, follows and match alerts all land here the moment they happen."
        />
      ) : (
        <div className="mt-8 flex flex-col gap-8">
          {groups.map(([day, group]) => (
            <section key={day}>
              <h2 className="sticky top-0 z-sticky bg-base py-2 text-label uppercase tracking-widest text-ink-3">
                {day}
              </h2>
              <ul className="mt-1 flex flex-col gap-1">
                {group.map((entry) => (
                  <li key={entry.notification.id}>
                    <NotificationRowView entry={entry} onRead={markOne} />
                  </li>
                ))}
              </ul>
            </section>
          ))}

          {!exhausted ? (
            <div className="flex justify-center">
              <Button variant="secondary" loading={loading} onClick={() => void loadMore()}>
                Load older
              </Button>
            </div>
          ) : null}

          {loading && entries.length === 0 ? <SkeletonRow /> : null}
        </div>
      )}
    </div>
  );
}

function NotificationRowView({
  entry,
  onRead,
}: {
  entry: NotificationEntry;
  onRead: (id: string) => void;
}) {
  const { notification, actor } = entry;
  const unread = notification.read_at === null;
  const href = notificationTargetHref(entry);
  const text = notification.body ?? NOTIFICATION_FALLBACK_TEXT[notification.type];

  return (
    <Link
      href={href}
      onClick={() => onRead(notification.id)}
      aria-label={`${actor?.display_name ?? 'Klect'} ${text}, ${shortTimeAgo(notification.created_at)} ago`}
      className={cn(
        'focus-ring flex items-start gap-3 rounded-lg px-3 py-3',
        'transition-colors dur-fast ease-standard hover:bg-surface-2',
        unread && 'bg-surface-1',
      )}
    >
      <span className="relative shrink-0">
        {actor ? (
          <Avatar
            path={actor.avatar_path}
            name={actor.display_name}
            username={actor.username}
            verified={actor.is_verified}
          />
        ) : (
          <span className="grid size-10 place-items-center rounded-full bg-surface-3 text-ink-2">
            <Icon name="bell" size="md" />
          </span>
        )}
        <span
          className={cn(
            'absolute -bottom-1 -right-1 grid size-5 place-items-center rounded-full ring-2 ring-base',
            NOTIFICATION_TYPE_TONE[notification.type],
          )}
        >
          <Icon name={NOTIFICATION_TYPE_ICON[notification.type]} size="xs" filled />
        </span>
      </span>

      <span className="min-w-0 flex-1">
        <span className="block text-body text-ink">
          {actor ? (
            <strong className="font-semibold">{actor.display_name}</strong>
          ) : (
            <strong className="font-semibold">Klect</strong>
          )}{' '}
          <span className="text-ink-2">{text}</span>
        </span>
        <span className="mt-0.5 block text-caption text-ink-3">
          {shortTimeAgo(notification.created_at)} ago
        </span>
      </span>

      {unread ? (
        <span
          className="mt-2 size-2 shrink-0 rounded-full bg-accent"
          aria-label="Unread"
          title="Unread"
        />
      ) : null}
    </Link>
  );
}
