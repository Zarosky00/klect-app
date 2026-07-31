import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../auth/auth_controller.dart';
import 'chat_api.dart';
import 'chat_models.dart';
import 'inbox_controller.dart';

/// How long a typing marker survives without a refresh.
const Duration _typingTtl = Duration(seconds: 5);

/// How often a keystroke may re-broadcast. Well under [_typingTtl] so the
/// indicator never blinks while somebody is genuinely typing.
const Duration _typingThrottle = Duration(seconds: 2);

/// One page of history.
const int _pageSize = 40;

/// One open conversation.
///
/// Owns the message list, the members (which carry the read watermarks), the
/// realtime bindings and the typing broadcast. Sends are optimistic: the bubble
/// appears on the frame the send button is tapped, carrying the very uuid the
/// insert will use, so the realtime echo replaces it instead of duplicating it.
///
/// Messages are deliberately **not** put on the offline queue. Replaying a send
/// would duplicate it; a failed message stays in the thread marked failed, with
/// a retry, which is the same rule the foundation applies to comments.
class ChatThreadController extends Notifier<ChatThreadState> {
  /// Creates a controller for one conversation.
  ChatThreadController(this.conversationId);

  /// The conversation this controller owns.
  final String conversationId;

  /// How long a delete-for-everyone may hang before the thread gives up and
  /// puts the original bubble back.
  ///
  /// A request budget rather than a motion duration — the Token_Set describes
  /// animation, so this deliberately is not one of its entries
  /// (Requirement 11.12).
  static const Duration deleteTimeout = Duration(seconds: 10);

  RealtimeChannel? _thread;
  RealtimeChannel? _presence;
  Timer? _typingSweeper;
  DateTime? _lastTypingBroadcast;
  bool _disposed = false;

  final Map<String, TypingUser> _typing = <String, TypingUser>{};
  final Map<String, Uint8List> _localPreviews = <String, Uint8List>{};
  final Map<String, _PendingSend> _pending = <String, _PendingSend>{};
  final Set<String> _hidden = <String>{};
  DateTime? _historyCursor;

  ChatApi get _api => ref.read(chatApiProvider);

  String? get _me => ref.read(currentUserIdProvider);

  @override
  ChatThreadState build() {
    // The previous run's `onDispose` has already fired by the time a rebuild
    // reaches here, so the flag must be cleared or the thread would refuse to
    // update itself.
    _disposed = false;
    _hidden.clear();
    _historyCursor = null;
    ref.onDispose(_teardown);
    unawaited(_load());
    _listen();
    return const ChatThreadState();
  }

  void _teardown() {
    _disposed = true;
    _typingSweeper?.cancel();
    _typingSweeper = null;
    final thread = _thread;
    final presence = _presence;
    _thread = null;
    _presence = null;
    if (thread != null) unawaited(_api.removeChannel(thread));
    if (presence != null) unawaited(_api.removeChannel(presence));
  }

  // ─────────────────────────────────────────────────────────────── loading ──

  Future<void> _load() async {
    try {
      final results = await Future.wait(<Future<Object?>>[
        _api.fetchMessages(conversationId, limit: _pageSize),
        _api.fetchMembers(conversationId),
        _api.fetchConversation(conversationId),
        _api.fetchHiddenMessageIds(conversationId),
      ]);
      if (_disposed) return;
      final page = results[0]! as List<ChatMessage>;
      _hidden
        ..clear()
        ..addAll(results[3]! as Set<String>);
      _historyCursor = page.isEmpty ? null : page.last.createdAt;
      final messages = <ChatMessage>[
        for (final message in page)
          if (!_hidden.contains(message.id)) message,
      ];
      state = state.copyWith(
        messages: messages,
        members: results[1]! as List<ConversationMember>,
        conversation: results[2] as Conversation?,
        loading: false,
        hasMore: page.length >= _pageSize,
        clearError: true,
      );
      if (messages.isEmpty && page.length >= _pageSize) {
        await _fillVisiblePage();
      }
      unawaited(markRead());
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(loading: false, error: KlectError.from(error));
    }
  }

