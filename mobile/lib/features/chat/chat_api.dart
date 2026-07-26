import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import 'chat_models.dart';

/// The chat feature's data surface.
///
/// ### Why this exists next to [KlectApi]
/// [KlectApi] is the app-wide Supabase boundary and covers most of messaging
/// already — `start_dm`, `mark_conversation_read`, `fetchConversations`,
/// `sendMessage`, `reactToMessage`, `createCall`, `sendCallSignal`. Chat needs
/// a handful of operations it does not expose (message edit/delete, reaction
/// reads, the per-viewer `pinned` / `archived_at` / `muted_until` membership
/// flags, `messages.call_id`, chat-bucket uploads, and the inbox / thread /
/// presence realtime channels).
///
/// Rather than scattering `client.from(...)` calls through the widgets, this
/// class is the **single** place the chat feature touches Supabase. Everything
/// it does not need to add is delegated straight to [KlectApi], and every
/// method throws [KlectError] and nothing else — exactly like [KlectApi].
class ChatApi {
  /// Wraps the app-wide API.
  ChatApi(this._api);

  final KlectApi _api;
  final Uuid _uuid = const Uuid();

  /// The columns a thread row needs: the author, its reactions, and enough of
  /// the parent message to draw a quoted preview.
  static const String _messageSelect =
      '*, author:profiles!author_id(*), reactions:message_reactions(*), '
      'reply_to:messages!reply_to_id(id, conversation_id, body, author_id, '
      'kind, attachments, shared_entity_type, shared_entity_id, created_at, '
      'deleted_at)';

  SupabaseClient get _client => _api.client;

  /// The app-wide API, for everything chat does not need to extend.
  KlectApi get api => _api;

  /// The signed-in user's id, or null.
  String? get currentUserId => _api.currentUserId;

  /// The signed-in user's id, or throws.
  String get requireUserId => _api.requireUserId;

