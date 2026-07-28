/**
 * THE OPTIMISTIC ENGINE.
 *
 * Same semantics as the Flutter client, deliberately: instant local delta →
 * RPC → reconcile with the authoritative `{active, count}` → roll back on
 * error. Rapid clicks coalesce.
 *
 * The whole design rests on one invariant:
 *
 *     displayed = f(serverActive, serverCount, desired)
 *
 *     active = desired
 *     count  = serverCount + (desired === serverActive ? 0 : desired ? +1 : -1)
 *
 * `desired` is the user's intent. `serverActive`/`serverCount` are the last
 * authoritative values the database gave us. Because the toggle RPCs are
 * idempotent *flips*, driving `serverActive` to `desired` needs exactly one
 * call whenever they differ — so ten taps in two seconds produce at most two
 * round trips and always converge on the right state and the right count.
 *
 * A count can therefore never flicker back to a stale server value: the
 * pending delta is re-derived after every reconciliation instead of being
 * stored separately.
 *
 * This module is framework-free on purpose so it can be unit tested without a
 * DOM. See `src/lib/interactions.test.ts`.
 */
import { duration } from '@/design/tokens.g';
import type { EntityType, SocialType } from '@/lib/entities';
import { entityKey } from '@/lib/entities';
import type { ToggleResult } from '@/lib/types';

export type ToggleKind = 'like' | 'save' | 'repost' | 'follow';

export const TOGGLE_KINDS: readonly ToggleKind[] = ['like', 'save', 'repost', 'follow'];

export interface ToggleRequest {
  kind: ToggleKind;
  type: SocialType;
  id: string;
  /** `toggle_save` note / `toggle_repost` quote — only read when activating. */
  note?: string;
  quote?: string;
}

/** Injected so tests can drive the engine without a network. */
export type ToggleRunner = (request: ToggleRequest) => Promise<ToggleResult>;

export interface SocialSeed {
  likeCount?: number;
  saveCount?: number;
  repostCount?: number;
  quoteCount?: number;
  followerCount?: number;
  commentCount?: number;
  viewCount?: number;
  childCount?: number;
  viewerLiked?: boolean;
  viewerSaved?: boolean;
  viewerReposted?: boolean;
  viewerFollows?: boolean;
}

/** What a component renders. Identity is stable until something changes. */
export interface SocialSnapshot {
  type: SocialType;
  id: string;
  liked: boolean;
  saved: boolean;
  reposted: boolean;
  following: boolean;
  likeCount: number;
  saveCount: number;
  repostCount: number;
  quoteCount: number;
  followerCount: number;
  commentCount: number;
  viewCount: number;
  childCount: number;
  /** True while any toggle for this entity is in flight. */
  pending: boolean;
}

interface KindState {
  serverActive: boolean;
  serverCount: number;
  desired: boolean;
  inFlight: boolean;
  note?: string;
  quote?: string;
}

interface EntityRecord {
  type: SocialType;
  id: string;
  kinds: Record<ToggleKind, KindState>;
  commentCount: number;
  viewCount: number;
  childCount: number;
  quoteCount: number;
}

export interface InteractionErrorContext {
  kind: ToggleKind;
  type: SocialType;
  id: string;
}

export interface InteractionStoreOptions {
  runner?: ToggleRunner;
  onError?: (error: unknown, context: InteractionErrorContext) => void;
  /**
   * Window before the first RPC fires. A double tap that nets to zero never
   * reaches the network at all. Token-derived; never a magic number.
   */
  coalesceMs?: number;
}

const newKindState = (active = false, count = 0): KindState => ({
  serverActive: active,
  serverCount: Math.max(0, count),
  desired: active,
  inFlight: false,
});

function displayedCount(state: KindState): number {
  if (state.desired === state.serverActive) return Math.max(0, state.serverCount);
  return Math.max(0, state.serverCount + (state.desired ? 1 : -1));
}

const notImplemented: ToggleRunner = () => {
  throw new Error(
    '[klect] InteractionStore has no runner. Wrap the tree in <InteractionsProvider/>.',
  );
};

