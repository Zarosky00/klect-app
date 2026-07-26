'use client';

import { usePathname, useRouter } from 'next/navigation';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { AnimatePresence, motion, useReducedMotion, type PanInfo } from 'framer-motion';
import { countUnreadNotifications, markNotificationsRead } from '@/lib/api';
import { cn } from '@/lib/cn';
import type { NotificationType } from '@/lib/entities';
import { loadMutedTypes, subscribeMutedTypes } from '@/lib/notification-prefs';
import { routes } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { NotificationRow } from '@/lib/types';
import { curve, gesture, reducedTransition } from '@/design/motion';
import { duration } from '@/design/tokens.g';
import { Avatar } from '@/components/ui/Avatar';
import { Icon } from '@/components/ui/Icon';
import {
  NOTIFICATION_FALLBACK_TEXT,
  NOTIFICATION_TYPE_ICON,
  NOTIFICATION_TYPE_TONE,
  notificationTargetHref,
} from '@/components/social/notification-meta';
import {
  hydrateNotification,
  type Client,
  type NotificationEntry,
} from '@/components/social/queries';
import { useSession } from '@/providers/session-provider';

/**
 * The shell-level notification listener — mounted once in the signed-in (app)
 * layout, exactly like `InteractionsProvider`, so the unread badge and the
 * arrival banner are live from the first paint of ANY page, not from the
 * first visit to /notifications.
 *
 * One realtime channel per session (never one per surface):
 *   · badge — seeded by `countUnreadNotifications` (a head-count, counts come
 *     from the database), incremented per arrival, cleared on /notifications;
 *   · banner — glass, avatar + verb + thumb, tap deep-links, auto-dismisses,
 *     suppressed on the page it would deep-link to and on /notifications;
 *   · feed — `NotificationsFeed` subscribes here instead of opening a second
 *     channel of its own.
 *
 * Per-type mutes (Settings → Notifications, a device preference) silence the
 * banner for that type; the rows still count and still land in the list.
 */

interface NotificationsContextValue {
  /** Live unread count for the Alerts badge. */
  unread: number;
  /** Register for hydrated realtime arrivals. Returns the unsubscribe. */
  subscribe: (listener: (entry: NotificationEntry) => void) => () => void;
}

const NotificationsContext = createContext<NotificationsContextValue | null>(null);

/** How long the banner lingers — same dwell as a toast. */
const BANNER_MS = duration.deliberate * 10;

interface BannerState {
  entry: NotificationEntry;
  href: string;
  thumbPath: string | null;
}

/** Best-effort cover lookup so the banner can show what was acted on. */
async function fetchNotificationThumb(
  client: Client,
  row: NotificationRow,
): Promise<string | null> {
  if (!row.entity_id || !row.entity_type) return null;
  if (row.entity_type === 'collection') {
    const { data } = await client
      .from('collections')
      .select('cover_path')
      .eq('id', row.entity_id)
      .maybeSingle();
    return data?.cover_path ?? null;
  }
  if (row.entity_type === 'subcollection') {
    const { data } = await client
      .from('subcollections')
      .select('cover_path')
      .eq('id', row.entity_id)
      .maybeSingle();
    return data?.cover_path ?? null;
  }
  if (row.entity_type === 'item') {
    const { data } = await client
      .from('items')
      .select('cover_path')
      .eq('id', row.entity_id)
      .maybeSingle();
    return data?.cover_path ?? null;
  }
  if (row.entity_type === 'post') {
    const { data } = await client
      .from('post_media')
      .select('storage_path')
      .eq('post_id', row.entity_id)
      .order('position', { ascending: true })
      .limit(1)
      .maybeSingle();
    return data?.storage_path ?? null;
  }
  return null;
}

