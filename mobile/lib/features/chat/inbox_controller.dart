import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../core/offline/feed_page_cache.dart';
import '../../core/supabase.dart';
import 'chat_api.dart';
import 'chat_models.dart';

/// The inbox, as the screen sees it.
class ChatInboxState {
  /// Creates an inbox state.
  const ChatInboxState({
    this.entries = const <ChatInboxEntry>[],
    this.loading = true,
    this.error,
  });

  /// Every conversation the viewer is still a member of, archived included.
  /// Already ordered: pinned first, then most recent activity.
  final List<ChatInboxEntry> entries;

  /// The first load is in flight.
  final bool loading;

  /// The last failure, if the inbox could not load.
  final Object? error;

  /// Rows that belong in the main list.
  List<ChatInboxEntry> get active => <ChatInboxEntry>[
    for (final entry in entries)
      if (!entry.isArchived) entry,
  ];

  /// Rows the viewer archived.
  List<ChatInboxEntry> get archived => <ChatInboxEntry>[
    for (final entry in entries)
      if (entry.isArchived) entry,
  ];

  /// Unread messages across every unarchived, unmuted-or-not conversation —
  /// the number the inbox entry point badges.
  int get unreadTotal {
    var total = 0;
    for (final entry in entries) {
      if (entry.isArchived) continue;
      total += entry.unreadCount;
    }
    return total;
  }