  /// Reloads the first page.
  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    await _load();
  }

  /// Pages backwards through history.
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    await _fillVisiblePage();
  }

  Future<void> _fillVisiblePage() async {
    try {
      var merged = <ChatMessage>[...state.messages];
      var hasMore = state.hasMore;
      for (var attempt = 0; attempt < 10 && hasMore; attempt++) {
        final older = await _api.fetchMessages(
          conversationId,
          limit: _pageSize,
          before: _historyCursor,
        );
        if (_disposed) return;
        if (older.isEmpty) {
          hasMore = false;
          break;
        }
        _historyCursor = older.last.createdAt;
        hasMore = older.length >= _pageSize;
        final known = <String>{for (final message in merged) message.id};
        final visible = <ChatMessage>[
          for (final message in older)
            if (!_hidden.contains(message.id) && !known.contains(message.id))
              message,
        ];
        merged = <ChatMessage>[...merged, ...visible];
        if (visible.isNotEmpty) break;
      }
      state = state.copyWith(
        messages: merged,
        loadingMore: false,
        hasMore: hasMore,
      );
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(loadingMore: false, error: KlectError.from(error));
    }
  }

  /// `mark_conversation_read` — call it whenever the thread is visible.
  Future<void> markRead() async {
    ref.read(chatInboxProvider.notifier).markReadLocally(conversationId);
    try {
      await _api.markRead(conversationId);
    } on KlectError {
      // Read receipts are not worth surfacing a banner for.
    }
  }

  // ────────────────────────────────────────────────────────────── realtime ──

  void _listen() {
    _thread = _api.threadChannel(
      conversationId: conversationId,
      onMessageInsert: _onMessageInsert,
      onMessageUpdate: _onMessageUpdate,
      onReactionInsert: _onReactionInsert,
      onReactionDelete: _onReactionDelete,
      onMembership: _onMembership,
    )..subscribe();

    // Assigned *before* subscribing: the join reply can arrive as soon as the
    // call returns, and the callback dereferences the field.
    final presence = _api.presenceChannel(
      conversationId: conversationId,
      onTyping: _onTypingBroadcast,
      onPresence: _onPresenceChanged,
    );
    _presence = presence;
    presence.subscribe((status, _) {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      final me = _me;
      if (me == null) return;
      unawaited(
        presence.track(<String, dynamic>{
          'user_id': me,
          'at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    });
  }

  /// Presence tells us who currently has this thread open, which is what
  /// "Active now" means — a far better signal than `profiles.last_seen_at`,
  /// and it costs no rows.
  void _onPresenceChanged() {
    final channel = _presence;
    if (channel == null || _disposed) return;
    final present = <String>{};
    for (final entry in channel.presenceState()) {
      for (final member in entry.presences) {
        final userId = asStringOrNull(member.payload['user_id']);
        if (userId != null) present.add(userId);
      }
    }
    state = state.copyWith(presentUserIds: present);
  }

  void _onMessageInsert(Map<String, dynamic> row) {
    final id = asString(row['id']);
    if (id.isEmpty) return;
    if (_hidden.contains(id)) return;
    if (_indexOf(id) != -1) {
      // Our own optimistic bubble, or a duplicate delivery.
      return;
    }
    unawaited(_hydrateInserted(id));
  }

  Future<void> _hydrateInserted(String id) async {
    try {
      if (_hidden.contains(id)) return;
      final message = await _api.fetchMessage(id);
      // A message deleted between the insert and this fetch still belongs in
      // the thread: it renders as a tombstone rather than never appearing, so
      // the thread reads the same before and after a restart (11.13).
      if (_disposed || message == null) return;
      if (_indexOf(id) != -1) return;
      final next = <ChatMessage>[message, ...state.messages]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(messages: next);
      if (message.authorId != _me) unawaited(markRead());
    } on KlectError {
      // Not visible to us — nothing to add.
    }
  }

  void _onMessageUpdate(Map<String, dynamic> row) {
    final id = asString(row['id']);
    if (_hidden.contains(id)) return;
    final index = _indexOf(id);
    if (index == -1) return;
    final existing = state.messages[index];
    // A delete-for-everyone arrives here as an ordinary update, and that is
    // exactly how it is treated: the row is replaced where it already sits,
    // carrying the `created_at` the delete never wrote, so the tombstone holds
    // the deleted message's position in thread order and its original
    // timestamp with no refresh (11.3, 11.6).
    final updated = MessageModel.fromJson(row).copyWith(
      author: existing.message.author,
      // The payload knows nothing about the viewer's own hidden set, and a
      // message the viewer hid stays hidden rather than turning into a
      // tombstone (12.6).
      hiddenForMe: existing.hiddenForMe,
    );
    _replaceMessage(
      index,
      existing.copyWith(message: updated, pending: false, failed: false),
    );
  }

  void _onReactionInsert(Map<String, dynamic> row) {
    final reaction = MessageReaction.fromJson(row);
    final index = _indexOf(reaction.messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    if (existing.reactions.contains(reaction)) return;
    _replaceMessage(
      index,
      existing.copyWith(
        reactions: <MessageReaction>[...existing.reactions, reaction],
      ),
    );
  }

  void _onReactionDelete(Map<String, dynamic> row) {
    final messageId = asString(row['message_id']);
    final userId = asString(row['user_id']);
    final emoji = asStringOrNull(row['emoji']);
    final index = _indexOf(messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    final remaining = <MessageReaction>[
      for (final reaction in existing.reactions)
        if (!(reaction.userId == userId &&
            (emoji == null || reaction.emoji == emoji)))
          reaction,
    ];
    if (remaining.length == existing.reactions.length) return;
    _replaceMessage(index, existing.copyWith(reactions: remaining));
  }

  void _onMembership(Map<String, dynamic> row) {
    final userId = asString(row['user_id']);
    final index = state.members.indexWhere((member) => member.userId == userId);
    if (index == -1) {
      // Somebody new joined the group while the thread was open. The payload
      // has no profile, so refetch the member list instead of guessing.
      if (userId.isNotEmpty) unawaited(_refreshMembers());
      return;
    }
    final existing = state.members[index];
    final next = <ConversationMember>[...state.members];
    next[index] = ConversationMember(
      conversationId: existing.conversationId,
      userId: existing.userId,
      // Roles change live too — promote/demote/ownership transfer.
      role: asString(row['role'], existing.role),
      joinedAt: existing.joinedAt,
      lastReadAt: asDateOrNull(row['last_read_at']) ?? existing.lastReadAt,
      unreadCount: asInt(row['unread_count']),
      mutedUntil: asDateOrNull(row['muted_until']),
      leftAt: asDateOrNull(row['left_at']),
      profile: existing.profile,
    );
    state = state.copyWith(members: next);
  }

  Future<void> _refreshMembers() async {
    try {
      final members = await _api.fetchMembers(conversationId);
      if (_disposed) return;
      state = state.copyWith(members: members);
    } on KlectError {
      // The list corrects itself on the next full load.
    }
  }

  // ─────────────────────────────────────────────────────────────── typing ──

  /// Broadcasts "I am typing", throttled. Never writes a row.
  void notifyTyping() {
    final me = _me;
    final channel = _presence;
    if (me == null || channel == null) return;
    final now = DateTime.now();
    final last = _lastTypingBroadcast;
    if (last != null && now.difference(last) < _typingThrottle) return;
    _lastTypingBroadcast = now;
    final name = ref.read(myProfileProvider).value?.name ?? 'Someone';
    unawaited(_broadcastTyping(channel, userId: me, name: name));
  }

  Future<void> _broadcastTyping(
    RealtimeChannel channel, {
    required String userId,
    required String name,
  }) async {
    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: <String, dynamic>{'user_id': userId, 'name': name},
      );
    } catch (_) {
      // A dropped keystroke event is not worth a banner.
    }
  }

  void _onTypingBroadcast(Map<String, dynamic> payload) {
    final data = asMap(payload['payload'] ?? payload);
    final userId = asString(data['user_id']);
    if (userId.isEmpty || userId == _me) return;
    _typing[userId] = TypingUser(
      userId: userId,
      name: asString(data['name'], 'Someone'),
      at: DateTime.now(),
    );
    _publishTyping();
    _typingSweeper ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sweepTyping(),
    );
  }

  void _sweepTyping() {
    final cutoff = DateTime.now().subtract(_typingTtl);
    final stale = <String>[
      for (final entry in _typing.entries)
        if (entry.value.at.isBefore(cutoff)) entry.key,
    ];
    if (stale.isEmpty) return;
    for (final key in stale) {
      _typing.remove(key);
    }
    if (_typing.isEmpty) {
      _typingSweeper?.cancel();
      _typingSweeper = null;
    }
    _publishTyping();
  }

  void _publishTyping() {
    if (_disposed) return;
    state = state.copyWith(typing: <TypingUser>[..._typing.values]);
  }

  // ───────────────────────────────────────────────────────────── outgoing ──

  /// Sends text, optionally quoting [replyToId] or attaching a KLECT entity.
  Future<void> sendText({
    String? body,
    String? replyToId,
    EntityType? sharedEntityType,
    String? sharedEntityId,
  }) async {
    final trimmed = body?.trim();
    final hasBody = trimmed != null && trimmed.isNotEmpty;
    if (!hasBody && sharedEntityId == null) return;
    await _send(
      _PendingSend(
        id: _api.newId(),
        body: hasBody ? trimmed : null,
        kind: MessageKind.text,
        replyToId: replyToId,
        sharedEntityType: sharedEntityType,
        sharedEntityId: sharedEntityId,
      ),
    );
  }

  /// Uploads a photo to the private `chat` bucket, then sends it.
  ///
  /// The bubble appears immediately rendering [bytes] from memory, so the
  /// upload never looks like a hang.
  Future<void> sendPhoto({
    required Uint8List bytes,
    required int width,
    required int height,
    String contentType = 'image/jpeg',
    String extension = 'jpg',
    String? caption,
    String? replyToId,
  }) async {
    final id = _api.newId();
    _localPreviews[id] = bytes;
    final caption0 = caption?.trim();
    await _send(
      _PendingSend(
        id: id,
        body: (caption0 == null || caption0.isEmpty) ? null : caption0,
        kind: MessageKind.image,
        replyToId: replyToId,
        upload: _PendingUpload(
          bytes: bytes,
          width: width,
          height: height,
          contentType: contentType,
          extension: extension,
        ),
      ),
    );
  }

  /// Writes the `call_event` marker that keeps the call log inside the thread.
  Future<void> sendCallEvent({
    required String callId,
    required String body,
  }) async {
    try {
      await _api.sendMessage(
        conversationId: conversationId,
        body: body,
        kind: MessageKind.callEvent,
        callId: callId,
      );
    } on KlectError {
      // A missing call marker must never break hanging up.
    }
  }

  Future<void> _send(_PendingSend request) async {
    _pending[request.id] = request;
    final placeholder = ChatMessage(
      message: MessageModel(
        id: request.id,
        conversationId: conversationId,
        authorId: _me,
        body: request.body,
        kind: request.kind,
        attachments: request.upload == null
            ? const <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[
                ChatAttachment(
                  storagePath: '',
                  width: request.upload!.width,
                  height: request.upload!.height,
                ).toJson(),
              ],
        sharedEntityType: request.sharedEntityType,
        sharedEntityId: request.sharedEntityId,
        replyToId: request.replyToId,
        createdAt: DateTime.now(),
        author: ref.read(myProfileProvider).value,
      ),
      replyTo: _findMessage(request.replyToId)?.message,
      pending: true,
    );
    state = state.copyWith(
      messages: <ChatMessage>[placeholder, ...state.messages],
    );
    await _flush(request);
  }

  Future<void> _flush(_PendingSend request) async {
    try {
      final upload = request.upload;
      final attachments = <ChatAttachment>[
        if (upload != null)
          await _api.uploadImage(
            conversationId: conversationId,
            bytes: upload.bytes,
            width: upload.width,
            height: upload.height,
            contentType: upload.contentType,
            extension: upload.extension,
          ),
      ];
      final sent = await _api.sendMessage(
        conversationId: conversationId,
        id: request.id,
        body: request.body,
        kind: request.kind,
        attachments: attachments,
        sharedEntityType: request.sharedEntityType,
        sharedEntityId: request.sharedEntityId,
        replyToId: request.replyToId,
      );
      if (_disposed) return;
      _pending.remove(request.id);
      _localPreviews.remove(request.id);
      final index = _indexOf(request.id);
      if (index == -1) {
        state = state.copyWith(
          messages: <ChatMessage>[sent, ...state.messages],
        );
      } else {
        _replaceMessage(index, sent);
      }
    } catch (error) {
      if (_disposed) return;
      final normalised = KlectError.from(error);
      if (normalised.kind == KlectErrorKind.duplicate) {
        // The insert actually landed; the retry raced the first attempt.
        _pending.remove(request.id);
        unawaited(_hydrateInserted(request.id));
        return;
      }
      final index = _indexOf(request.id);
      if (index != -1) {
        _replaceMessage(
          index,
          state.messages[index].copyWith(pending: false, failed: true),
        );
      }
      state = state.copyWith(error: normalised);
    }
  }

  /// Retries a message whose insert failed. The id is reused, so a send that
  /// actually succeeded comes back as a duplicate and is treated as success.
  Future<void> retry(String messageId) async {
    final request = _pending[messageId];
    if (request == null) return;
    final index = _indexOf(messageId);
    if (index != -1) {
      _replaceMessage(
        index,
        state.messages[index].copyWith(pending: true, failed: false),
      );
    }
    state = state.copyWith(clearError: true);
    await _flush(request);
  }

  /// Drops a failed message without sending it.
  void discard(String messageId) {
    _pending.remove(messageId);
    _localPreviews.remove(messageId);
    _removeMessage(messageId);
  }

  /// The bytes of a photo still uploading, so the bubble can render it from
  /// memory instead of a spinner.
  Uint8List? localPreview(String messageId) => _localPreviews[messageId];

  /// The text a failed message carried, so the composer can restore the draft.
  String? draftFor(String messageId) => _pending[messageId]?.body;

  // ────────────────────────────────────────────────────────────── editing ──

  /// Rewrites the viewer's own message.
  Future<void> edit(String messageId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final index = _indexOf(messageId);
    if (index == -1) return;
    final before = state.messages[index];
    _replaceMessage(
      index,
      before.copyWith(message: before.message.copyWith(body: trimmed)),
    );
    try {
      await _api.editMessage(messageId, trimmed);
    } catch (error) {
      if (_disposed) return;
      final now = _indexOf(messageId);
      if (now != -1) _replaceMessage(now, before);
      state = state.copyWith(error: KlectError.from(error));
    }
  }

  /// Turns the viewer's own message into a tombstone for every participant.
  ///
  /// Optimistic and in place: the tombstone is painted at the message's own
  /// index before the RPC is issued, so nothing is removed from the thread and
  /// neither the position nor the original timestamp moves (11.3).
  ///
  /// Returns `null` once the delete has committed. On any failure, or after
  /// [deleteTimeout] with no answer, the exact [ChatMessage] captured
  /// beforehand is put back — the same body and the same whole attachment set,
  /// object for object — the stored row is left untouched, and the failure is
  /// **returned** rather than pushed onto `state.error`, so the caller surfaces
  /// exactly one error indication and can carry the retry on it (11.12).
  Future<KlectError?> deleteForEveryone(String messageId) async {
    final index = _indexOf(messageId);
    if (index == -1) return null;
    final before = state.messages[index];
    _replaceMessage(
      index,
      before.copyWith(
        message: before.message.tombstoned(),
        pending: false,
        failed: false,
      ),
    );
    try {
      final stored = await _api
          .deleteMessageForEveryone(messageId)
          .timeout(deleteTimeout);
      if (_disposed) return null;
      final now = _indexOf(messageId);
      if (now == -1) return null;
      final current = state.messages[now];
      // The RPC answers with the bare `messages` row: no author profile and no
      // embedded parent. Only the deletion state is taken from it; the rest of
      // the loaded shape stays where it is.
      _replaceMessage(
        now,
        current.copyWith(
          message: stored.message.copyWith(
            author: current.message.author,
            hiddenForMe: current.hiddenForMe,
          ),
          pending: false,
          failed: false,
        ),
      );
      return null;
    } catch (error) {
      if (_disposed) return null;
      final now = _indexOf(messageId);
      if (now != -1) _replaceMessage(now, before);
      return KlectError.from(error);
    }
  }

  /// Hides one message only for the signed-in viewer.
  ///
  /// The rendered row disappears synchronously, well inside the 500 ms budget.
  /// A failed stored-message RPC restores the exact row at its original order;
  /// a pending/failed local send has no server row and is simply discarded.
  Future<KlectError?> hideForMe(String messageId) async {
    final index = _indexOf(messageId);
    if (index == -1) return null;
    final before = state.messages[index];
    _hidden.add(messageId);
    _removeMessage(messageId);

    if (before.pending || before.failed) {
      _pending.remove(messageId);
      _localPreviews.remove(messageId);
      return null;
    }

    try {
      await _api.hideMessageForMe(messageId).timeout(deleteTimeout);
      return null;
    } catch (error) {
      if (_disposed) return null;
      _hidden.remove(messageId);
      final restored = <ChatMessage>[...state.messages, before]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(messages: restored);
      return KlectError.from(error);
    }
  }

  // ──────────────────────────────────────────────────────────── reactions ──

  /// Adds or removes one of the viewer's reactions, optimistically.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final me = _me;
    if (me == null) return;
    final index = _indexOf(messageId);
    if (index == -1) return;
    final before = state.messages[index];
    final mine = MessageReaction(
      messageId: messageId,
      userId: me,
      emoji: emoji,
    );
    final had = before.reactions.contains(mine);

    _replaceMessage(
      index,
      before.copyWith(
        reactions: had
            ? <MessageReaction>[
                for (final reaction in before.reactions)
                  if (reaction != mine) reaction,
              ]
            : <MessageReaction>[...before.reactions, mine],
      ),
    );

    try {
      if (had) {
        await _api.unreact(messageId, emoji);
      } else {
        await _api.react(messageId, emoji);
      }
    } catch (error) {
      if (_disposed) return;
      final now = _indexOf(messageId);
      if (now != -1) _replaceMessage(now, before);
      state = state.copyWith(error: KlectError.from(error));
    }
  }

  /// Drops the sticky error banner.
  void clearError() => state = state.copyWith(clearError: true);

  // ───────────────────────────────────────────────────────────── plumbing ──

  int _indexOf(String messageId) =>
      state.messages.indexWhere((message) => message.id == messageId);

  ChatMessage? _findMessage(String? messageId) {
    if (messageId == null) return null;
    final index = _indexOf(messageId);
    return index == -1 ? null : state.messages[index];
  }

  void _replaceMessage(int index, ChatMessage message) {
    final next = <ChatMessage>[...state.messages];
    next[index] = message;
    state = state.copyWith(messages: next);
  }

  void _removeMessage(String messageId) {
    final next = <ChatMessage>[
      for (final message in state.messages)
        if (message.id != messageId) message,
    ];
    if (next.length == state.messages.length) return;
    state = state.copyWith(messages: next);
  }
}

class _PendingUpload {
  const _PendingUpload({
    required this.bytes,
    required this.width,
    required this.height,
    required this.contentType,
    required this.extension,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String contentType;
  final String extension;
}

class _PendingSend {
  const _PendingSend({
    required this.id,
    required this.kind,
    this.body,
    this.replyToId,
    this.sharedEntityType,
    this.sharedEntityId,
    this.upload,
  });

  final String id;
  final MessageKind kind;
  final String? body;
  final String? replyToId;
  final EntityType? sharedEntityType;
  final String? sharedEntityId;
  final _PendingUpload? upload;
}

/// One open conversation. Auto-disposed so its realtime channels go away with
/// the screen.
final chatThreadProvider = NotifierProvider.autoDispose
    .family<ChatThreadController, ChatThreadState, String>(
      ChatThreadController.new,
      name: 'chatThread',
    );

/// The rich card for a shared collection / subcollection / item, cached per
/// `(type, id)` so a thread full of the same share fetches once.
final sharedEntityPreviewProvider = FutureProvider.autoDispose
    .family<SharedEntityPreview?, ({EntityType type, String id})>(
      (ref, key) =>
          ref.watch(chatApiProvider).fetchEntityPreview(key.type, key.id),
      name: 'sharedEntityPreview',
    );

/// A signed URL for one `chat` bucket object. The bucket is private, so every
/// attachment goes through here.
final chatAttachmentUrlProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, storagePath) => ref.watch(chatApiProvider).signedUrl(storagePath),
      name: 'chatAttachmentUrl',
    );
