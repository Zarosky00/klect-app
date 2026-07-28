import type { EntityType } from '@/lib/entities';

export type SocialActivityKind =
  | 'post'
  | 'quote'
  | 'comment'
  | 'delete'
  | 'like'
  | 'save'
  | 'repost';

export interface SocialActivityMutation {
  kind: SocialActivityKind;
  type: EntityType;
  id: string;
  /** Author/actor when known; profile consumers can ignore unrelated events. */
  actorId?: string;
}
type Listener = (mutation: SocialActivityMutation) => void;
const listeners = new Set<Listener>();

/**
 * A tiny typed invalidation bus. It deliberately carries no cached payload:
 * server envelopes remain authoritative and mounted feeds/profiles decide
 * whether to patch optimistically or reload their current cursor head.
 */
export function emitSocialActivityMutation(mutation: SocialActivityMutation): void {
  for (const listener of [...listeners]) listener(mutation);
}

export function subscribeSocialActivity(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
