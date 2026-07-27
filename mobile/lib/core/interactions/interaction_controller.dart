import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../api/klect_api.dart';
import '../feedback/interaction_feedback.dart';
import '../models/models.dart';
import '../offline/action_queue.dart';
import '../offline/queued_action.dart';
import 'entity_ref.dart';
import 'interaction_state.dart';

/// A place to drop authoritative social state before anybody reads it.
///
/// A feed row knows the truth (`viewer_liked`, `like_count`) the moment it is
/// parsed, but the notifier for that entity may not exist yet. Writing the seed
/// here means the notifier picks it up in `build()` instead of flashing zeros.
class InteractionSeedStore {
  final Map<String, InteractionState> _seeds = <String, InteractionState>{};

  /// Records authoritative state for [entity].
  void put(EntityRef entity, InteractionState state) {
    _seeds[entity.key] = state;
  }

  /// Records every card of a feed page in one go.
  void putCards(Iterable<SurfCard> cards) {
    for (final card in cards) {
      _seeds[card.key] = InteractionState.fromCard(card);
    }
  }

  /// Records every entry of a pulse page.
  void putPulse(Iterable<PulseEntry> entries) {
    for (final entry in entries) {
      _seeds[entry.key] = InteractionState.fromPulse(entry);
    }
  }

  /// Reads a seed, if one was left.
  InteractionState? get(EntityRef entity) => _seeds[entity.key];

  /// Drops everything — call on sign-out.
  void clear() => _seeds.clear();
}

/// The seed store.
final interactionSeedStoreProvider = Provider<InteractionSeedStore>(
  (ref) => InteractionSeedStore(),
  name: 'interactionSeedStore',
);

/// **The optimistic engine.**
///
/// One notifier per `(entityType, entityId)`. It owns the whole
/// tap → optimistic delta → RPC → reconcile → (rollback | queue) cycle.
///
/// ### Coalescing
/// Taps are absorbed into a *desired* state rather than a queue of calls. Only
/// one RPC per action is ever in flight; when it returns, the loop compares the
/// server's answer with what the user now wants and fires again only if they
/// disagree. Ten taps in two seconds therefore produce at most two round trips
/// and always land on the right count.
///
/// ### Failure
///  * transport failure → the optimistic state **stays** (that is the user's
///    intent) and the intent is written to the durable offline queue;
///  * `42501` / suspended / gone → the delta is rolled back to the last known
///    server truth and [InteractionState.error] is set.
class InteractionController extends Notifier<InteractionState> {
  /// Creates a controller for one entity.
  InteractionController(this.entity);

  /// The entity this controller owns.
  final EntityRef entity;

  final Map<InteractionAction, bool> _desired = <InteractionAction, bool>{};
  final Map<InteractionAction, bool> _serverActive =
      <InteractionAction, bool>{};
  final Map<InteractionAction, int> _serverCount = <InteractionAction, int>{};
  final Set<InteractionAction> _busy = <InteractionAction>{};
  final Map<InteractionAction, String> _feedbackIds =
      <InteractionAction, String>{};

  KlectApi get _api => ref.read(klectApiProvider);
  OfflineActionQueue get _queue => ref.read(offlineQueueProvider);

  @override
  InteractionState build() {
    final seed =
        ref.read(interactionSeedStoreProvider).get(entity) ??
        const InteractionState();
    _adoptAsServerTruth(seed);
    return seed;
  }

  void _adoptAsServerTruth(InteractionState truth) {
    for (final action in InteractionAction.values) {
      _serverActive[action] = truth.isActive(action);
      _serverCount[action] = truth.countOf(action);
      _desired[action] = truth.isActive(action);
    }
  }

  /// Applies authoritative state fetched from the server.
  ///
  /// Anything with an RPC in flight is left alone — the running drain owns it
  /// and will reconcile when it lands. This is what stops a count flickering
  /// back to a stale value after an optimistic update.
  void hydrate(InteractionState truth) {
    var next = state;
    for (final action in InteractionAction.values) {
      if (_busy.contains(action)) continue;
      _serverActive[action] = truth.isActive(action);
      _serverCount[action] = truth.countOf(action);
      _desired[action] = truth.isActive(action);
      next = next.withAction(
        action,
        active: truth.isActive(action),
        count: truth.countOf(action),
      );
    }
    state = next.copyWith(
      commentCount: truth.commentCount,
      viewCount: truth.viewCount,
      hydrated: true,
    );
  }