export class InteractionStore {
  private readonly records = new Map<string, EntityRecord>();
  private readonly snapshots = new Map<string, SocialSnapshot>();
  private readonly listeners = new Map<string, Set<() => void>>();
  private readonly timers = new Map<string, ReturnType<typeof setTimeout>>();
  private runner: ToggleRunner;
  private readonly onError: ((error: unknown, ctx: InteractionErrorContext) => void) | undefined;
  private readonly coalesceMs: number;

  constructor(options: InteractionStoreOptions = {}) {
    this.runner = options.runner ?? notImplemented;
    this.onError = options.onError;
    this.coalesceMs = options.coalesceMs ?? duration.fast;
  }

  setRunner(runner: ToggleRunner): void {
    this.runner = runner;
  }

  /* ── reading ────────────────────────────────────────────────────────────── */

  /** Creates the record from `seed` if it does not exist. Safe during render. */
  ensure(type: SocialType, id: string, seed?: SocialSeed): SocialSnapshot {
    const key = entityKey(type, id);
    if (!this.records.has(key)) {
      this.records.set(key, this.buildRecord(type, id, seed));
      this.recompute(key);
    }
    return this.getSnapshot(type, id);
  }

  getSnapshot(type: SocialType, id: string): SocialSnapshot {
    const key = entityKey(type, id);
    const cached = this.snapshots.get(key);
    if (cached) return cached;
    this.records.set(key, this.buildRecord(type, id));
    return this.recompute(key);
  }

  subscribe(type: SocialType, id: string, listener: () => void): () => void {
    const key = entityKey(type, id);
    let set = this.listeners.get(key);
    if (!set) {
      set = new Set();
      this.listeners.set(key, set);
    }
    set.add(listener);
    return () => {
      set.delete(listener);
      if (set.size === 0) this.listeners.delete(key);
    };
  }

  /* ── writing ────────────────────────────────────────────────────────────── */

  /**
   * Adopt fresh server values. A kind with a pending intent is left alone —
   * that is what stops a stale payload from stomping an optimistic update.
   */
  seed(type: SocialType, id: string, seed: SocialSeed): void {
    const key = entityKey(type, id);
    const record = this.records.get(key);
    if (!record) {
      this.records.set(key, this.buildRecord(type, id, seed));
      this.recompute(key);
      this.emit(key);
      return;
    }

    const apply = (
      kind: ToggleKind,
      active: boolean | undefined,
      count: number | undefined,
    ): void => {
      const state = record.kinds[kind];
      if (state.inFlight || state.desired !== state.serverActive) return;
      if (typeof active === 'boolean') {
        state.serverActive = active;
        state.desired = active;
      }
      if (typeof count === 'number') state.serverCount = Math.max(0, count);
    };

    apply('like', seed.viewerLiked, seed.likeCount);
    apply('save', seed.viewerSaved, seed.saveCount);
    apply('repost', seed.viewerReposted, seed.repostCount);
    apply('follow', seed.viewerFollows, seed.followerCount);

    if (typeof seed.commentCount === 'number') record.commentCount = seed.commentCount;
    if (typeof seed.viewCount === 'number') record.viewCount = seed.viewCount;
    if (typeof seed.childCount === 'number') record.childCount = seed.childCount;
    if (typeof seed.quoteCount === 'number') record.quoteCount = Math.max(0, seed.quoteCount);

    this.recompute(key);
    this.emit(key);
  }

  /**
   * Realtime `UPDATE` on the entity row — one event carries every counter.
   * Ignored for any kind with work in flight; the RPC's own return value is
   * more authoritative than a row we might have raced.
   */
  applyCounters(
    type: SocialType,
    id: string,
    row: Record<string, unknown> | null | undefined,
  ): void {
    if (!row) return;
    const num = (value: unknown): number | undefined =>
      typeof value === 'number' ? value : undefined;

    this.seed(type, id, {
      likeCount: num(row['like_count']),
      saveCount: num(row['save_count']),
      repostCount: num(row['repost_count']),
      quoteCount: num(row['quote_count']),
      followerCount: num(row['follower_count']),
      commentCount: num(row['comment_count']),
      viewCount: num(row['view_count']),
    });
  }

  setCommentCount(type: SocialType, id: string, count: number): void {
    const key = entityKey(type, id);
    const record = this.records.get(key) ?? this.buildRecord(type, id);
    this.records.set(key, record);
    record.commentCount = Math.max(0, count);
    this.recompute(key);
    this.emit(key);
  }