  /// A fresh client-side uuid — used so an optimistic message carries the id
  /// the insert will really use, and the realtime echo dedupes against it.
  String newId() => _uuid.v4();

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw KlectError.from(error);
    }
  }

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _guard(() => _client.rpc<dynamic>(fn, params: params));

  // ──────────────────────────────────────────────────────────────── inbox ──

  /// The viewer's inbox, pinned first then most recent.
  ///
  /// Two round trips, never N+1: one for the memberships (with the conversation
  /// embedded), one for the *other* members' profiles across every row.
  Future<List<ChatInboxEntry>> fetchInbox({int limit = 60}) async {
    final me = requireUserId;
    final rows = await _guard(
      () => _client
          .from('conversation_members')
          .select(
            'conversation_id, unread_count, last_read_at, pinned, '
            'archived_at, muted_until, conversations!inner(*)',
          )
          .eq('user_id', me)
          .isFilter('left_at', null)
          // `conversation_members` has no `created_at`; ordering by `joined_at`
          // is what makes `limit` deterministic. The inbox's real order is
          // applied client-side by `ChatInboxEntry.compare`, because "pinned
          // first, then last activity" spans two tables.
          .order('joined_at', ascending: false)
          .limit(limit),
    );

    final entries = <ChatInboxEntry>[];
    for (final row in rows) {
      final conversationJson = asMap(row['conversations']);
      if (conversationJson.isEmpty) continue;
      conversationJson['unread_count'] = asInt(row['unread_count']);
      entries.add(
        ChatInboxEntry(
          conversation: Conversation.fromJson(conversationJson),
          pinned: asBool(row['pinned']),
          archivedAt: asDateOrNull(row['archived_at']),
          mutedUntil: asDateOrNull(row['muted_until']),
          lastReadAt: asDateOrNull(row['last_read_at']),
        ),
      );
    }
    if (entries.isEmpty) return entries;

    final counterparts = await _fetchCounterparts(
      <String>[for (final entry in entries) entry.id],
      me,
    );
    final resolved = <ChatInboxEntry>[
      for (final entry in entries)
        entry.copyWith(
          conversation: entry.conversation.copyWith(
            otherMember: counterparts[entry.id],
          ),
        ),
    ]..sort(ChatInboxEntry.compare);
    return resolved;
  }

  /// One inbox row, refetched after a realtime insert.
  Future<ChatInboxEntry?> fetchInboxEntry(String conversationId) async {
    final me = requireUserId;
    final row = await _guard(
      () => _client
          .from('conversation_members')
          .select(
            'conversation_id, unread_count, last_read_at, pinned, '
            'archived_at, muted_until, conversations!inner(*)',
          )
          .eq('user_id', me)
          .eq('conversation_id', conversationId)
          .maybeSingle(),
    );
    if (row == null) return null;
    final conversationJson = asMap(row['conversations']);
    if (conversationJson.isEmpty) return null;
    conversationJson['unread_count'] = asInt(row['unread_count']);
    final counterparts = await _fetchCounterparts(<String>[conversationId], me);
    return ChatInboxEntry(
      conversation: Conversation.fromJson(conversationJson)
          .copyWith(otherMember: counterparts[conversationId]),
      pinned: asBool(row['pinned']),
      archivedAt: asDateOrNull(row['archived_at']),
      mutedUntil: asDateOrNull(row['muted_until']),
      lastReadAt: asDateOrNull(row['last_read_at']),
    );
  }

  Future<Map<String, Profile>> _fetchCounterparts(
    List<String> conversationIds,
    String me,
  ) async {
    if (conversationIds.isEmpty) return const <String, Profile>{};
    final rows = await _guard(
      () => _client
          .from('conversation_members')
          .select('conversation_id, user_id, profile:profiles!user_id(*)')
          .inFilter('conversation_id', conversationIds)
          .neq('user_id', me),
    );
    final result = <String, Profile>{};
    for (final row in rows) {
      final conversationId = asString(row['conversation_id']);
      final profile = asMap(row['profile']);
      if (conversationId.isEmpty || profile.isEmpty) continue;
      result.putIfAbsent(conversationId, () => Profile.fromJson(profile));
    }
    return result;
  }

  /// Pins or unpins a conversation for the viewer only.
  Future<void> setPinned(String conversationId, {required bool pinned}) =>
      _patchMembership(conversationId, <String, dynamic>{'pinned': pinned});

  /// Archives or un-archives a conversation for the viewer only.
  Future<void> setArchived(String conversationId, {required bool archived}) =>
      _patchMembership(conversationId, <String, dynamic>{
        'archived_at': archived ? _now() : null,
      });

  /// Mutes notifications for [duration], or unmutes when it is null.
  Future<void> setMuted(String conversationId, {Duration? duration}) =>
      _patchMembership(conversationId, <String, dynamic>{
        'muted_until': duration == null
            ? null
            : DateTime.now().toUtc().add(duration).toIso8601String(),
      });

  /// Leaves a conversation.
  ///
  /// This is what "delete" means for a shared thread: the row survives for the
  /// other member, but it stops appearing in the viewer's inbox. `start_dm`
  /// will hand back the same conversation if they ever message again.
  Future<void> leaveConversation(String conversationId) =>
      _patchMembership(conversationId, <String, dynamic>{'left_at': _now()});

  Future<void> _patchMembership(
    String conversationId,
    Map<String, dynamic> patch,
  ) =>
      _guard(
        () => _client
            .from('conversation_members')
            .update(patch)
            .eq('conversation_id', conversationId)
            .eq('user_id', requireUserId),
      );

  /// Members of one conversation, with profiles. Ordered by `joined_at` —
  /// `conversation_members` has no `created_at`.
  Future<List<ConversationMember>> fetchMembers(String conversationId) async {
    final rows = await _guard(
      () => _client
          .from('conversation_members')
          .select('*, profile:profiles!user_id(*)')
          .eq('conversation_id', conversationId)
          .order('joined_at'),
    );
    return <ConversationMember>[
      for (final row in rows) ConversationMember.fromJson(row),
    ];
  }

  /// One conversation row.
  Future<Conversation?> fetchConversation(String conversationId) async {
    final row = await _guard(
      () => _client
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .maybeSingle(),
    );
    return row == null ? null : Conversation.fromJson(row);
  }

  /// `mark_conversation_read(p_conversation)`.
  Future<void> markRead(String conversationId) =>
      _api.markConversationRead(conversationId);

  /// `start_dm(p_other)` — one DM per pair, ever.
  Future<String> startDm(String otherUserId) => _api.startDm(otherUserId);

  // ─────────────────────────────────────────────────────────────── groups ──
  // Thin wrappers over the five RPCs of `0017_group_chats.sql`. Every rule —
  // dedupe, blocks, the 64-member cap, role checks, ownership transfer —
  // lives server-side; these methods only carry the arguments across. Errors
  // arrive as stable snake_case texts (`not_admin`, `group_full`, …) inside a
  // [KlectError]; `groupErrorCopy` turns them into human copy.

  /// `create_group(p_title, p_members, ...)` → the new conversation id.
  ///
  /// The caller becomes `owner`, everyone in [memberIds] becomes `member`,
  /// and a system message marks the birth of the thread.
  Future<String> createGroup({
    required String title,
    required List<String> memberIds,
    String? description,
    String? avatarPath,
  }) async =>
      asString(
        await _rpc('create_group', <String, dynamic>{
          'p_title': title,
          'p_members': memberIds,
          'p_description': description,
          'p_avatar_path': avatarPath,
        }),
      );

  /// `add_group_members(p_conversation, p_members)` — admin/owner only.
  ///
  /// Returns how many people actually joined; already-present and blocked
  /// candidates are skipped silently, so 0 is a success, not a failure.
  Future<int> addGroupMembers(
    String conversationId,
    List<String> memberIds,
  ) async =>
      asInt(
        await _rpc('add_group_members', <String, dynamic>{
          'p_conversation': conversationId,
          'p_members': memberIds,
        }),
      );

  /// `remove_group_member(p_conversation, p_member)`.
  ///
  /// Pass the viewer's own id to leave; anything else requires admin/owner,
  /// and the owner can never be removed by someone else.
  Future<void> removeGroupMember(String conversationId, String memberId) async {
    await _rpc('remove_group_member', <String, dynamic>{
      'p_conversation': conversationId,
      'p_member': memberId,
    });
  }

  /// `update_group_info(p_conversation, ...)` — admin/owner only.
  ///
  /// Null arguments mean "keep the current value"; an empty [description]
  /// clears it. A rename emits a system message server-side.
  Future<void> updateGroupInfo(
    String conversationId, {
    String? title,
    String? description,
    String? avatarPath,
  }) async {
    await _rpc('update_group_info', <String, dynamic>{
      'p_conversation': conversationId,
      'p_title': title,
      'p_description': description,
      'p_avatar_path': avatarPath,
    });
  }

  /// `set_group_member_role(p_conversation, p_member, p_role)` — owner only.
  ///
  /// Granting `owner` transfers ownership and demotes the previous owner to
  /// `admin`.
  Future<void> setGroupMemberRole(
    String conversationId,
    String memberId,
    String role,
  ) async {
    await _rpc('set_group_member_role', <String, dynamic>{
      'p_conversation': conversationId,
      'p_member': memberId,
      'p_role': role,
    });
  }

  // ─────────────────────────────────────────────────────────────── thread ──

  /// A page of messages, newest first. Pass the oldest [before] you hold to
  /// page backwards.
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    int limit = 40,
    DateTime? before,
  }) async {
    var query = _client
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null);
    final cutoff = isoOrNull(before);
    if (cutoff != null) query = query.lt('created_at', cutoff);
    final rows = await _guard(
      () => query.order('created_at', ascending: false).limit(limit),
    );
    return <ChatMessage>[for (final row in rows) ChatMessage.fromJson(row)];
  }

  /// One message in the thread shape — used to hydrate a realtime INSERT,
  /// whose payload carries neither the author profile nor the parent.
  Future<ChatMessage?> fetchMessage(String messageId) async {
    final row = await _guard(
      () => _client
          .from('messages')
          .select(_messageSelect)
          .eq('id', messageId)
          .maybeSingle(),
    );
    return row == null ? null : ChatMessage.fromJson(row);
  }

  /// Sends a message by **inserting** it — triggers then write the conversation
  /// preview, bump every other member's unread count, and fan out
  /// notifications.
  ///
  /// [id] lets the caller pre-generate the primary key so the optimistic bubble
  /// and the realtime echo are the same row.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    String? id,
    String? body,
    MessageKind kind = MessageKind.text,
    List<ChatAttachment> attachments = const <ChatAttachment>[],
    EntityType? sharedEntityType,
    String? sharedEntityId,
    String? replyToId,
    String? callId,
  }) async {
    final row = await _guard(
      () => _client
          .from('messages')
          .insert(<String, dynamic>{
            'id': ?id,
            'conversation_id': conversationId,
            'author_id': requireUserId,
            'body': body,
            'kind': kind.wire,
            'attachments': <Map<String, dynamic>>[
              for (final attachment in attachments) attachment.toJson(),
            ],
            'shared_entity_type': sharedEntityType?.wire,
            'shared_entity_id': sharedEntityId,
            'reply_to_id': replyToId,
            'call_id': ?callId,
          })
          .select(_messageSelect)
          .single(),
    );
    return ChatMessage.fromJson(row);
  }

  /// Server-side search within one conversation: a case-insensitive substring
  /// match on `body`, newest first, capped at [limit]. RLS already scopes
  /// `messages` to conversations the viewer belongs to, so no extra guard is
  /// needed here.
  Future<List<MessageModel>> searchMessages(
    String conversationId,
    String term, {
    int limit = 50,
  }) async {
    // `%` and `_` are `ilike` wildcards; escape them (and the escape character
    // itself) so the user searches for literals, not patterns.
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await _guard(
      () => _client
          .from('messages')
          .select('*, author:profiles!author_id(*)')
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null)
          .ilike('body', '%$escaped%')
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return <MessageModel>[for (final row in rows) MessageModel.fromJson(row)];
  }

  /// Re-sends [message] into [targetConversationId] as a brand-new message.
  ///
  /// Text and entity shares are plain re-inserts; the quote (`reply_to_id`)
  /// deliberately does not travel — a forward is a new utterance, not a reply.
  /// Image attachments are **copied** inside the private `chat` bucket to a
  /// path the target's members can actually read
  /// (`{me}/{target_conversation}/{uuid}`); a forwarded message must never
  /// reference the source conversation's objects.
  Future<void> forwardMessage({
    required ChatMessage message,
    required String targetConversationId,
  }) async {
    final attachments = <ChatAttachment>[
      for (final attachment in message.attachments)
        await _copyAttachment(attachment, targetConversationId),
    ];
    await sendMessage(
      conversationId: targetConversationId,
      body: message.message.body,
      kind: message.message.kind,
      attachments: attachments,
      sharedEntityType: message.message.sharedEntityType,
      sharedEntityId: message.message.sharedEntityId,
    );
  }

  Future<ChatAttachment> _copyAttachment(
    ChatAttachment attachment,
    String targetConversationId,
  ) async {
    final source = attachment.storagePath;
    final slash = source.lastIndexOf('/');
    final dot = source.lastIndexOf('.');
    final extension = dot > slash ? source.substring(dot) : '';
    final destination =
        '$requireUserId/$targetConversationId/${newId()}$extension';
    await _guard(
      () => _client.storage
          .from(StorageBucket.chat.id)
          .copy(source, destination),
    );
    return ChatAttachment(
      storagePath: destination,
      width: attachment.width,
      height: attachment.height,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      blurhash: attachment.blurhash,
    );
  }

  /// Rewrites the body of the viewer's own message and stamps `edited_at`.
  Future<void> editMessage(String messageId, String body) => _guard(
        () => _client
            .from('messages')
            .update(<String, dynamic>{'body': body, 'edited_at': _now()})
            .eq('id', messageId)
            .eq('author_id', requireUserId),
      );

  /// Soft-deletes the viewer's own message. Threads filter on
  /// `deleted_at is null`, so the bubble disappears on both sides.
  Future<void> deleteMessage(String messageId) => _guard(
        () => _client
            .from('messages')
            .update(<String, dynamic>{'deleted_at': _now(), 'body': null})
            .eq('id', messageId)
            .eq('author_id', requireUserId),
      );

  /// Adds an emoji reaction.
  Future<void> react(String messageId, String emoji) =>
      _api.reactToMessage(messageId, emoji);

  /// Removes an emoji reaction.
  Future<void> unreact(String messageId, String emoji) =>
      _api.unreactToMessage(messageId, emoji);

  // ──────────────────────────────────────────────────────── shared entity ──

  /// The lite card shown for a shared collection / subcollection / item.
  ///
  /// Posts and comments are not shareable into a thread, so they resolve to
  /// null rather than inventing a shape.
  Future<SharedEntityPreview?> fetchEntityPreview(
    EntityType type,
    String id,
  ) async {
    switch (type) {
      case EntityType.collection:
        final row = await _guard(
          () => _client
              .from('collections')
              .select('id, name, description, cover_path, cover_blurhash, '
                  'item_count, subcollection_count')
              .eq('id', id)
              .maybeSingle(),
        );
        if (row == null) return null;
        final subcollections = asInt(row['subcollection_count']);
        final items = asInt(row['item_count']);
        return SharedEntityPreview(
          entityType: type,
          entityId: id,
          title: asString(row['name']),
          subtitle: '$subcollections subcollections · $items items',
          coverPath: asStringOrNull(row['cover_path']),
          coverBlurhash: asStringOrNull(row['cover_blurhash']),
        );
      case EntityType.subcollection:
        final row = await _guard(
          () => _client
              .from('subcollections')
              .select('id, name, description, cover_path, cover_blurhash, '
                  'item_count')
              .eq('id', id)
              .maybeSingle(),
        );
        if (row == null) return null;
        return SharedEntityPreview(
          entityType: type,
          entityId: id,
          title: asString(row['name']),
          subtitle: '${asInt(row['item_count'])} items',
          coverPath: asStringOrNull(row['cover_path']),
          coverBlurhash: asStringOrNull(row['cover_blurhash']),
        );
      case EntityType.item:
        final row = await _guard(
          () => _client
              .from('items')
              .select('id, title, brand, cover_path, cover_blurhash')
              .eq('id', id)
              .maybeSingle(),
        );
        if (row == null) return null;
        return SharedEntityPreview(
          entityType: type,
          entityId: id,
          title: asString(row['title']),
          subtitle: asStringOrNull(row['brand']),
          coverPath: asStringOrNull(row['cover_path']),
          coverBlurhash: asStringOrNull(row['cover_blurhash']),
        );
      case EntityType.post:
      case EntityType.comment:
        return null;
    }
  }

  // ────────────────────────────────────────────────────────────── storage ──

  /// Uploads a photo to the private `chat` bucket at
  /// `{user_id}/{conversation_id}/{uuid}` and returns its descriptor.
  Future<ChatAttachment> uploadImage({
    required String conversationId,
    required Uint8List bytes,
    required int width,
    required int height,
    String contentType = 'image/jpeg',
    String extension = 'jpg',
  }) async {
    final key = '$requireUserId/$conversationId/${newId()}.$extension';
    final stored = await _api.upload(
      bucket: StorageBucket.chat,
      objectPath: key,
      bytes: bytes,
      contentType: contentType,
    );
    return ChatAttachment(
      storagePath: stored,
      width: width,
      height: height,
      mimeType: contentType,
      sizeBytes: bytes.lengthInBytes,
    );
  }

  /// A time-limited URL for a `chat` object. The bucket is private, so this is
  /// the only way an attachment renders.
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) =>
      _api.signedUrl(
        path,
        expiresInSeconds: expiresInSeconds,
      );

  /// Resolves a public path (avatars, covers) to an absolute URL.
  String? publicUrl(String? path, {StorageBucket bucket = StorageBucket.media}) =>
      _api.publicUrl(path, bucket: bucket);

  // ──────────────────────────────────────────────────────────────── calls ──

  /// Creates a `calls` row in `ringing`.
  Future<CallModel> createCall({
    required String conversationId,
    CallKind kind = CallKind.audio,
  }) =>
      _api.createCall(conversationId: conversationId, kind: kind);

  /// Reads one call.
  Future<CallModel?> fetchCall(String callId) => _api.fetchCall(callId);

  /// Moves a call through its lifecycle.
  Future<void> updateCallStatus(
    String callId,
    CallStatus status, {
    int? durationSeconds,
    String? endReason,
  }) =>
      _api.updateCallStatus(
        callId,
        status,
        durationSeconds: durationSeconds,
        endReason: endReason,
      );

  /// Records that the viewer joined the media session.
  Future<void> joinCall(String callId) => _api.joinCall(callId);

  /// Records that the viewer left the media session.
  Future<void> leaveCall(String callId) => _api.leaveCall(callId);

  /// Sends one WebRTC signal.
  Future<void> sendCallSignal({
    required String callId,
    required CallSignalType type,
    required Map<String, dynamic> payload,
    String? recipientId,
  }) =>
      _api.sendCallSignal(
        callId: callId,
        type: type,
        payload: payload,
        recipientId: recipientId,
      );

  /// Every signal for a call, oldest first.
  ///
  /// Realtime can only deliver what arrives *after* the subscription is live;
  /// the callee usually subscribes after the caller has already inserted the
  /// offer. Replaying the table on join closes that race.
  Future<List<CallSignal>> fetchCallSignals(String callId) async {
    final rows = await _guard(
      () => _client
          .from('call_signals')
          .select()
          .eq('call_id', callId)
          .order('created_at'),
    );
    return <CallSignal>[for (final row in rows) CallSignal.fromJson(row)];
  }

  /// Calls still ringing that the viewer did not start — the cold-start path
  /// for an incoming call the realtime stream missed.
  Future<List<CallModel>> fetchRingingCalls() async {
    final me = requireUserId;
    final rows = await _guard(
      () => _client
          .from('calls')
          .select()
          .eq('status', CallStatus.ringing.wire)
          .neq('created_by', me)
          .order('created_at', ascending: false)
          .limit(5),
    );
    return <CallModel>[for (final row in rows) CallModel.fromJson(row)];
  }

  // ───────────────────────────────────────────────────────────── realtime ──

  /// Everything the inbox needs to reorder itself live.
  ///
  /// Three bindings on one channel: new/edited messages (RLS limits the stream
  /// to the viewer's own conversations), conversation preview updates, and the
  /// viewer's own membership row for unread / pinned / archived.
  RealtimeChannel inboxChannel({
    required void Function(Map<String, dynamic> row) onMessage,
    required void Function(Map<String, dynamic> row) onConversation,
    required void Function(Map<String, dynamic> row) onMembership,
  }) {
    final me = requireUserId;
    return _client
        .channel('inbox:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => onMessage(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (payload) => onConversation(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (payload) => onMembership(
            payload.newRecord.isEmpty ? payload.oldRecord : payload.newRecord,
          ),
        );
  }

  /// Everything one open thread needs: inserts, edits/deletes, reactions and
  /// the other members' read watermarks.
  ///
  /// `message_reactions` cannot be filtered by conversation, so the binding is
  /// unfiltered and the controller drops rows for messages it does not hold.
  RealtimeChannel threadChannel({
    required String conversationId,
    required void Function(Map<String, dynamic> row) onMessageInsert,
    required void Function(Map<String, dynamic> row) onMessageUpdate,
    required void Function(Map<String, dynamic> row) onReactionInsert,
    required void Function(Map<String, dynamic> row) onReactionDelete,
    required void Function(Map<String, dynamic> row) onMembership,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    return _client
        .channel('thread:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => onMessageInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => onMessageUpdate(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) => onReactionInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) => onReactionDelete(payload.oldRecord),
        )
        .onPostgresChanges(
          // `all`, not `update`: a group gains members while the thread is
          // open, and the join arrives as an INSERT. Rows are never deleted
          // (leaving sets `left_at`), so `newRecord` is always populated.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: filter,
          callback: (payload) => onMembership(payload.newRecord),
        );
  }

  /// The typing / presence channel for one thread.
  ///
  /// Typing is **broadcast**, presence is who has the thread open. Neither ever
  /// touches a table — see `docs/BACKEND_API.md` §3.
  RealtimeChannel presenceChannel({
    required String conversationId,
    required void Function(Map<String, dynamic> payload) onTyping,
    required void Function() onPresence,
  }) {
    final channel = _client.channel(
      'presence:$conversationId',
      // `key` is the presence identity, so a second device replaces rather
      // than duplicates the entry. `self` stays false (the default), which is
      // what keeps our own keystrokes out of our own typing indicator.
      opts: RealtimeChannelConfig(key: requireUserId),
    );
    return channel
        .onBroadcast(event: 'typing', callback: onTyping)
        .onPresenceSync((_) => onPresence())
        .onPresenceJoin((_) => onPresence())
        .onPresenceLeave((_) => onPresence());
  }

  /// Incoming and updated calls anywhere in the app.
  RealtimeChannel callsChannel({
    required void Function(Map<String, dynamic> row) onInsert,
    required void Function(Map<String, dynamic> row) onUpdate,
  }) =>
      _client
          .channel('calls:$requireUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'calls',
            callback: (payload) => onInsert(payload.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            callback: (payload) => onUpdate(payload.newRecord),
          );

  /// UPDATEs on one call row — how each side learns the other answered,
  /// declined or hung up.
  RealtimeChannel callChannel({
    required String callId,
    required void Function(Map<String, dynamic> row) onUpdate,
  }) =>
      _client.channel('call-state:$callId').onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: callId,
            ),
            callback: (payload) => onUpdate(payload.newRecord),
          );

  /// WebRTC signals for one call.
  RealtimeChannel callSignalsChannel({
    required String callId,
    required void Function(Map<String, dynamic> row) onSignal,
  }) =>
      _api.callSignalsChannel(callId: callId, onSignal: onSignal);

  /// Tears a channel down.
  Future<void> removeChannel(RealtimeChannel channel) =>
      _api.removeChannel(channel);

  static String _now() => DateTime.now().toUtc().toIso8601String();
}

/// The chat feature's data surface.
final chatApiProvider = Provider<ChatApi>(
  (ref) => ChatApi(ref.watch(klectApiProvider)),
  name: 'chatApi',
);
