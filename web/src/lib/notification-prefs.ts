import type { NotificationType } from '@/lib/entities';

/**
 * Per-type notification mutes — a DEVICE preference, mirroring mobile's model:
 * persisted client-side (localStorage), never a server column. Muting a type
 * silences its arrival banner and badge bumps on this browser; the rows still
 * land in the Alerts list, so nothing is ever lost.
 */

const STORAGE_KEY = 'klect:muted-notification-types:v1';
const CHANGE_EVENT = 'klect:notification-prefs-changed';

/** The types a person may mute. System and moderation notices never mute. */
export const MUTABLE_NOTIFICATION_TYPES = [
  'like',
  'save',
  'repost',
  'comment',
  'reply',
  'mention',
  'follow',
  'message',
  'call',
  'match',
] as const satisfies readonly NotificationType[];

export type MutableNotificationType = (typeof MUTABLE_NOTIFICATION_TYPES)[number];

export const NOTIFICATION_TYPE_LABELS: Record<MutableNotificationType, string> = {
  like: 'Likes',
  save: 'Saves',
  repost: 'Reposts',
  comment: 'Comments',
  reply: 'Replies',
  mention: 'Mentions',
  follow: 'New followers',
  message: 'Messages',
  call: 'Calls',
  match: 'Taste matches',
};

export const NOTIFICATION_TYPE_BLURBS: Record<MutableNotificationType, string> = {
  like: 'Someone liked a collection, item or post of yours.',
  save: 'Someone saved something of yours to their shelves.',
  repost: 'Someone reposted or quoted your content.',
  comment: 'New comments on your collections, items and posts.',
  reply: 'Replies to your comments.',
  mention: 'You were mentioned in a comment or post.',
  follow: 'A collector started following you.',
  message: 'New chat messages while you are elsewhere in the app.',
  call: 'Incoming call alerts.',
  match: 'The matching engine found a strong taste overlap.',
};

function isNotificationType(value: unknown): value is NotificationType {
  return (
    typeof value === 'string' &&
    (MUTABLE_NOTIFICATION_TYPES as readonly string[]).includes(value)
  );
}

/** SSR-safe: on the server there is no storage, so nothing is muted. */
export function loadMutedTypes(): Set<NotificationType> {
  if (typeof window === 'undefined') return new Set();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return new Set();
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed.filter(isNotificationType));
  } catch {
    return new Set();
  }
}

export function saveMutedTypes(muted: ReadonlySet<NotificationType>): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify([...muted]));
  } catch {
    // Storage full or blocked — the toggle still works for this session.
  }
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

/** Fires on same-tab saves and on cross-tab storage changes. */
export function subscribeMutedTypes(listener: () => void): () => void {
  if (typeof window === 'undefined') return () => {};
  const onStorage = (event: StorageEvent) => {
    if (event.key === null || event.key === STORAGE_KEY) listener();
  };
  window.addEventListener(CHANGE_EVENT, listener);
  window.addEventListener('storage', onStorage);
  return () => {
    window.removeEventListener(CHANGE_EVENT, listener);
    window.removeEventListener('storage', onStorage);
  };
}
