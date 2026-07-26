import { entityHref, isEntityType, type NotificationType } from '@/lib/entities';
import { closeupHref, conversationHref, postHref, profileHref, routes } from '@/lib/routes';
import type { IconName } from '@/components/ui/Icon';
import type { NotificationEntry } from './queries';

/**
 * Per-type presentation of a notification, shared by the Alerts feed and the
 * shell-level arrival banner so the two can never disagree about what a
 * "like" looks like or where it deep-links.
 */

export const NOTIFICATION_TYPE_ICON: Record<NotificationType, IconName> = {
  like: 'heart',
  save: 'bookmark',
  repost: 'repost',
  comment: 'comment',
  reply: 'comment',
  mention: 'comment',
  follow: 'user',
  message: 'mail',
  call: 'activity',
  match: 'users',
  system: 'bell',
  moderation: 'shield',
};

/** Action colours are semantic and never swapped (DESIGN_SYSTEM §1). */
export const NOTIFICATION_TYPE_TONE: Record<NotificationType, string> = {
  like: 'text-like bg-like-subtle',
  save: 'text-save bg-save-subtle',
  repost: 'text-repost bg-repost-subtle',
  comment: 'text-comment bg-comment-subtle',
  reply: 'text-comment bg-comment-subtle',
  mention: 'text-comment bg-comment-subtle',
  follow: 'text-accent bg-accent-subtle',
  message: 'text-info bg-comment-subtle',
  call: 'text-info bg-comment-subtle',
  match: 'text-accent bg-accent-subtle',
  system: 'text-ink-2 bg-surface-3',
  moderation: 'text-warning bg-danger-subtle',
};

export const NOTIFICATION_FALLBACK_TEXT: Record<NotificationType, string> = {
  like: 'liked something of yours',
  save: 'saved something of yours',
  repost: 'reposted something of yours',
  comment: 'commented on your collection',
  reply: 'replied to you',
  mention: 'mentioned you',
  follow: 'started following you',
  message: 'sent you a message',
  call: 'called you',
  match: 'is a strong taste match',
  system: 'Klect has an update for you',
  moderation: 'A moderator acted on your content',
};

/** Where tapping a notification takes you. */
export function notificationTargetHref(entry: NotificationEntry): string {
  const { notification, actor } = entry;
  switch (notification.type) {
    case 'follow':
    case 'match':
      return actor ? profileHref(actor.username) : routes.matches;
    case 'message':
    case 'call':
      return notification.conversation_id
        ? conversationHref(notification.conversation_id)
        : routes.messages;
    case 'comment':
    case 'reply':
    case 'mention':
      // Comments live inside the closeup of whatever they hang off — except a
      // post's, whose discussion is the thread page (W3).
      return isEntityType(notification.entity_type) && notification.entity_id
        ? notification.entity_type === 'post'
          ? postHref(notification.entity_id)
          : closeupHref(notification.entity_type, notification.entity_id)
        : routes.notifications;
    default:
      return isEntityType(notification.entity_type) && notification.entity_id
        ? entityHref(notification.entity_type, notification.entity_id)
        : routes.notifications;
  }
}
