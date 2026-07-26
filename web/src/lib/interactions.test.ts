import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  InteractionStore,
  createToggleRunner,
  type ToggleRunner,
} from '@/lib/interactions';
import type { ToggleResult } from '@/lib/types';

/**
 * A stand-in for the database. It behaves exactly like the real toggle RPCs:
 * idempotent flips that always answer with the authoritative `{active, count}`.
 */
function makeServer(initial: { active: boolean; count: number }) {
  const state = { ...initial };
  let calls = 0;
  const runner: ToggleRunner = async () => {
    calls += 1;
    // A real round trip is never instant; make sure the engine survives one.
    await new Promise((resolve) => setTimeout(resolve, 5));
    state.active = !state.active;
    state.count = Math.max(0, state.count + (state.active ? 1 : -1));
    return { active: state.active, count: state.count } satisfies ToggleResult;
  };
  return {
    runner,
    get calls() {
      return calls;
    },
    get state() {
      return { ...state };
    },
  };
}

const ENTITY = { type: 'item' as const, id: 'item-1' };

describe('InteractionStore — the optimistic engine', () => {
  beforeEach(() => {
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('applies the delta before the network answers', () => {
    const server = makeServer({ active: false, count: 10 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 5 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 10, viewerLiked: false });

    store.toggle('like', ENTITY.type, ENTITY.id);

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(true);
    expect(snapshot.likeCount).toBe(11);
    expect(server.calls).toBe(0); // nothing has left the browser yet
  });

  it('converges on the correct state and count after 10 rapid clicks', async () => {
    const server = makeServer({ active: false, count: 10 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 5 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 10, viewerLiked: false });

    // Ten taps in quick succession: odd count, so the user ends up liked.
    for (let i = 0; i < 9; i += 1) {
      store.toggle('like', ENTITY.type, ENTITY.id);
    }

    // Every intermediate render is already correct.
    expect(store.getSnapshot(ENTITY.type, ENTITY.id).liked).toBe(true);

    await store.settled();

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(true);
    expect(snapshot.likeCount).toBe(11);
    expect(snapshot.pending).toBe(false);

    // The server agrees, and it was told once — not nine times.
    expect(server.state).toEqual({ active: true, count: 11 });
    expect(server.calls).toBeLessThanOrEqual(2);
  });

  it('converges back to the original state on an even number of clicks', async () => {
    const server = makeServer({ active: true, count: 42 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 5 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 42, viewerLiked: true });

    for (let i = 0; i < 10; i += 1) {
      store.toggle('like', ENTITY.type, ENTITY.id);
    }

    await store.settled();

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(true);
    expect(snapshot.likeCount).toBe(42);
    expect(server.state).toEqual({ active: true, count: 42 });
    // Nothing changed, so nothing needed saying.
    expect(server.calls).toBe(0);
  });

  it('absorbs taps that land while a request is in flight', async () => {
    const server = makeServer({ active: false, count: 0 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 1 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 0, viewerLiked: false });

    store.toggle('like', ENTITY.type, ENTITY.id); // → wants liked
    await new Promise((resolve) => setTimeout(resolve, 3)); // request departs
    store.toggle('like', ENTITY.type, ENTITY.id); // → changes mind mid-flight

    await store.settled();

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(false);
    expect(snapshot.likeCount).toBe(0);
    expect(server.state).toEqual({ active: false, count: 0 });
  });

  it('rolls back to the last authoritative state when the RPC fails', async () => {
    const failing: ToggleRunner = async () => {
      throw new Error('42501');
    };
    const errors: unknown[] = [];
    const store = new InteractionStore({
      runner: failing,
      coalesceMs: 1,
      onError: (error) => errors.push(error),
    });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 7, viewerLiked: false });

    store.toggle('like', ENTITY.type, ENTITY.id);
    expect(store.getSnapshot(ENTITY.type, ENTITY.id).likeCount).toBe(8);

    await store.settled();

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(false);
    expect(snapshot.likeCount).toBe(7);
    expect(errors).toHaveLength(1);
  });

  it('never lets a realtime counter stomp a pending optimistic update', async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const runner: ToggleRunner = async () => {
      await gate;
      return { active: true, count: 101 };
    };

    const store = new InteractionStore({ runner, coalesceMs: 1 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 100, viewerLiked: false });

    store.toggle('like', ENTITY.type, ENTITY.id);
    await new Promise((resolve) => setTimeout(resolve, 3));

    // A realtime UPDATE arrives carrying the pre-toggle count.
    store.applyCounters(ENTITY.type, ENTITY.id, { like_count: 100, view_count: 9 });

    // The like count holds the optimistic value; unrelated counters still update.
    expect(store.getSnapshot(ENTITY.type, ENTITY.id).likeCount).toBe(101);
    expect(store.getSnapshot(ENTITY.type, ENTITY.id).viewCount).toBe(9);

    release();
    await store.settled();

    expect(store.getSnapshot(ENTITY.type, ENTITY.id).likeCount).toBe(101);
  });

  it('notifies subscribers on every state change', () => {
    const server = makeServer({ active: false, count: 3 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 50 });
    store.ensure(ENTITY.type, ENTITY.id, { likeCount: 3 });

    const listener = vi.fn();
    const unsubscribe = store.subscribe(ENTITY.type, ENTITY.id, listener);

    store.toggle('like', ENTITY.type, ENTITY.id);
    expect(listener).toHaveBeenCalled();

    unsubscribe();
    listener.mockClear();
    store.toggle('save', ENTITY.type, ENTITY.id);
    expect(listener).not.toHaveBeenCalled();
  });

  it('keeps like, save and repost independent on the same entity', async () => {
    const server = makeServer({ active: false, count: 0 });
    const store = new InteractionStore({ runner: server.runner, coalesceMs: 1 });
    store.ensure(ENTITY.type, ENTITY.id, {
      likeCount: 5,
      saveCount: 2,
      repostCount: 0,
    });

    store.toggle('like', ENTITY.type, ENTITY.id);
    store.toggle('save', ENTITY.type, ENTITY.id);

    const snapshot = store.getSnapshot(ENTITY.type, ENTITY.id);
    expect(snapshot.liked).toBe(true);
    expect(snapshot.saved).toBe(true);
    expect(snapshot.reposted).toBe(false);
    expect(snapshot.repostCount).toBe(0);
  });
});

