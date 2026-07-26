import type { Database } from '@/lib/database.types';
import { closeupHref, collectionHref, itemHref, postHref, subcollectionHref } from '@/lib/routes';

export type EntityType = Database['public']['Enums']['entity_type'];
export type Visibility = Database['public']['Enums']['visibility'];
export type ReportReason = Database['public']['Enums']['report_reason'];
export type AppRole = Database['public']['Enums']['app_role'];
export type ModAction = Database['public']['Enums']['mod_action'];
export type ReportStatus = Database['public']['Enums']['report_status'];
export type NotificationType = Database['public']['Enums']['notification_type'];
export type MessageKind = Database['public']['Enums']['message_kind'];
export type ConversationKind = Database['public']['Enums']['conversation_kind'];
export type CallKind = Database['public']['Enums']['call_kind'];
export type CallStatus = Database['public']['Enums']['call_status'];
export type PostKind = Database['public']['Enums']['post_kind'];

export const ENTITY_TYPES = [
  'collection',
  'subcollection',
  'item',
  'post',
  'comment',
] as const satisfies readonly EntityType[];

/** Types that carry a cover image and appear in the surf grid. */
export const SURFACE_ENTITY_TYPES = [
  'collection',
  'subcollection',
  'item',
] as const satisfies readonly EntityType[];

export type SurfaceEntityType = (typeof SURFACE_ENTITY_TYPES)[number];

export const REPORT_REASONS = [
  'spam',
  'nudity',
  'harassment',
  'hate',
  'violence',
  'self_harm',
  'ip_violation',
  'misinformation',
  'impersonation',
  'other',
] as const satisfies readonly ReportReason[];

export const REPORT_REASON_LABELS: Record<ReportReason, string> = {
  spam: 'Spam or scam',
  nudity: 'Nudity or sexual content',
  harassment: 'Harassment or bullying',
  hate: 'Hate speech',
  violence: 'Violence or threats',
  self_harm: 'Self-harm',
  ip_violation: 'Intellectual property',
  misinformation: 'Misinformation',
  impersonation: 'Impersonation',
  other: 'Something else',
};

export const VISIBILITY_LABELS: Record<Visibility, string> = {
  public: 'Public',
  followers: 'Followers only',
  private: 'Only me',
};

/** The physical table behind each polymorphic entity — used for realtime filters. */
export const ENTITY_TABLE = {
  collection: 'collections',
  subcollection: 'subcollections',
  item: 'items',
  post: 'posts',
  comment: 'comments',
} as const satisfies Record<EntityType, string>;

export const ENTITY_LABEL: Record<EntityType, string> = {
  collection: 'Collection',
  subcollection: 'Subcollection',
  item: 'Item',
  post: 'Post',
  comment: 'Comment',
};

export function isEntityType(value: unknown): value is EntityType {
  return typeof value === 'string' && (ENTITY_TYPES as readonly string[]).includes(value);
}

export function isSurfaceEntityType(value: unknown): value is SurfaceEntityType {
  return (
    typeof value === 'string' && (SURFACE_ENTITY_TYPES as readonly string[]).includes(value)
  );
}

/**
 * The identity used by the optimistic engine, the realtime hooks and every
 * cache. `profile` is not an `entity_type` in the database — follows live on
 * their own RPC — but it shares the machinery, so it shares the key space.
 */
export type SocialType = EntityType | 'profile';

export function entityKey(type: SocialType, id: string): string {
  return `${type}:${id}`;
}

export function parseEntityKey(key: string): { type: SocialType; id: string } | null {
  const separator = key.indexOf(':');
  if (separator < 0) return null;
  const type = key.slice(0, separator);
  const id = key.slice(separator + 1);
  if (type !== 'profile' && !isEntityType(type)) return null;
  if (!id) return null;
  return { type: type as SocialType, id };
}

/** The canonical, deep-linkable page for an entity. */
export function entityHref(type: EntityType, id: string): string {
  switch (type) {
    case 'collection':
      return collectionHref(id);
    case 'subcollection':
      return subcollectionHref(id);
    case 'item':
      return itemHref(id);
    case 'post':
      // Thread-first Pulse (W3): a post's canonical page is its thread.
      return postHref(id);
    case 'comment':
      return closeupHref(type, id);
  }
}

/** The modal-over-grid route. Intercepted; falls back to a full page. */
export function entityCloseupHref(type: EntityType, id: string): string {
  return closeupHref(type, id);
}
