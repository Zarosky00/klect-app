import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../models/models.dart';

/// Which of the three toggles an operation refers to.
enum InteractionAction {
  /// `toggle_like`.
  like,

  /// `toggle_save` — the brand action.
  save,

  /// `toggle_repost`.
  repost,
}

/// Everything a card, a closeup or an action bar needs to render the social
/// state of one entity.
///
/// Counts are always the counter columns plus any un-reconciled optimistic
/// delta. Nothing here is ever computed with `COUNT(*)`.
@immutable
class InteractionState {
  /// Creates a state.
  const InteractionState({
    this.liked = false,
    this.saved = false,
    this.reposted = false,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.hydrated = false,
    this.syncing = false,
    this.error,
  });

  /// Seeds from a surf card.
  factory InteractionState.fromCard(SurfCard card) => InteractionState(
        liked: card.viewerLiked,
        saved: card.viewerSaved,
        reposted: card.viewerReposted,
        likeCount: card.likeCount,
        saveCount: card.saveCount,
        repostCount: card.repostCount,
        commentCount: card.commentCount,
        viewCount: card.viewCount,
        hydrated: true,
      );

  /// Seeds from a closeup payload.
  factory InteractionState.fromCloseup(Closeup closeup) => InteractionState(
        liked: closeup.viewer.liked,
        saved: closeup.viewer.saved,
        reposted: closeup.viewer.reposted,
        likeCount: closeup.counts.like,
        saveCount: closeup.counts.save,
        repostCount: closeup.counts.repost,
        commentCount: closeup.counts.comment,
        viewCount: closeup.counts.view,
        hydrated: true,
      );

  /// Seeds from a comment row — comments are full social citizens (0021),
  /// so a comment's bar hydrates exactly like a post's.
  factory InteractionState.fromComment(CommentModel comment) =>
      InteractionState(
        liked: comment.viewerLiked,
        saved: comment.viewerSaved,
        reposted: comment.viewerReposted,
        likeCount: comment.likeCount,
        saveCount: comment.saveCount,
        repostCount: comment.repostCount,
        commentCount: comment.replyCount,
        hydrated: true,
      );

  /// Seeds from a pulse entry.
  factory InteractionState.fromPulse(PulseEntry entry) => InteractionState(
        liked: entry.viewerLiked,
        saved: entry.viewerSaved,
        reposted: entry.viewerReposted,
        likeCount: entry.likeCount,
        saveCount: entry.saveCount,
        repostCount: entry.repostCount,
        commentCount: entry.commentCount,
        viewCount: entry.viewCount,
        hydrated: true,
      );

  /// Viewer has liked it.
  final bool liked;

  /// Viewer has saved it.
  final bool saved;

  /// Viewer has reposted it.
  final bool reposted;

  /// Live like count.
  final int likeCount;

  /// Live save count.
  final int saveCount;

  /// Live repost count.
  final int repostCount;

  /// Live comment count.
  final int commentCount;

  /// Live view count.
  final int viewCount;

  /// False until real data has been seeded — render a skeleton, not a zero.
  final bool hydrated;

  /// True while at least one RPC is in flight for this entity.
  final bool syncing;

  /// The last failure, cleared on the next successful action.
  final KlectError? error;

  /// Whether [action] is currently active for the viewer.
  bool isActive(InteractionAction action) => switch (action) {
        InteractionAction.like => liked,
        InteractionAction.save => saved,
        InteractionAction.repost => reposted,
      };

  /// The count for [action].
  int countOf(InteractionAction action) => switch (action) {
        InteractionAction.like => likeCount,
        InteractionAction.save => saveCount,
        InteractionAction.repost => repostCount,
      };

  /// Returns a copy with [action] set to [active] and its count set to [count].
  InteractionState withAction(
    InteractionAction action, {
    required bool active,
    required int count,
  }) {
    final safe = count < 0 ? 0 : count;
    return switch (action) {
      InteractionAction.like => copyWith(liked: active, likeCount: safe),
      InteractionAction.save => copyWith(saved: active, saveCount: safe),
      InteractionAction.repost => copyWith(reposted: active, repostCount: safe),
    };
  }

  /// Copy with overrides. [clearError] wins over [error].
  InteractionState copyWith({
    bool? liked,
    bool? saved,
    bool? reposted,
    int? likeCount,
    int? saveCount,
    int? repostCount,
    int? commentCount,
    int? viewCount,
    bool? hydrated,
    bool? syncing,
    KlectError? error,
    bool clearError = false,
  }) =>
      InteractionState(
        liked: liked ?? this.liked,
        saved: saved ?? this.saved,
        reposted: reposted ?? this.reposted,
        likeCount: likeCount ?? this.likeCount,
        saveCount: saveCount ?? this.saveCount,
        repostCount: repostCount ?? this.repostCount,
        commentCount: commentCount ?? this.commentCount,
        viewCount: viewCount ?? this.viewCount,
        hydrated: hydrated ?? this.hydrated,
        syncing: syncing ?? this.syncing,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InteractionState &&
          other.liked == liked &&
          other.saved == saved &&
          other.reposted == reposted &&
          other.likeCount == likeCount &&
          other.saveCount == saveCount &&
          other.repostCount == repostCount &&
          other.commentCount == commentCount &&
          other.viewCount == viewCount &&
          other.hydrated == hydrated &&
          other.syncing == syncing &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
        liked,
        saved,
        reposted,
        likeCount,
        saveCount,
        repostCount,
        commentCount,
        viewCount,
        hydrated,
        syncing,
        error,
      );

  @override
  String toString() => 'InteractionState(liked: $liked/$likeCount, '
      'saved: $saved/$saveCount, reposted: $reposted/$repostCount, '
      'comments: $commentCount, views: $viewCount)';
}