describe('createToggleRunner', () => {
  it('routes each kind to its RPC and refuses invalid combinations', async () => {
    const calls: string[] = [];
    const runner = createToggleRunner({
      toggleLike: async (type, id) => {
        calls.push(`like:${type}:${id}`);
        return { active: true, count: 1 };
      },
      toggleSave: async (type, id, note) => {
        calls.push(`save:${type}:${id}:${note ?? ''}`);
        return { active: true, count: 1 };
      },
      toggleRepost: async (type, id, quote) => {
        calls.push(`repost:${type}:${id}:${quote ?? ''}`);
        return { active: true, count: 1 };
      },
      toggleFollow: async (userId) => {
        calls.push(`follow:${userId}`);
        return { active: true, count: 1 };
      },
    });

    await runner({ kind: 'like', type: 'collection', id: 'c1' });
    await runner({ kind: 'save', type: 'item', id: 'i1', note: 'later' });
    await runner({ kind: 'repost', type: 'subcollection', id: 's1', quote: 'look' });
    await runner({ kind: 'follow', type: 'profile', id: 'u1' });

    expect(calls).toEqual([
      'like:collection:c1',
      'save:item:i1:later',
      'repost:subcollection:s1:look',
      'follow:u1',
    ]);

    await expect(runner({ kind: 'like', type: 'profile', id: 'u1' })).rejects.toThrow();
  });
});