  /// Seeds from a feed card.
  void hydrateFromCard(SurfCard card) =>
      hydrate(InteractionState.fromCard(card));

  /// Seeds from a closeup payload.
  void hydrateFromCloseup(Closeup closeup) =>
      hydrate(InteractionState.fromCloseup(closeup));

  /// Merges the counter columns from a realtime `UPDATE` on the entity row.
  ///
  /// Only counts move: the viewer's own booleans are not in that payload, and
  /// an action currently in flight keeps its optimistic count.
  void mergeCounters(Map<String, dynamic> row) {
    var next = state;
    if (!_busy.contains(InteractionAction.like)) {
      final value = asIntOrNull(row['like_count']);
      if (value != null) {
        _serverCount[InteractionAction.like] = value;
        next = next.copyWith(likeCount: value);
      }
    }
    if (!_busy.contains(InteractionAction.save)) {
      final value = asIntOrNull(row['save_count']);
      if (value != null) {
        _serverCount[InteractionAction.save] = value;
        next = next.copyWith(saveCount: value);
      }
    }
    if (!_busy.contains(InteractionAction.repost)) {
      final value = asIntOrNull(row['repost_count']);
      if (value != null) {
        _serverCount[InteractionAction.repost] = value;
        next = next.copyWith(repostCount: value);
      }
    }
    final comments = asIntOrNull(row['comment_count']);
    if (comments != null) next = next.copyWith(commentCount: comments);
    final views = asIntOrNull(row['view_count']);
    if (views != null) next = next.copyWith(viewCount: views);
    state = next.copyWith(hydrated: true);
  }

  /// Like / unlike. Returns when the state has converged.
  Future<void> toggleLike() => _toggle(InteractionAction.like);

  /// Save / unsave.
  Future<void> toggleSave({String? note}) =>
      _toggle(InteractionAction.save, note: note);

  /// Repost / un-repost.
  Future<void> toggleRepost({String? quote}) =>
      _toggle(InteractionAction.repost, quote: quote);

  /// Toggles by enum — used by the long-press peek, which is generic.
  Future<void> toggle(InteractionAction action) => _toggle(action);

  /// Records a view. Deduped per viewer per day server-side; a transport
  /// failure queues it rather than losing it.
  Future<void> recordView() async {
    try {
      final count = await _api.recordView(entity.type, entity.id);
      state = state.copyWith(viewCount: count, hydrated: true);
    } on KlectError catch (error) {
      if (error.isRetryable) {
        await _queue.enqueueView(entityType: entity.type, entityId: entity.id);
      }
    }
  }

  /// Applies a comment-count delta after an optimistic comment post, then
  /// reconciles with the authoritative count from `add_comment`.
  void setCommentCount(int count) {
    state = state.copyWith(commentCount: count < 0 ? 0 : count);
  }

  /// Nudges the comment count by [delta] for an optimistic post or removal.
  void bumpCommentCount(int delta) {
    final next = state.commentCount + delta;
    state = state.copyWith(commentCount: next < 0 ? 0 : next);
  }