  setViewCount(type: SocialType, id: string, count: number): void {
    const key = entityKey(type, id);
    const record = this.records.get(key) ?? this.buildRecord(type, id);
    this.records.set(key, record);
    record.viewCount = Math.max(0, count);
    this.recompute(key);
    this.emit(key);
  }

  /** The finger lifted. Flip intent now, talk to the server after. */
  toggle(
    kind: ToggleKind,
    type: SocialType,
    id: string,
    options?: { note?: string; quote?: string },
  ): void {
    const key = entityKey(type, id);
    const record = this.records.get(key) ?? this.buildRecord(type, id);
    this.records.set(key, record);

    const state = record.kinds[kind];
    state.desired = !state.desired;
    if (options?.note !== undefined) state.note = options.note;
    if (options?.quote !== undefined) state.quote = options.quote;

    this.recompute(key);
    this.emit(key);
    this.schedule(key, kind);
  }

  /** Force a specific state rather than flipping (used by "unfollow" menus). */
  set(kind: ToggleKind, type: SocialType, id: string, active: boolean): void {
    const snapshot = this.ensure(type, id);
    const current =
      kind === 'like'
        ? snapshot.liked
        : kind === 'save'
          ? snapshot.saved
          : kind === 'repost'
            ? snapshot.reposted
            : snapshot.following;
    if (current !== active) this.toggle(kind, type, id);
  }

  /** Test/teardown seam. */
  reset(): void {
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.timers.clear();
    this.records.clear();
    this.snapshots.clear();
  }

  /** Resolves once nothing is in flight — used by tests, never by the UI. */
  async settled(): Promise<void> {
    // Let queued timers fire, then drain until quiet.
    for (let guard = 0; guard < 1000; guard += 1) {
      const pendingTimers = this.timers.size > 0;
      const pendingCalls = [...this.records.values()].some((record) =>
        TOGGLE_KINDS.some((kind) => record.kinds[kind].inFlight),
      );
      if (!pendingTimers && !pendingCalls) return;
      await new Promise<void>((resolve) => {
        setTimeout(resolve, this.coalesceMs + 1);
      });
    }
  }

  /* ── internals ──────────────────────────────────────────────────────────── */

  private buildRecord(type: SocialType, id: string, seed?: SocialSeed): EntityRecord {
    return {
      type,
      id,
      kinds: {
        like: newKindState(seed?.viewerLiked ?? false, seed?.likeCount ?? 0),
        save: newKindState(seed?.viewerSaved ?? false, seed?.saveCount ?? 0),
        repost: newKindState(seed?.viewerReposted ?? false, seed?.repostCount ?? 0),
        follow: newKindState(seed?.viewerFollows ?? false, seed?.followerCount ?? 0),
      },
      commentCount: seed?.commentCount ?? 0,
      viewCount: seed?.viewCount ?? 0,
      childCount: seed?.childCount ?? 0,
      quoteCount: seed?.quoteCount ?? 0,
    };
  }

  private recompute(key: string): SocialSnapshot {
    const record = this.records.get(key);
    if (!record) {
      const empty: SocialSnapshot = {
        type: 'item',
        id: '',
        liked: false,
        saved: false,
        reposted: false,
        following: false,
        likeCount: 0,
        saveCount: 0,
        repostCount: 0,
        quoteCount: 0,
        followerCount: 0,
        commentCount: 0,
        viewCount: 0,
        childCount: 0,
        pending: false,
      };
      this.snapshots.set(key, empty);
      return empty;
    }

    const { like, save, repost, follow } = record.kinds;
    const snapshot: SocialSnapshot = {
      type: record.type,
      id: record.id,
      liked: like.desired,
      saved: save.desired,
      reposted: repost.desired,
      following: follow.desired,
      likeCount: displayedCount(like),
      saveCount: displayedCount(save),
      repostCount: displayedCount(repost),
      quoteCount: record.quoteCount,
      followerCount: displayedCount(follow),
      commentCount: record.commentCount,
      viewCount: record.viewCount,
      childCount: record.childCount,
      pending:
        like.inFlight || save.inFlight || repost.inFlight || follow.inFlight,
    };
    this.snapshots.set(key, snapshot);
    return snapshot;
  }

