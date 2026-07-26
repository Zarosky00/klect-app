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
    this.loadingMore = false,
    this.hasMore = false,
    this.sort = CommentSort.top,
    this.error,
    this.failedDraft,
    this.failedParentId,
  });

  /// Every loaded comment, flat: root comments in [sort] order followed by
  /// replies in time order. The view builds the tree.
  final List<CommentModel> comments;

  /// The first fetch (or a sort switch) is in flight.
  final bool loading;

  /// A later page of root comments is in flight.
  final bool loadingMore;

  /// Whether the last root page came back full.
  final bool hasMore;

  /// Current ordering.
  final CommentSort sort;

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
    bool? loadingMore,
    bool? hasMore,
    CommentSort? sort,
    KlectError? error,
    bool clearError = false,
    String? failedDraft,
    String? failedParentId,
    bool clearDraft = false,
  }) =>
      CommentsState(
        comments: comments ?? this.comments,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        sort: sort ?? this.sort,
        error: clearError ? null : (error ?? this.error),
        failedDraft: clearDraft ? null : (failedDraft ?? this.failedDraft),
        failedParentId:
            clearDraft ? null : (failedParentId ?? this.failedParentId),
      );
}

/// Threaded comments with optimistic posting, Top/Newest sorting and
/// load-more pagination over **root** comments.
///
/// Roots page through `fetchComments(sort, limit, offset)`; every reply on
/// the entity arrives in one companion query, and the viewer's like state for
/// the whole page is seeded by **one** batched `likes` lookup
/// (`fetchLikedCommentIds`) — a plain table select carries no `viewer_liked`,
/// which is why the old per-row parse was always false.
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

  /// Root comments per page.
  static const int pageSize = 20;

  static const Uuid _uuid = Uuid();

  bool _disposed = false;
  bool _busy = false;

  @override
  CommentsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const CommentsState();
  }

  /// Fetches the first page under the current sort.
  Future<void> load() => _loadPage(reset: true);

  /// Switches ordering and reloads from the top.
  Future<void> setSort(CommentSort sort) async {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort, loading: true, comments: const []);
    await _loadPage(reset: true);
  }

  /// Appends the next page of root comments.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore) return;
    await _loadPage(reset: false);
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_disposed || _busy) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: true, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);
    try {
      final api = ref.read(klectApiProvider);
      final existingRoots = reset
          ? 0
          : state.comments.where((c) => c.parentId == null).length;

      final roots = await api.fetchComments(
        type: entity.type,
        id: entity.id,
        sort: state.sort,
        limit: pageSize,
        offset: existingRoots,
      );
      // One query serves every reply on the thread; the view attaches them.
      final replies = reset || state.comments.isEmpty
          ? await api.fetchCommentReplies(type: entity.type, id: entity.id)
          : const <CommentModel>[];

      // Batched viewer-like seeding — ONE query for the whole page.
      final fresh = <CommentModel>[...roots, ...replies];
      final liked = await api.fetchLikedCommentIds(
        <String>[for (final comment in fresh) comment.id],
      );
      final seeded = <CommentModel>[
        for (final comment in fresh)
          comment.copyWith(viewerLiked: liked.contains(comment.id)),
      ];

      // Comments are likeable entities in their own right, so seed the engine
      // for each one before any pill is built.
      final store = ref.read(interactionSeedStoreProvider);
      for (final comment in seeded) {
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
      final known = <String>{
        if (!reset) for (final comment in state.comments) comment.id,
      };
      state = state.copyWith(
        comments: <CommentModel>[
          if (!reset) ...state.comments,
          for (final comment in seeded)
            if (known.add(comment.id)) comment,
        ],
        loading: false,
        loadingMore: false,
        hasMore: roots.length >= pageSize,
      );
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: error,
      );
    } finally {
      _busy = false;
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

    // Your own comment surfaces immediately: new roots lead the thread, new
    // replies ride under their parent.
    state = state.copyWith(
      comments: parentId == null
          ? <CommentModel>[optimistic, ...state.comments]
          : <CommentModel>[...state.comments, optimistic],
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
