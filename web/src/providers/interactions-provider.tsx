'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useSyncExternalStore,
  type ReactNode,
} from 'react';
import {
  addComment as addCommentRpc,
  recordView as recordViewRpc,
  toggleFollow,
  toggleLike,
  toggleRepost,
  toggleSave,
} from '@/lib/api';
import { ENTITY_TABLE, type EntityType, type SocialType } from '@/lib/entities';
import {
  InteractionStore,
  createToggleRunner,
  type SocialSeed,
  type SocialSnapshot,
  type ToggleKind,
} from '@/lib/interactions';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

const InteractionsContext = createContext<InteractionStore | null>(null);

export function InteractionsProvider({ children }: { children: ReactNode }) {
  const { supabase } = useSession();
  const { fromError } = useToast();

  const store = useMemo(
    () =>
      new InteractionStore({
        onError: (error) => fromError(error),
      }),
    // The store must outlive re-renders; `fromError` is stable from the provider.
    [fromError],
  );

  useEffect(() => {
    store.setRunner(
      createToggleRunner({
        toggleLike: (type, id) => toggleLike(supabase, type, id),
        toggleSave: (type, id, note) => toggleSave(supabase, type, id, note),
        toggleRepost: (type, id, quote) => toggleRepost(supabase, type, id, quote),
        toggleFollow: (userId) => toggleFollow(supabase, userId),
      }),
    );
  }, [store, supabase]);

  return (
    <InteractionsContext.Provider value={store}>{children}</InteractionsContext.Provider>
  );
}

export function useInteractionStore(): InteractionStore {
  const store = useContext(InteractionsContext);
  if (!store) {
    throw new Error('useInteractionStore must be used inside <InteractionsProvider/>.');
  }
  return store;
}

export interface EntitySocial extends SocialSnapshot {
  like: () => void;
  save: (note?: string) => void;
  repost: (quote?: string) => void;
  follow: () => void;
  toggle: (kind: ToggleKind) => void;
}

/**
 * Subscribe a component to one entity's social state.
 *
 * `seed` is applied on first sight and re-applied whenever the server values
 * change — but never over the top of a pending optimistic update.
 */
export function useEntitySocial(
  type: SocialType,
  id: string,
  seed?: SocialSeed,
): EntitySocial {
  const store = useInteractionStore();

  // Fill the record before the first read so the first paint has real numbers.
  const seeded = useRef(false);
  if (!seeded.current) {
    store.ensure(type, id, seed);
    seeded.current = true;
  }

  const seedSignature = seed ? JSON.stringify(seed) : '';
  useEffect(() => {
    if (!seed) return;
    store.seed(type, id, seed);
    // `seedSignature` is the value-identity of `seed`; re-seed only on change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store, type, id, seedSignature]);

  const subscribe = useCallback(
    (listener: () => void) => store.subscribe(type, id, listener),
    [store, type, id],
  );
  const getSnapshot = useCallback(() => store.getSnapshot(type, id), [store, type, id]);

  const snapshot = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);

  return useMemo<EntitySocial>(
    () => ({
      ...snapshot,
      like: () => store.toggle('like', type, id),
      save: (note?: string) =>
        store.toggle('save', type, id, note === undefined ? undefined : { note }),
      repost: (quote?: string) =>
        store.toggle('repost', type, id, quote === undefined ? undefined : { quote }),
      follow: () => store.toggle('follow', type, id),
      toggle: (kind: ToggleKind) => store.toggle(kind, type, id),
    }),
    [id, snapshot, store, type],
  );
}

/** Follow state for a profile, sharing the same engine. */
export function useFollowState(userId: string, seed?: SocialSeed) {
  const social = useEntitySocial('profile', userId, seed);
  return {
    following: social.following,
    followerCount: social.followerCount,
    pending: social.pending,
    toggle: social.follow,
  };
}

/**
 * Live counters. BACKEND_API §3: never subscribe to `likes` — subscribe to
 * `UPDATE` on the entity row, because one event carries every fresh counter.
 *
 * Use this on detail/closeup views. Do NOT mount it once per masonry tile: a
 * channel per tile will exhaust the realtime connection budget.
 */
export function useRealtimeEntity(
  type: EntityType,
  id: string,
  options: { enabled?: boolean } = {},
): void {
  const enabled = options.enabled ?? true;
  const { supabase } = useSession();
  const store = useInteractionStore();

  useEffect(() => {
    if (!enabled || !id) return;
    const table = ENTITY_TABLE[type];
    const channel = supabase
      .channel(`entity:${type}:${id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table, filter: `id=eq.${id}` },
        (payload) => {
          store.applyCounters(type, id, payload.new as Record<string, unknown>);
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [enabled, id, store, supabase, type]);
}

/** Live follower count for a profile row. */
export function useRealtimeProfile(userId: string, enabled = true): void {
  const { supabase } = useSession();
  const store = useInteractionStore();

  useEffect(() => {
    if (!enabled || !userId) return;
    const channel = supabase
      .channel(`profile:${userId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'profiles', filter: `id=eq.${userId}` },
        (payload) => {
          store.applyCounters('profile', userId, payload.new as Record<string, unknown>);
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [enabled, store, supabase, userId]);
}

/**
 * Records a view once per mount. The server dedupes per viewer per day, so a
 * refresh cannot inflate the number.
 */
export function useRecordView(type: EntityType, id: string, enabled = true): void {
  const { supabase } = useSession();
  const store = useInteractionStore();
  const done = useRef('');

  useEffect(() => {
    if (!enabled || !id) return;
    const key = `${type}:${id}`;
    if (done.current === key) return;
    done.current = key;
    void recordViewRpc(supabase, type, id)
      .then((count) => store.setViewCount(type, id, count))
      .catch(() => {
        // A failed view record is never worth interrupting the reader.
      });
  }, [enabled, id, store, supabase, type]);
}

/** Optimistic comment posting: the count moves before the round trip lands. */
export function useAddComment() {
  const { supabase } = useSession();
  const store = useInteractionStore();
  const { fromError } = useToast();

  return useCallback(
    async (
      type: EntityType,
      id: string,
      body: string,
      parentId?: string,
    ): Promise<{ id: string } | null> => {
      const before = store.getSnapshot(type, id).commentCount;
      store.setCommentCount(type, id, before + 1);
      try {
        const result = await addCommentRpc(supabase, type, id, body, parentId);
        store.setCommentCount(type, id, result.count);
        return { id: result.id };
      } catch (error) {
        store.setCommentCount(type, id, before);
        fromError(error);
        return null;
      }
    },
    [fromError, store, supabase],
  );
}