  /// Clears a surfaced error once the UI has shown it.
  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  Future<void> _toggle(
    InteractionAction action, {
    String? note,
    String? quote,
  }) async {
    final desired = !state.isActive(action);
    _desired[action] = desired;
    final feedbackAction = _feedbackActionFor(action);
    final feedback = ref.read(interactionFeedbackProvider.notifier);
    _feedbackIds[action] = feedback.begin(
      action: feedbackAction,
      targetKey: entity.key,
      active: desired,
    );

    // Optimistic: the delta lands the instant the finger lifts.
    final optimisticCount = state.countOf(action) + (desired ? 1 : -1);
    state = state
        .withAction(action, active: desired, count: optimisticCount)
        .copyWith(syncing: true, clearError: true);

    // Already draining? The running loop will observe the new desired state.
    if (_busy.contains(action)) return;
    _busy.add(action);

    try {
      while (_desired[action] != _serverActive[action]) {
        final result = await _call(action, note: note, quote: quote);
        _serverActive[action] = result.active;
        _serverCount[action] = result.count;
      }
      // Converged — adopt the server's authoritative answer.
      state = state
          .withAction(
            action,
            active: _serverActive[action]!,
            count: _serverCount[action]!,
          )
          .copyWith(syncing: _busy.length > 1, hydrated: true);
      unawaited(
        feedback.resolve(
          id: _feedbackIds[action]!,
          action: feedbackAction,
          result: InteractionFeedbackResult.confirmed,
          targetKey: entity.key,
          active: _serverActive[action],
        ),
      );
    } on KlectError catch (error) {
      if (error.isRetryable) {
        // Keep the user's intent on screen and replay it on reconnect.
        await _enqueue(action, _desired[action]!, note: note, quote: quote);
        state = state.copyWith(syncing: _busy.length > 1);
        unawaited(
          feedback.resolve(
            id: _feedbackIds[action]!,
            action: feedbackAction,
            result: InteractionFeedbackResult.queued,
            targetKey: entity.key,
            active: _desired[action],
          ),
        );
      } else {
        // Roll back to the last thing the server actually told us.
        final attempted = _desired[action]!;
        _desired[action] = _serverActive[action]!;
        state = state
            .withAction(
              action,
              active: _serverActive[action]!,
              count: _serverCount[action]!,
            )
            .copyWith(syncing: _busy.length > 1, error: error);
        unawaited(
          feedback.resolve(
            id: _feedbackIds[action]!,
            action: feedbackAction,
            result: InteractionFeedbackResult.failed,
            targetKey: entity.key,
            active: attempted,
          ),
        );
      }
    } finally {
      _busy.remove(action);
    }
  }

  static InteractionFeedbackAction _feedbackActionFor(
    InteractionAction action,
  ) => switch (action) {
    InteractionAction.like => InteractionFeedbackAction.like,
    InteractionAction.save => InteractionFeedbackAction.save,
    InteractionAction.repost => InteractionFeedbackAction.repost,
  };

  Future<ToggleResult> _call(
    InteractionAction action, {
    String? note,
    String? quote,
  }) => switch (action) {
    InteractionAction.like => _api.toggleLike(entity.type, entity.id),
    InteractionAction.save => _api.toggleSave(
      entity.type,
      entity.id,
      note: note,
    ),
    InteractionAction.repost => _api.toggleRepost(
      entity.type,
      entity.id,
      quote: quote,
    ),
  };

  Future<void> _enqueue(
    InteractionAction action,
    bool desired, {
    String? note,
    String? quote,
  }) => _queue.enqueueToggle(
    kind: switch (action) {
      InteractionAction.like => QueuedActionKind.like,
      InteractionAction.save => QueuedActionKind.save,
      InteractionAction.repost => QueuedActionKind.repost,
    },
    entityType: entity.type,
    entityId: entity.id,
    desiredActive: desired,
    note: note,
    quote: quote,
  );
}

/// The optimistic engine, keyed by `(entityType, entityId)`.
///
/// ```dart
/// final state = ref.watch(interactionProvider(EntityRef.item(id)));
/// ref.read(interactionProvider(EntityRef.item(id)).notifier).toggleLike();
/// ```
final interactionProvider =
    NotifierProvider.family<InteractionController, InteractionState, EntityRef>(
      InteractionController.new,
      name: 'interaction',
    );

/// Follow state for one profile, with the same optimistic contract.
///
/// `toggle_follow` returns the **target's** follower count, so a follow button
/// anywhere on screen can show the right number immediately.
class FollowController extends Notifier<FollowState> {
  /// Creates a controller for one profile.
  FollowController(this.userId);

  /// The profile being followed.
  final String userId;

  bool _desired = false;
  bool _serverActive = false;
  int _serverCount = 0;
  bool _busy = false;
  String? _feedbackId;
  String? _targetLabel;
  String? _targetAvatarPath;