  /// Copy with overrides.
  ChatInboxState copyWith({
    List<ChatInboxEntry>? entries,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) => ChatInboxState(
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The live inbox.
///
/// Loads one page, then keeps itself correct from three realtime bindings
/// instead of polling: a new message reorders a row, a conversation update
/// rewrites its preview, and a membership update carries the viewer's unread
/// count, pin, archive and mute — all of which are **per viewer**, which is why
/// they live on `conversation_members` rather than `conversations`.
class ChatInboxController extends Notifier<ChatInboxState> {
  RealtimeChannel? _channel;
  bool _disposed = false;

  ChatApi get _api => ref.read(chatApiProvider);

  @override
  ChatInboxState build() {
    // `build` re-runs whenever the signed-in user changes, and the previous
    // run's `onDispose` has already fired by then — so the flag has to be
    // cleared here or the rebuilt inbox would think it was disposed.
    _disposed = false;
    final userId = ref.watch(currentUserIdProvider);
    ref.onDispose(_teardown);
    if (userId == null) {
      return const ChatInboxState(entries: <ChatInboxEntry>[], loading: false);
    }
    unawaited(_load());
    _listen();
    return const ChatInboxState();
  }

  void _teardown() {
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_api.removeChannel(channel));
  }

  void _listen() {
    _channel = _api.inboxChannel(
      onMessage: _onMessageRow,
      onConversation: _onConversationRow,
      onMembership: _onMembershipRow,
    )..subscribe();
  }

  Future<void> _load() async {
    try {
      final entries = await _api.fetchInbox();
      if (_disposed) return;
      state = ChatInboxState(entries: entries, loading: false);
      unawaited(
        ref.read(feedPageCacheProvider).write(_cacheKey, _snapshot(entries)),
      );
    } catch (error) {
      if (_disposed) return;
      final normalised = KlectError.from(error);
      if (state.entries.isEmpty &&
          normalised.isRetryable &&
          _hydrateFromCache()) {
        return;
      }
      state = state.copyWith(loading: false, error: normalised);
    }
  }

  // ─────────────────────────────────────────────────── offline first page ──

  String get _cacheKey =>
      'chat.inbox.${ref.read(currentUserIdProvider) ?? 'anon'}';

  /// Rebuilds the inbox from the cached snapshot when the first load fails
  /// offline. No error is set: these rows render fine, realtime will catch up
  /// the moment the socket returns, and pull-to-refresh forces it.
  bool _hydrateFromCache() {
    final rows = ref.read(feedPageCacheProvider).read(_cacheKey);
    if (rows == null) return false;
    final entries = <ChatInboxEntry>[
      for (final row in rows)
        if (asMap(row['conversations']).isNotEmpty)
          ChatInboxEntry(
            conversation: Conversation.fromJson(asMap(row['conversations'])),
            pinned: asBool(row['pinned']),
            archivedAt: asDateOrNull(row['archived_at']),
            mutedUntil: asDateOrNull(row['muted_until']),
            lastReadAt: asDateOrNull(row['last_read_at']),
          ),
    ]..sort(ChatInboxEntry.compare);
    if (entries.isEmpty) return false;
    state = ChatInboxState(entries: entries, loading: false);
    return true;
  }

  /// The wire-shaped snapshot the cache stores — only what an inbox row
  /// renders, keyed exactly how [Conversation.fromJson] reads it back.
  List<Map<String, dynamic>> _snapshot(List<ChatInboxEntry> entries) =>
      <Map<String, dynamic>>[
        for (final entry in entries)
          <String, dynamic>{
            'pinned': entry.pinned,
            'archived_at': entry.archivedAt?.toIso8601String(),
            'muted_until': entry.mutedUntil?.toIso8601String(),
            'last_read_at': entry.lastReadAt?.toIso8601String(),
            'conversations': <String, dynamic>{
              'id': entry.conversation.id,
              'kind': entry.conversation.kind.wire,
              'title': entry.conversation.title,
              'description': entry.conversation.description,
              'avatar_path': entry.conversation.avatarPath,
              'last_message_at': entry.conversation.lastMessageAt
                  ?.toIso8601String(),
              'last_message_preview': entry.conversation.lastMessagePreview,
              'created_at': entry.conversation.createdAt?.toIso8601String(),
              'unread_count': entry.conversation.unreadCount,
              if (entry.conversation.otherMember != null)
                'other_member': <String, dynamic>{
                  'id': entry.conversation.otherMember!.id,
                  'username': entry.conversation.otherMember!.username,
                  'display_name': entry.conversation.otherMember!.displayName,
                  'avatar_path': entry.conversation.otherMember!.avatarPath,
                  'is_verified': entry.conversation.otherMember!.isVerified,
                },
            },
          },
      ];

  /// Reloads from the server — pull-to-refresh and the error retry.
  Future<void> refresh() async {
    state = state.copyWith(clearError: true);
    await _load();
  }

  // ───────────────────────────────────────────────────────────── realtime ──

  void _onMessageRow(Map<String, dynamic> row) {
    final conversationId = asString(row['conversation_id']);
    if (conversationId.isEmpty) return;
    // A conversation we already hold is covered by the `conversations` UPDATE
    // the same insert triggers. An unknown one is brand new to us.
    if (_indexOf(conversationId) == -1) {
      unawaited(_adopt(conversationId));
    }
  }

  void _onConversationRow(Map<String, dynamic> row) {
    final id = asString(row['id']);
    final index = _indexOf(id);
    if (index == -1) {
      if (id.isNotEmpty) unawaited(_adopt(id));
      return;
    }
    final existing = state.entries[index];
    final next = existing.copyWith(
      conversation: existing.conversation.copyWith(
        lastMessagePreview: asStringOrNull(row['last_message_preview']),
        lastMessageAt: asDateOrNull(row['last_message_at']),
      ),
    );
    _replace(index, next);
  }

  void _onMembershipRow(Map<String, dynamic> row) {
    final conversationId = asString(row['conversation_id']);
    if (conversationId.isEmpty) return;

    if (asDateOrNull(row['left_at']) != null) {
      _remove(conversationId);
      return;
    }

    final index = _indexOf(conversationId);
    if (index == -1) {
      unawaited(_adopt(conversationId));
      return;
    }
    final existing = state.entries[index];
    _replace(
      index,
      ChatInboxEntry(
        conversation: existing.conversation.copyWith(
          unreadCount: asInt(row['unread_count']),
        ),
        pinned: asBool(row['pinned']),
        archivedAt: asDateOrNull(row['archived_at']),
        mutedUntil: asDateOrNull(row['muted_until']),
        lastReadAt: asDateOrNull(row['last_read_at']),
      ),
    );
  }

  Future<void> _adopt(String conversationId) async {
    try {
      final entry = await _api.fetchInboxEntry(conversationId);
      if (_disposed || entry == null) return;
      final index = _indexOf(conversationId);
      if (index == -1) {
        _sortInto(<ChatInboxEntry>[...state.entries, entry]);
      } else {
        _replace(index, entry);
      }
    } on KlectError {
      // The row is not visible to us (blocked, left, RLS). Nothing to show.
    }
  }

  // ────────────────────────────────────────────────────────────── actions ──

  /// Pins or unpins, optimistically.
  Future<void> togglePin(String conversationId) => _optimistic(
    conversationId,
    (entry) => entry.copyWith(pinned: !entry.pinned),
    (entry) => _api.setPinned(conversationId, pinned: !entry.pinned),
  );

  /// Archives or un-archives, optimistically.
  Future<void> toggleArchive(String conversationId) => _optimistic(
    conversationId,
    (entry) => entry.isArchived
        ? entry.copyWith(clearArchived: true)
        : entry.copyWith(archivedAt: DateTime.now()),
    (entry) => _api.setArchived(conversationId, archived: !entry.isArchived),
  );

  /// Mutes for [duration], or unmutes when already muted.
  Future<void> toggleMute(
    String conversationId, {
    Duration duration = const Duration(days: 7),
  }) => _optimistic(
    conversationId,
    (entry) => entry.isMuted
        ? entry.copyWith(clearMuted: true)
        : entry.copyWith(mutedUntil: DateTime.now().add(duration)),
    (entry) => _api.setMuted(
      conversationId,
      duration: entry.isMuted ? null : duration,
    ),
  );

  /// Leaves a conversation and drops it from the inbox.
  ///
  /// Restores the row if the server refuses, so a failure is never silent.
  Future<void> leave(String conversationId) async {
    final index = _indexOf(conversationId);
    if (index == -1) return;
    final removed = state.entries[index];
    _remove(conversationId);
    try {
      await _api.leaveConversation(conversationId);
    } catch (error) {
      if (_disposed) return;
      _sortInto(<ChatInboxEntry>[...state.entries, removed]);
      state = state.copyWith(error: KlectError.from(error));
    }
  }

  /// Zeroes the badge the instant a thread opens; the RPC confirms it.
  void markReadLocally(String conversationId) {
    final index = _indexOf(conversationId);
    if (index == -1) return;
    final existing = state.entries[index];
    if (existing.unreadCount == 0) return;
    _replace(
      index,
      existing.copyWith(
        conversation: existing.conversation.copyWith(unreadCount: 0),
        lastReadAt: DateTime.now(),
      ),
    );
  }

  Future<void> _optimistic(
    String conversationId,
    ChatInboxEntry Function(ChatInboxEntry entry) apply,
    Future<void> Function(ChatInboxEntry entry) commit,
  ) async {
    final index = _indexOf(conversationId);
    if (index == -1) return;
    final before = state.entries[index];
    _replace(index, apply(before));
    try {
      await commit(before);
    } catch (error) {
      if (_disposed) return;
      final now = _indexOf(conversationId);
      if (now != -1) _replace(now, before);
      state = state.copyWith(error: KlectError.from(error));
    }
  }

  /// Drops the sticky error banner.
  void clearError() => state = state.copyWith(clearError: true);

  // ───────────────────────────────────────────────────────────── plumbing ──

  int _indexOf(String conversationId) =>
      state.entries.indexWhere((entry) => entry.id == conversationId);

  void _replace(int index, ChatInboxEntry entry) {
    final next = <ChatInboxEntry>[...state.entries];
    next[index] = entry;
    _sortInto(next);
  }

  void _remove(String conversationId) {
    final next = <ChatInboxEntry>[
      for (final entry in state.entries)
        if (entry.id != conversationId) entry,
    ];
    if (next.length == state.entries.length) return;
    state = state.copyWith(entries: next);
  }

  void _sortInto(List<ChatInboxEntry> entries) {
    entries.sort(ChatInboxEntry.compare);
    state = state.copyWith(entries: entries, loading: false);
  }
}

/// The live inbox.
final chatInboxProvider = NotifierProvider<ChatInboxController, ChatInboxState>(
  ChatInboxController.new,
  name: 'chatInbox',
);

/// Unread direct messages, for a badge on the messages entry point.
final unreadMessageCountProvider = Provider<int>(
  (ref) => ref.watch(chatInboxProvider).unreadTotal,
  name: 'unreadMessageCount',
);