  private emit(key: string): void {
    const listeners = this.listeners.get(key);
    if (!listeners) return;
    for (const listener of [...listeners]) listener();
  }

  private schedule(key: string, kind: ToggleKind): void {
    const timerKey = `${key}#${kind}`;
    const existing = this.timers.get(timerKey);
    if (existing) clearTimeout(existing);
    const timer = setTimeout(() => {
      this.timers.delete(timerKey);
      void this.drain(key, kind);
    }, this.coalesceMs);
    this.timers.set(timerKey, timer);
  }

  private async drain(key: string, kind: ToggleKind): Promise<void> {
    const record = this.records.get(key);
    if (!record) return;
    const state = record.kinds[kind];
    if (state.inFlight) return;
    if (state.desired === state.serverActive) return;

    state.inFlight = true;
    this.recompute(key);
    this.emit(key);

    try {
      // Re-reads `desired` every lap: taps that land mid-flight are absorbed.
      let guard = 0;
      while (state.desired !== state.serverActive && guard < 32) {
        guard += 1;
        try {
          const request: ToggleRequest = { kind, type: record.type, id: record.id };
          if (state.desired && state.note !== undefined) request.note = state.note;
          if (state.desired && state.quote !== undefined) request.quote = state.quote;

          const result = await this.runner(request);
          state.serverActive = result.active;
          state.serverCount = Math.max(0, result.count);
        } catch (error) {
          // Roll back to the last thing the database confirmed.
          state.desired = state.serverActive;
          this.onError?.(error, { kind, type: record.type, id: record.id });
          break;
        }
        this.recompute(key);
        this.emit(key);
      }
    } finally {
      state.inFlight = false;
      this.recompute(key);
      this.emit(key);
    }
  }
}

/* ── binding the runner to Supabase ───────────────────────────────────────── */

export interface ToggleApi {
  toggleLike: (type: EntityType, id: string) => Promise<ToggleResult>;
  toggleSave: (type: EntityType, id: string, note?: string) => Promise<ToggleResult>;
  toggleRepost: (type: EntityType, id: string, quote?: string) => Promise<ToggleResult>;
  toggleFollow: (userId: string) => Promise<ToggleResult>;
}

export function createToggleRunner(api: ToggleApi): ToggleRunner {
  return async ({ kind, type, id, note, quote }) => {
    if (kind === 'follow') return api.toggleFollow(id);
    if (type === 'profile') {
      throw new Error(`[klect] '${kind}' is not valid on a profile.`);
    }
    switch (kind) {
      case 'like':
        return api.toggleLike(type, id);
      case 'save':
        return api.toggleSave(type, id, note);
      case 'repost':
        return api.toggleRepost(type, id, quote);
    }
  };
}

/** Seed helper for surf cards. */
export function seedFromSurfCard(card: {
  like_count: number;
  save_count: number;
  repost_count: number;
  quote_count?: number;
  comment_count: number;
  view_count: number;
  child_count: number;
  viewer_liked: boolean;
  viewer_saved: boolean;
  viewer_reposted: boolean;
}): SocialSeed {
  return {
    likeCount: card.like_count,
    saveCount: card.save_count,
    repostCount: card.repost_count,
    quoteCount: card.quote_count,
    commentCount: card.comment_count,
    viewCount: card.view_count,
    childCount: card.child_count,
    viewerLiked: card.viewer_liked,
    viewerSaved: card.viewer_saved,
    viewerReposted: card.viewer_reposted,
  };
}

/** Seed helper for a `get_closeup` payload. */
export function seedFromCloseup(payload: {
  counts: { like: number; save: number; repost: number; comment: number; view: number };
  viewer: { liked: boolean; saved: boolean; reposted: boolean };
}): SocialSeed {
  return {
    likeCount: payload.counts.like,
    saveCount: payload.counts.save,
    repostCount: payload.counts.repost,
    commentCount: payload.counts.comment,
    viewCount: payload.counts.view,
    viewerLiked: payload.viewer.liked,
    viewerSaved: payload.viewer.saved,
    viewerReposted: payload.viewer.reposted,
  };
}