  @override
  FollowState build() => const FollowState();

  /// Applies authoritative state from a fetched profile.
  void hydrate({required bool following, required int followerCount}) {
    if (_busy) return;
    _desired = following;
    _serverActive = following;
    _serverCount = followerCount;
    state = FollowState(
      following: following,
      followerCount: followerCount,
      hydrated: true,
    );
  }

  /// Follow / unfollow, optimistic and coalesced exactly like the toggles.
  Future<void> toggle({String? targetLabel, String? targetAvatarPath}) async {
    final desired = !state.following;
    _desired = desired;
    if (targetLabel?.trim().isNotEmpty == true) {
      _targetLabel = targetLabel!.trim();
    }
    if (targetAvatarPath?.trim().isNotEmpty == true) {
      _targetAvatarPath = targetAvatarPath!.trim();
    }
    final feedback = ref.read(interactionFeedbackProvider.notifier);
    _feedbackId = feedback.begin(
      action: InteractionFeedbackAction.follow,
      targetKey: userId,
      active: desired,
      targetLabel: _targetLabel,
      targetAvatarPath: _targetAvatarPath,
    );
    final optimistic = state.followerCount + (desired ? 1 : -1);
    state = state.copyWith(
      following: desired,
      followerCount: optimistic < 0 ? 0 : optimistic,
      clearError: true,
    );

    if (_busy) return;
    _busy = true;
    try {
      while (_desired != _serverActive) {
        final result = await ref.read(klectApiProvider).toggleFollow(userId);
        _serverActive = result.active;
        _serverCount = result.count;
      }
      state = state.copyWith(
        following: _serverActive,
        followerCount: _serverCount,
        hydrated: true,
      );
      unawaited(
        feedback.resolve(
          id: _feedbackId!,
          action: InteractionFeedbackAction.follow,
          result: InteractionFeedbackResult.confirmed,
          targetKey: userId,
          active: _serverActive,
          targetLabel: _targetLabel,
          targetAvatarPath: _targetAvatarPath,
        ),
      );
    } on KlectError catch (error) {
      if (error.isRetryable) {
        await ref
            .read(offlineQueueProvider)
            .enqueueFollow(userId: userId, desiredActive: _desired);
        unawaited(
          feedback.resolve(
            id: _feedbackId!,
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.queued,
            targetKey: userId,
            active: _desired,
            targetLabel: _targetLabel,
            targetAvatarPath: _targetAvatarPath,
          ),
        );
      } else {
        final attempted = _desired;
        _desired = _serverActive;
        state = state.copyWith(
          following: _serverActive,
          followerCount: _serverCount,
          error: error,
        );
        unawaited(
          feedback.resolve(
            id: _feedbackId!,
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.failed,
            targetKey: userId,
            active: attempted,
            targetLabel: _targetLabel,
            targetAvatarPath: _targetAvatarPath,
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }
}

/// The state a follow button renders.
class FollowState {
  /// Creates a follow state.
  const FollowState({
    this.following = false,
    this.followerCount = 0,
    this.hydrated = false,
    this.error,
  });

  /// Whether the viewer follows the target.
  final bool following;

  /// The target's follower count.
  final int followerCount;

  /// False until real data arrived.
  final bool hydrated;

  /// The last failure.
  final KlectError? error;

  /// Copy with overrides.
  FollowState copyWith({
    bool? following,
    int? followerCount,
    bool? hydrated,
    KlectError? error,
    bool clearError = false,
  }) => FollowState(
    following: following ?? this.following,
    followerCount: followerCount ?? this.followerCount,
    hydrated: hydrated ?? this.hydrated,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowState &&
          other.following == following &&
          other.followerCount == followerCount &&
          other.hydrated == hydrated &&
          other.error == error;

  @override
  int get hashCode => Object.hash(following, followerCount, hydrated, error);
}

/// Follow state per user id.
final followProvider =
    NotifierProvider.family<FollowController, FollowState, String>(
      FollowController.new,
      name: 'follow',
    );
