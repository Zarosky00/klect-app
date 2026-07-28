import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../auth/auth_controller.dart';
import '../data/pulse_entry_view.dart';

/// Everything the post thread screen renders.
@immutable
class PostThreadState {
  /// Creates a thread state.
  const PostThreadState({
    this.post,
    this.comments = const <CommentModel>[],
    this.sort = CommentSort.top,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.commentError,
    this.failedDraft,
    this.failedParentId,
  });

  /// The post, normalised exactly like a Pulse row. Null until loaded.
  final PulseItem? post;

  /// Loaded comments in server order (already sorted by [sort]).
  final List<CommentModel> comments;

  /// Current comment ordering.
  final CommentSort sort;

  /// The first fetch (or a sort switch / refresh) is in flight.
  final bool loading;

  /// A later comment page is in flight.
  final bool loadingMore;

  /// Whether the server said another comment page exists.
  final bool hasMore;

  /// A fatal load failure — the screen shows an error state.
  final KlectError? error;

  /// A transient comment-post failure.
  final KlectError? commentError;

  /// Text of a comment that failed to post, so the composer restores it.
  final String? failedDraft;

  /// Which reply the failed draft belonged to.
  final String? failedParentId;

  /// Copy with overrides.
  PostThreadState copyWith({
    PulseItem? post,
    List<CommentModel>? comments,
    CommentSort? sort,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    KlectError? error,
    bool clearError = false,
    KlectError? commentError,
    String? failedDraft,
    String? failedParentId,
    bool clearDraft = false,
  }) => PostThreadState(
    post: post ?? this.post,
    comments: comments ?? this.comments,
    sort: sort ?? this.sort,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    commentError: clearDraft ? null : (commentError ?? this.commentError),
    failedDraft: clearDraft ? null : (failedDraft ?? this.failedDraft),
    failedParentId: clearDraft ? null : (failedParentId ?? this.failedParentId),
  );
}

/// The post thread — `get_post_thread` (0021) behind one controller.
///
/// One RPC returns the post envelope, a stats snapshot and a page of
/// comments with the viewer's like/save/repost state already batched in, so
/// the screen never fires an N+1. Comments page by `created_at` keyset
/// (`p_before` = the minimum on screen, in both sort modes), and the payload
/// carries an explicit `has_more` instead of the flat feeds' extra-row
/// contract.
class PostThreadController extends Notifier<PostThreadState> {
  /// Creates the controller for one post.
  PostThreadController(this.postId);

  /// Which post this thread belongs to.
  final String postId;

  /// Comments per page.
  static const int pageSize = 30;

  static const Uuid _uuid = Uuid();

  bool _disposed = false;
  bool _busy = false;

  EntityRef get _entity => EntityRef.post(postId);

  @override
  PostThreadState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const PostThreadState();
  }

  /// Fetches the thread from the top under the current sort.
  Future<void> load() => _load(reset: true);

  /// Reloads everything — pull-to-refresh.
  Future<void> refresh() => _load(reset: true);

  /// Switches comment ordering and reloads.
  Future<void> setSort(CommentSort sort) async {
    if (sort == state.sort) return;
    state = state.copyWith(
      sort: sort,
      loading: true,
      comments: const <CommentModel>[],
    );
    await _load(reset: true);
  }

  /// Appends the next comment page.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore) return;
    await _load(reset: false);
  }

  /// The `p_before` keyset: the minimum `created_at` currently on screen —
  /// correct in both sort modes per the 0021 contract (server-acknowledged
  /// rows only; a pending optimistic comment has no server timestamp yet).
  DateTime? _oldestLoaded() {
    DateTime? oldest;
    for (final comment in state.comments) {
      if (comment.isPending) continue;
      final at = comment.createdAt;
      if (at == null) continue;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    return oldest;
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: true, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);

    try {
      final thread = await ref
          .read(klectApiProvider)
          .getPostThread(
            postId,
            limit: pageSize,
            before: reset ? null : _oldestLoaded(),
            sort: state.sort,
          );
      if (_disposed) return;

      final post = PulseItem.fromEntry(thread.post);

      // Seed the optimistic engine before anything renders: the post's bar
      // and every comment's bar hydrate from the envelope's counts.
      final store = ref.read(interactionSeedStoreProvider);
      store.put(post.entity, post.seed);
      ref.read(interactionProvider(post.entity).notifier).hydrate(post.seed);
      for (final comment in thread.comments) {
        final seed = InteractionState.fromComment(comment);
        store.put(EntityRef.comment(comment.id), seed);
        ref
            .read(interactionProvider(EntityRef.comment(comment.id)).notifier)
            .hydrate(seed);
      }

      final known = <String>{
        if (!reset)
          for (final comment in state.comments) comment.id,
      };
      state = state.copyWith(
        post: post,
        comments: <CommentModel>[
          if (!reset) ...state.comments,
          for (final comment in thread.comments)
            if (known.add(comment.id)) comment,
        ],
        loading: false,
        loadingMore: false,
        hasMore: thread.hasMore,
      );
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, loadingMore: false, error: error);
    } finally {
      _busy = false;
    }
  }

  /// Posts a comment (or a reply when [parentId] is set), optimistically.
  Future<void> addComment({
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
      entityType: EntityType.post,
      entityId: postId,
      authorId: me?.id,
      parentId: parentId,
      depth: parentId == null ? 0 : parentDepth + 1,
      createdAt: DateTime.now(),
      author: me,
      isPending: true,
    );

    // Reply-first: your words lead the thread the instant you send them.
    state = state.copyWith(
      comments: <CommentModel>[optimistic, ...state.comments],
      clearDraft: true,
    );
    final interactions = ref.read(interactionProvider(_entity).notifier)
      ..bumpCommentCount(1);
    ref
        .read(socialActivityMutationProvider.notifier)
        .record(
          SocialActivityMutationKind.comment,
          entity: _entity,
          active: true,
        );

    try {
      final result = await ref
          .read(klectApiProvider)
          .addComment(
            type: EntityType.post,
            id: postId,
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
        commentError: error,
        failedDraft: trimmed,
        failedParentId: parentId,
      );
      interactions.bumpCommentCount(-1);
    }
  }

  /// Deletes one of the viewer's own comments, optimistically.
  Future<void> removeComment(String commentId) async {
    final previous = state.comments;
    state = state.copyWith(
      comments: <CommentModel>[
        for (final comment in previous)
          if (comment.id != commentId && comment.parentId != commentId) comment,
      ],
    );
    ref
        .read(socialActivityMutationProvider.notifier)
        .record(
          SocialActivityMutationKind.delete,
          entity: EntityRef.comment(commentId),
          active: false,
        );
    try {
      final count = await ref.read(klectApiProvider).deleteComment(commentId);
      if (_disposed) return;
      ref.read(interactionProvider(_entity).notifier).setCommentCount(count);
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(comments: previous, commentError: error);
    }
  }

  /// Called once the composer has restored a failed draft.
  void draftRestored() => state = state.copyWith(clearDraft: true);
}

/// The post thread, keyed by post id.
final postThreadProvider = NotifierProvider.autoDispose
    .family<PostThreadController, PostThreadState, String>(
      PostThreadController.new,
      name: 'postThread',
    );
