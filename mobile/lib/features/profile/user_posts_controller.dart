import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../pulse/data/pulse_entry_view.dart';

typedef ProfilePulseQuery = ({String userId, ProfilePulseView view});
typedef ProfileDiscussionQuery = ({String userId, ProfileSurface surface});
typedef ProfileReactionQuery = ({
  ProfileReactionAction action,
  ProfileSurface surface,
});

@immutable
class UserPostsState {
  const UserPostsState({
    this.items = const <PulseItem>[],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  final List<PulseItem> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final KlectError? error;

  UserPostsState copyWith({
    List<PulseItem>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Map<String, dynamic>? nextCursor,
    bool clearCursor = false,
    KlectError? error,
    bool clearError = false,
  }) => UserPostsState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    error: clearError ? null : (error ?? this.error),
  );
}

/// One public profile Pulse slice, keyed by account and server-side view.
class UserPostsController extends Notifier<UserPostsState> {
  UserPostsController(this.query);

  final ProfilePulseQuery query;
  static const int pageSize = 25;
  final Set<String> _seen = <String>{};
  bool _disposed = false;
  bool _busy = false;

  @override
  UserPostsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen<SocialActivityMutation?>(socialActivityMutationProvider, (
      previous,
      next,
    ) {
      if (next != null && next.revision != previous?.revision) {
        unawaited(refresh());
      }
    });
    unawaited(Future<void>.microtask(load));
    return const UserPostsState();
  }

  Future<void> load() => _load(reset: true);
  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.nextCursor == null) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: state.items.isEmpty, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(klectApiProvider)
          .profilePulseActivity(
            userId: query.userId,
            view: query.view,
            limit: pageSize,
            cursor: reset ? null : state.nextCursor,
          );
      if (_disposed) return;
      if (reset) _seen.clear();
      final fresh = <PulseItem>[];
      for (final entry in page.items) {
        final item = PulseItem.fromEntry(entry);
        if (_seen.add(item.key)) fresh.add(item);
      }
      final store = ref.read(interactionSeedStoreProvider);
      for (final item in fresh) {
        store.put(item.entity, item.seed);
      }
      state = UserPostsState(
        items: reset ? fresh : <PulseItem>[...state.items, ...fresh],
        loading: false,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, loadingMore: false, error: error);
    } finally {
      _busy = false;
    }
  }
}

final userPostsProvider = NotifierProvider.autoDispose
    .family<UserPostsController, UserPostsState, ProfilePulseQuery>(
      UserPostsController.new,
      name: 'profilePulseActivity',
    );

@immutable
class ProfileDiscussionState {
  const ProfileDiscussionState({
    this.items = const <ProfileDiscussionActivity>[],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  final List<ProfileDiscussionActivity> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final KlectError? error;

  ProfileDiscussionState copyWith({
    List<ProfileDiscussionActivity>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Map<String, dynamic>? nextCursor,
    KlectError? error,
    bool clearError = false,
  }) => ProfileDiscussionState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: nextCursor ?? this.nextCursor,
    error: clearError ? null : (error ?? this.error),
  );
}

class ProfileDiscussionController extends Notifier<ProfileDiscussionState> {
  ProfileDiscussionController(this.query);

  final ProfileDiscussionQuery query;
  static const int pageSize = 25;
  final Set<String> _seen = <String>{};
  bool _busy = false;
  bool _disposed = false;

  @override
  ProfileDiscussionState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen<SocialActivityMutation?>(socialActivityMutationProvider, (
      previous,
      next,
    ) {
      if (next != null && next.revision != previous?.revision) {
        unawaited(refresh());
      }
    });
    unawaited(Future<void>.microtask(refresh));
    return const ProfileDiscussionState();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy || (!reset && !state.hasMore)) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: state.items.isEmpty, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(klectApiProvider)
          .profileDiscussionActivity(
            userId: query.userId,
            surface: query.surface,
            limit: pageSize,
            cursor: reset ? null : state.nextCursor,
          );
      if (_disposed) return;
      if (reset) _seen.clear();
      final fresh = <ProfileDiscussionActivity>[
        for (final item in page.items)
          if (_seen.add(item.comment.id)) item,
      ];
      for (final item in fresh) {
        ref
            .read(interactionSeedStoreProvider)
            .put(
              EntityRef.comment(item.comment.id),
              InteractionState.fromComment(item.comment),
            );
      }
      state = ProfileDiscussionState(
        items: reset
            ? fresh
            : <ProfileDiscussionActivity>[...state.items, ...fresh],
        loading: false,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } on KlectError catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          error: error,
        );
      }
    } finally {
      _busy = false;
    }
  }
}

final profileDiscussionProvider = NotifierProvider.autoDispose
    .family<
      ProfileDiscussionController,
      ProfileDiscussionState,
      ProfileDiscussionQuery
    >(ProfileDiscussionController.new, name: 'profileDiscussionActivity');

@immutable
class ProfileReactionState {
  const ProfileReactionState({
    this.items = const <ProfileReactionActivity>[],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  final List<ProfileReactionActivity> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final KlectError? error;

  ProfileReactionState copyWith({
    List<ProfileReactionActivity>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Map<String, dynamic>? nextCursor,
    KlectError? error,
    bool clearError = false,
  }) => ProfileReactionState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: nextCursor ?? this.nextCursor,
    error: clearError ? null : (error ?? this.error),
  );
}

class ProfileReactionController extends Notifier<ProfileReactionState> {
  ProfileReactionController(this.query);

  final ProfileReactionQuery query;
  static const int pageSize = 25;
  final Set<String> _seen = <String>{};
  bool _busy = false;
  bool _disposed = false;

  @override
  ProfileReactionState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen<SocialActivityMutation?>(socialActivityMutationProvider, (
      previous,
      next,
    ) {
      if (next != null && next.revision != previous?.revision) {
        unawaited(refresh());
      }
    });
    unawaited(Future<void>.microtask(refresh));
    return const ProfileReactionState();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy || (!reset && !state.hasMore)) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: state.items.isEmpty, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(klectApiProvider)
          .myProfileReactions(
            action: query.action,
            surface: query.surface,
            limit: pageSize,
            cursor: reset ? null : state.nextCursor,
          );
      if (_disposed) return;
      if (reset) _seen.clear();
      final fresh = <ProfileReactionActivity>[
        for (final item in page.items)
          if (_seen.add('${item.targetType.wire}:${item.targetId}')) item,
      ];
      state = ProfileReactionState(
        items: reset
            ? fresh
            : <ProfileReactionActivity>[...state.items, ...fresh],
        loading: false,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    } on KlectError catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          error: error,
        );
      }
    } finally {
      _busy = false;
    }
  }
}

final profileReactionProvider = NotifierProvider.autoDispose
    .family<
      ProfileReactionController,
      ProfileReactionState,
      ProfileReactionQuery
    >(ProfileReactionController.new, name: 'profileReactionActivity');
