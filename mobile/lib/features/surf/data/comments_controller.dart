import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../auth/auth_controller.dart';

/// The comment thread of one entity.
@immutable
class CommentsState {
  /// Creates a thread state.
  const CommentsState({
    this.comments = const <CommentModel>[],
    this.loading = true,
    this.error,
    this.failedDraft,
    this.failedParentId,
  });

  /// Every comment, flat and oldest-first. The view builds the tree.
  final List<CommentModel> comments;

  /// The first fetch is in flight.
  final bool loading;

  /// The last failure.
  final KlectError? error;

  /// Text of a comment that failed to post. The composer picks this up and
  /// puts the words back in the field — a failed comment never loses text.
  final String? failedDraft;

  /// Which reply the failed draft belonged to.
  final String? failedParentId;

  /// Copy with overrides.
  CommentsState copyWith({
    List<CommentModel>? comments,
    bool? loading,
    KlectError? error,
    bool clearError = false,
    String? failedDraft,
    String? failedParentId,
    bool clearDraft = false,
  }) =>
      CommentsState(
        comments: comments ?? this.comments,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        failedDraft: clearDraft ? null : (failedDraft ?? this.failedDraft),
        failedParentId:
            clearDraft ? null : (failedParentId ?? this.failedParentId),
      );
}

/// Threaded comments with optimistic posting.
///
/// The comment count on the entity is nudged the instant the finger lifts and
/// then reconciled with the authoritative `count` from `add_comment`, exactly
/// like the toggles. Comments are deliberately **not** offline-queueable: a
/// replay would duplicate them, so a transport failure restores the draft
/// instead.
class CommentsController extends Notifier<CommentsState> {
  /// Creates a thread controller for one entity.
  CommentsController(this.entity);

  /// The entity being commented on.
  final EntityRef entity;

  /// The product allows replies down to this depth; deeper replies re-parent
  /// onto the deepest allowed ancestor.
  static const int maxDepth = 3;

  static const Uuid _uuid = Uuid();

  bool _disposed = false;

  @override
  CommentsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const CommentsState();
  }

  /// Fetches the thread.
  Future<void> load() async {
    if (_disposed) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final comments = await ref.read(klectApiProvider).fetchComments(
            type: entity.type,
            id: entity.id,
          );
      // Comments are likeable entities in their own right, so seed the engine
      // for each one before any pill is built.
      final store = ref.read(interactionSeedStoreProvider);
      for (final comment in comments) {
        store.put(
          EntityRef.comment(comment.id),
          InteractionState(
            liked: comment.viewerLiked,
            likeCount: comment.likeCount,
            hydrated: true,
          ),
        );
      }
      if (_disposed) return;
      state = state.copyWith(comments: comments, loading: false);
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// Posts [body], optimistically.
  ///
  /// [parentId] threads it as a reply; [parentDepth] is the parent's own depth
  /// so the optimistic row indents correctly before the server answers.
  Future<void> post({
    required String body,
    String? parentId,
    int parentDepth = 0,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    final me = ref.read(myProfileProvider).value;
    final tempId = 'pending:${_uuid.v4()}';
    final optimistic = CommentModel(
      id: tempId,
      body: trimmed,
      entityType: entity.type,
      entityId: entity.id,
      authorId: me?.id,
      parentId: parentId,
      depth: parentId == null ? 0 : parentDepth + 1,
      createdAt: DateTime.now(),
      author: me,
      isPending: true,
    );

    state = state.copyWith(
      comments: <CommentModel>[...state.comments, optimistic],
      clearDraft: true,
      clearError: true,
    );
    final interactions = ref.read(interactionProvider(entity).notifier)
      ..bumpCommentCount(1);

    try {
      final result = await ref.read(klectApiProvider).addComment(
            type: entity.type,
            id: entity.id,
            body: trimmed,
            parentId: parentId,
          );
      if (_disposed) return;
      state = state.copyWith(
        comments: <CommentModel>[
          for (final comment in state.comments)
            if (comment.id == tempId)
              comment.copyWith(id: result.id, isPending: false)
            else
              comment,
        ],
      );
      interactions.setCommentCount(result.count);
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        comments: <CommentModel>[
          for (final comment in state.comments)
            if (comment.id != tempId) comment,
        ],
        error: error,
        failedDraft: trimmed,
        failedParentId: parentId,
      );
      interactions.bumpCommentCount(-1);
    }
  }

  /// Deletes one of the viewer's own comments, optimistically.
  Future<void> remove(String commentId) async {
    final previous = state.comments;
    state = state.copyWith(
      comments: <CommentModel>[
        for (final comment in previous)
          if (comment.id != commentId && comment.parentId != commentId) comment,
      ],
      clearError: true,
    );
    try {
      final count = await ref.read(klectApiProvider).deleteComment(commentId);
      if (_disposed) return;
      ref.read(interactionProvider(entity).notifier).setCommentCount(count);
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(comments: previous, error: error);
    }
  }

  /// Called once the composer has restored a failed draft.
  void draftRestored() => state = state.copyWith(clearDraft: true);

  /// Clears a surfaced error.
  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

/// The comment thread, keyed by entity.
final commentsProvider = NotifierProvider.autoDispose
    .family<CommentsController, CommentsState, EntityRef>(
  CommentsController.new,
  name: 'comments',
);