export function NotificationsProvider({ children }: { children: ReactNode }) {
  const { supabase, user } = useSession();
  const pathname = usePathname();

  const [unread, setUnread] = useState(0);
  const [banner, setBanner] = useState<BannerState | null>(null);

  const listeners = useRef(new Set<(entry: NotificationEntry) => void>());
  const mutedTypes = useRef<Set<NotificationType>>(new Set());
  const pathnameRef = useRef(pathname);
  pathnameRef.current = pathname;
  const bannerTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const userId = user?.id ?? null;

  useEffect(() => {
    mutedTypes.current = loadMutedTypes();
    return subscribeMutedTypes(() => {
      mutedTypes.current = loadMutedTypes();
    });
  }, []);

  const dismissBanner = useCallback(() => {
    if (bannerTimer.current) clearTimeout(bannerTimer.current);
    bannerTimer.current = null;
    setBanner(null);
  }, []);

  /* One viewer-scoped channel for the whole app shell. */
  useEffect(() => {
    if (!userId) {
      setUnread(0);
      setBanner(null);
      return;
    }

    let active = true;
    void countUnreadNotifications(supabase)
      .then((count) => {
        if (active) setUnread(count);
      })
      .catch(() => {
        // The badge starts at 0 and catches up on the next arrival.
      });

    const handleArrival = async (row: NotificationRow) => {
      const entry = await hydrateNotification(supabase, row).catch(
        (): NotificationEntry => ({ notification: row, actor: null }),
      );
      if (!active) return;

      for (const listener of listeners.current) listener(entry);

      // On the Alerts page the list itself is the surface — no badge, no banner.
      if (pathnameRef.current === routes.notifications) return;
      setUnread((current) => current + 1);

      // Per-type mute is a banner filter, never a data filter.
      if (mutedTypes.current.has(row.type)) return;
      const href = notificationTargetHref(entry);
      // Suppressed on the originating page: you are already looking at it.
      if (href === pathnameRef.current) return;

      const thumbPath = await fetchNotificationThumb(supabase, row).catch(() => null);
      if (!active) return;
      if (bannerTimer.current) clearTimeout(bannerTimer.current);
      setBanner({ entry, href, thumbPath });
      bannerTimer.current = setTimeout(() => setBanner(null), BANNER_MS);
    };

    const channel = supabase
      .channel(`notifications:shell:${userId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'notifications',
          filter: `user_id=eq.${userId}`,
        },
        (payload) => {
          void handleArrival(payload.new as NotificationRow);
        },
      )
      .subscribe();

    return () => {
      active = false;
      if (bannerTimer.current) clearTimeout(bannerTimer.current);
      bannerTimer.current = null;
      void supabase.removeChannel(channel);
    };
  }, [supabase, userId]);

  /* Visiting the Alerts page clears the badge (the feed marks rows read). */
  useEffect(() => {
    if (pathname === routes.notifications) {
      setUnread(0);
      dismissBanner();
    }
  }, [dismissBanner, pathname]);

  const subscribe = useCallback((listener: (entry: NotificationEntry) => void) => {
    listeners.current.add(listener);
    return () => {
      listeners.current.delete(listener);
    };
  }, []);

  const onBannerRead = useCallback(
    (entry: NotificationEntry) => {
      void markNotificationsRead(supabase, [entry.notification.id]).catch(() => {
        // The Alerts page shows the true state either way.
      });
      setUnread((current) => Math.max(0, current - 1));
      dismissBanner();
    },
    [dismissBanner, supabase],
  );

  const value = useMemo<NotificationsContextValue>(
    () => ({ unread, subscribe }),
    [subscribe, unread],
  );

  return (
    <NotificationsContext.Provider value={value}>
      {children}
      <NotificationBanner banner={banner} onDismiss={dismissBanner} onRead={onBannerRead} />
    </NotificationsContext.Provider>
  );
}

export function useNotifications(): NotificationsContextValue {
  const context = useContext(NotificationsContext);
  if (!context) {
    throw new Error('useNotifications must be used inside <NotificationsProvider/>.');
  }
  return context;
}

/* ── the arrival banner ───────────────────────────────────────────────────── */

function NotificationBanner({
  banner,
  onDismiss,
  onRead,
}: {
  banner: BannerState | null;
  onDismiss: () => void;
  onRead: (entry: NotificationEntry) => void;
}) {
  const router = useRouter();
  const reduced = useReducedMotion();

  const open = banner !== null;
  const entry = banner?.entry ?? null;
  const notification = entry?.notification ?? null;
  const actor = entry?.actor ?? null;
  const text = notification
    ? (notification.body ?? NOTIFICATION_FALLBACK_TEXT[notification.type])
    : '';
  const thumbSrc = banner?.thumbPath ? mediaUrl(banner.thumbPath) : null;

  const onDragEnd = (_event: unknown, info: PanInfo) => {
    // Swipe up (or a decisive flick) dismisses, mirroring the mobile banner.
    // Same thresholds a sheet uses — one definition, one feel.
    if (
      info.offset.y < -gesture.sheetDismissPx ||
      info.velocity.y < -gesture.sheetDismissVelocity
    ) {
      onDismiss();
    }
  };

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-0 z-toast flex justify-center p-3 pt-[calc(env(safe-area-inset-top)+var(--k-space-3))]"
    >
      <AnimatePresence>
        {open && entry && notification ? (
          <motion.div
            key={notification.id}
            role="status"
            drag={reduced ? false : 'y'}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0.6, bottom: 0 }}
            onDragEnd={onDragEnd}
            initial={{ y: '-120%', opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: '-120%', opacity: 0 }}
            transition={reduced ? reducedTransition : curve.medium}
            className="pointer-events-auto w-full max-w-96"
          >
            <button
              type="button"
              onClick={() => {
                if (!banner) return;
                onRead(entry);
                router.push(banner.href);
              }}
              className={cn(
                'glass focus-ring flex w-full items-center gap-3 rounded-lg border border-line',
                'p-3 text-left shadow-high',
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
                <span className="block truncate text-body text-ink">
                  <strong className="font-semibold">
                    {actor?.display_name ?? 'Klect'}
                  </strong>{' '}
                  <span className="text-ink-2">{text}</span>
                </span>
                <span className="mt-0.5 block text-caption text-ink-3">Tap to view</span>
              </span>

              {thumbSrc ? (
                <span className="block size-10 shrink-0 overflow-hidden rounded-md border border-line-subtle">
                  {/* eslint-disable-next-line @next/next/no-img-element -- a
                      40px thumb; the optimizer round-trip costs more than it
                      saves here. */}
                  <img src={thumbSrc} alt="" className="size-full object-cover" />
                </span>
              ) : null}
            </button>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}
