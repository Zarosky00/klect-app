import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../create/media/image_pipeline.dart';
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
  ///
  /// `deleted_at` travels on both the row and the embedded parent, and no read
  /// built on this projection filters on it. A message deleted for everyone
  /// keeps its row with an empty body and no attachments, so the thread renders
  /// a tombstone in place and the quoted preview renders as unavailable —
  /// after a restart and on every older-history page alike (11.13, 11.5).
  static const String _messageSelect =
      '*, author:profiles!author_id(*), reactions:message_reactions(*), '
      'reply_to:messages!reply_to_id(id, conversation_id, body, author_id, '
      'kind, attachments, shared_entity_type, shared_entity_id, created_at, '
      'deleted_at, author:profiles!author_id(id, username, display_name, '
      'avatar_path, is_verified))';

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
            'archived_at, muted_until, request_state, notification_level, '
            'conversations!inner(*)',
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
          requestState: asString(row['request_state'], 'accepted'),
          notificationLevel: asString(row['notification_level'], 'all'),
        ),
      );
    }
    if (entries.isEmpty) return entries;

    final counterparts = await _fetchCounterparts(<String>[
      for (final entry in entries) entry.id,
    ], me);
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
            'archived_at, muted_until, request_state, notification_level, '
            'conversations!inner(*)',
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
      conversation: Conversation.fromJson(
        conversationJson,
      ).copyWith(otherMember: counterparts[conversationId]),
      pinned: asBool(row['pinned']),
      archivedAt: asDateOrNull(row['archived_at']),
      mutedUntil: asDateOrNull(row['muted_until']),
      lastReadAt: asDateOrNull(row['last_read_at']),
      requestState: asString(row['request_state'], 'accepted'),
      notificationLevel: asString(row['notification_level'], 'all'),
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
  ) => _guard(
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
  }) async => asString(
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
  ) async => asInt(
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

  /// Removes the custom group avatar; members fall back to stacked initials.
  Future<void> clearGroupAvatar(String conversationId) async {
    await _rpc('clear_group_avatar', <String, dynamic>{
      'p_conversation': conversationId,
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

  /// Replaces the server-enforced permissions for a group. Owner only.
  Future<GroupPolicy> setGroupPolicy(
    String conversationId,
    GroupPolicy policy,
  ) async {
    final result = asMap(
      await _rpc('set_group_policy', <String, dynamic>{
        'p_conversation': conversationId,
        'p_policy': policy.toJson(),
      }),
    );
    return GroupPolicy.fromJson(result);
  }

  /// Enables or disables approval for invite-link joins. Owner only.
  Future<bool> setGroupJoinApproval(
    String conversationId, {
    required bool required,
  }) async => asBool(
    await _rpc('set_group_join_approval', <String, dynamic>{
      'p_conversation': conversationId,
      'p_required': required,
    }),
  );

  /// Rotates the private invite token and returns the only complete copy.
  Future<String> rotateGroupInvite(String conversationId) async => asString(
    await _rpc('rotate_group_invite', <String, dynamic>{
      'p_conversation': conversationId,
    }),
  );

  /// Revokes the active invite token.
  Future<void> revokeGroupInvite(String conversationId) async {
    await _rpc('revoke_group_invite', <String, dynamic>{
      'p_conversation': conversationId,
    });
  }

  /// Uses a private invite token, returning the group id and membership state.
  Future<({String conversationId, String state})> joinGroupInvite(
    String token,
  ) async {
    final result = asMap(
      await _rpc('join_group_invite', <String, dynamic>{
        'p_token': token.trim(),
      }),
    );
    return (
      conversationId: asString(result['conversation_id']),
      state: asString(result['state'], 'pending'),
    );
  }

  /// Accepts or declines one pending invite-link join request.
  Future<void> reviewGroupJoinRequest(
    String conversationId,
    String memberId, {
    required bool accept,
  }) async {
    await _rpc('review_group_join_request', <String, dynamic>{
      'p_conversation': conversationId,
      'p_member': memberId,
      'p_accept': accept,
    });
  }

  /// Permanently removes a group and its relational rows. Owner only.
  Future<void> deleteGroup(String conversationId) async {
    await _rpc('delete_group', <String, dynamic>{
      'p_conversation': conversationId,
    });
  }

  /// Sets the viewer's notification level for this conversation.
  Future<void> setNotificationLevel(String conversationId, String level) {
    if (!const <String>{'all', 'mentions', 'none'}.contains(level)) {
      throw ArgumentError.value(level, 'level');
    }
    return _patchMembership(conversationId, <String, dynamic>{
      'notification_level': level,
    });
  }

  /// Recent photos shared in a conversation, newest message first.
  Future<List<ChatAttachment>> fetchSharedMedia(
    String conversationId, {
    int limit = 120,
  }) async {
    final rows = await _guard(
      () => _client
          .from('messages')
          .select('attachments')
          .eq('conversation_id', conversationId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return <ChatAttachment>[
      for (final row in rows)
        for (final attachment in asMapList(row['attachments']))
          if (asString(attachment['storage_path']).isNotEmpty)
            ChatAttachment.fromJson(attachment),
    ];
  }

  // ─────────────────────────────────────────────────────────────── thread ──

  /// A page of messages, newest first. Pass the oldest [before] you hold to
  /// page backwards.
  ///
  /// Tombstones are part of the page. Delete-for-me is a separate, per-viewer
  /// concern: read [fetchHiddenMessageIds] alongside the first page and apply
  /// it client-side, so a hidden message never consumes a different code path
  /// from a deleted one (11.13, 12.5).
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    int limit = 40,
    DateTime? before,
  }) async {
    var query = _client
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', conversationId);
    final cutoff = isoOrNull(before);
    if (cutoff != null) query = query.lt('created_at', cutoff);
    final rows = await _guard(
      () => query.order('created_at', ascending: false).limit(limit),
    );
    return <ChatMessage>[for (final row in rows) ChatMessage.fromJson(row)];
  }

  /// One message in the thread shape — used to hydrate a realtime INSERT,
  /// whose payload carries neither the author profile nor the parent.
  ///
  /// Returns tombstones too, so an UPDATE that lands while the row is being
  /// hydrated resolves to the tombstone rather than to null (11.13).
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
    final messageId = id ?? newId();
    await _rpc('send_message', <String, dynamic>{
      'p_conversation': conversationId,
      'p_id': messageId,
      'p_body': body,
      'p_kind': kind.wire,
      'p_attachments': <Map<String, dynamic>>[
        for (final attachment in attachments) attachment.toJson(),
      ],
      'p_shared_entity_type': sharedEntityType?.wire,
      'p_shared_entity_id': sharedEntityId,
      'p_reply_to': replyToId,
      'p_call_id': callId,
    });
    final hydrated = await fetchMessage(messageId);
    if (hydrated == null) {
      throw const KlectError(
        KlectErrorKind.unknown,
        'The message was sent but could not be displayed yet.',
      );
    }
    return hydrated;
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
          // Search keeps the filter the thread reads dropped: a tombstone's
          // body is `''`, so it can never match a term, and returning it would
          // only put an empty result row in the list.
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
      () =>
          _client.storage.from(StorageBucket.chat.id).copy(source, destination),
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

  /// Soft-deletes the viewer's own message with a direct row update.
  ///
  /// Superseded by [deleteMessageForEveryone], which is author-checked,
  /// idempotent and refreshes the inbox preview server-side. The thread
  /// controller has moved across, so nothing calls this any more — it is kept
  /// only until its removal is confirmed, and no new caller should use it.
  Future<void> deleteMessage(String messageId) => _guard(
    () => _client
        .from('messages')
        .update(<String, dynamic>{'deleted_at': _now(), 'body': null})
        .eq('id', messageId)
        .eq('author_id', requireUserId),
  );

  // ────────────────────────────────────────────────────────────── deletion ──

  /// Turns the viewer's own message into a tombstone for every participant.
  ///
  /// The RPC is author-only (`not_message_author`) and idempotent: it keeps the
  /// row's `id`, `author_id`, `reply_to_id` and `created_at`, clears `body` to
  /// `''` and `attachments` to `[]`, and refreshes
  /// `conversations.last_message_preview` only when this really was the
  /// conversation's newest message. A repeat returns the identical row, so a
  /// retry after a timeout is safe (11.1, 11.9, 11.10).
  ///
  /// Returns the stored row in the thread shape. The RPC returns the bare
  /// `messages` row — no author profile and no embedded parent — so the caller
  /// keeps whatever it already holds for those and only takes the deletion
  /// state from here.
  Future<ChatMessage> deleteMessageForEveryone(String messageId) async {
    final row = asMap(
      await _rpc('delete_message_for_everyone', <String, dynamic>{
        'p_message': messageId,
      }),
    );
    if (row.isEmpty) {
      throw const KlectError(
        KlectErrorKind.unknown,
        'The message was deleted but could not be refreshed.',
      );
    }
    return ChatMessage.fromJson(row);
  }

  /// Hides one message from the viewer's own copy of the thread.
  ///
  /// Idempotent per `(message, viewer)`: the RPC inserts into
  /// `public.message_hides` with `on conflict do nothing`, so a repeat succeeds
  /// without producing a second record (12.7). Nothing changes for any other
  /// participant.
  Future<void> hideMessageForMe(String messageId) async {
    await _rpc('hide_message_for_me', <String, dynamic>{
      'p_message': messageId,
    });
  }

  /// The message ids the viewer has hidden in one conversation.
  ///
  /// Read directly from `public.message_hides`, whose own-row RLS policy is
  /// what scopes the result — the viewer id is never sent as a filter, so
  /// another account's hidden set is unreachable rather than merely unrequested
  /// (12.8). Load this with the thread's first page and re-apply it to every
  /// later page and every realtime insert so a hidden message stays hidden
  /// across restart, re-sign-in, edits and reactions (12.5).
  Future<Set<String>> fetchHiddenMessageIds(String conversationId) async {
    final rows = await _guard(
      () => _client
          .from('message_hides')
          .select('message_id')
          .eq('conversation_id', conversationId),
    );
    return <String>{
      for (final row in rows)
        if (asString(row['message_id']).isNotEmpty) asString(row['message_id']),
    };
  }

  /// Adds an emoji reaction.
  Future<void> react(String messageId, String emoji) =>
      _api.reactToMessage(messageId, emoji);

  /// Removes an emoji reaction.
  Future<void> unreact(String messageId, String emoji) =>
      _api.unreactToMessage(messageId, emoji);

  // ──────────────────────────────────────────────────────── shared entity ──

  /// The lite card shown for a shared collection / subcollection / item /
  /// post.
  ///
  /// Comments are not shareable into a thread, so they resolve to null rather
  /// than inventing a shape.
  Future<SharedEntityPreview?> fetchEntityPreview(
    EntityType type,
    String id,
  ) async {
    switch (type) {
      case EntityType.collection:
        final row = await _guard(
          () => _client
              .from('collections')
              .select(
                'id, name, description, cover_path, cover_blurhash, '
                'item_count, subcollection_count',
              )
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
              .select(
                'id, name, description, cover_path, cover_blurhash, '
                'item_count',
              )
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
        final row = await _guard(
          () => _client
              .from('posts')
              .select(
                'id, body, author:profiles!author_id(*), '
                'media:post_media(storage_path, blurhash, position)',
              )
              .eq('id', id)
              .isFilter('deleted_at', null)
              .maybeSingle(),
        );
        if (row == null) return null;
        final author = asMap(row['author']);
        final media = asMapList(
          row['media'],
        )..sort((a, b) => asInt(a['position']).compareTo(asInt(b['position'])));
        final cover = media.isEmpty ? null : media.first;
        final body = asStringOrNull(row['body'])?.trim();
        final by = author.isEmpty ? null : Profile.fromJson(author);
        return SharedEntityPreview(
          entityType: type,
          entityId: id,
          title: body == null || body.isEmpty ? 'A post on KLECT' : body,
          subtitle: by == null ? null : 'by ${by.name}',
          coverPath: cover == null
              ? null
              : asStringOrNull(cover['storage_path']),
          coverBlurhash: cover == null
              ? null
              : asStringOrNull(cover['blurhash']),
        );
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

  /// Uploads an already square-cropped group display photo.
  Future<String> uploadGroupAvatar(PreparedImage image) => _api.upload(
    bucket: StorageBucket.avatars,
    objectPath: '$requireUserId/groups/${newId()}.${image.extension}',
    bytes: image.bytes,
    contentType: image.mimeType,
  );

  /// A time-limited URL for a `chat` object. The bucket is private, so this is
  /// the only way an attachment renders.
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) =>
      _api.signedUrl(path, expiresInSeconds: expiresInSeconds);

  /// Resolves a public path (avatars, covers) to an absolute URL.
  String? publicUrl(
    String? path, {
    StorageBucket bucket = StorageBucket.media,
  }) => _api.publicUrl(path, bucket: bucket);

  // ──────────────────────────────────────────────────────────────── calls ──

  /// Whether reliable one-to-one calling is enabled by the server.
  Future<bool> callFeatureEnabled() async =>
      asBool(await _rpc('call_feature_enabled'));

  /// Creates a `calls` row in `ringing`.
  Future<CallModel> createCall({
    required String conversationId,
    CallKind kind = CallKind.audio,
  }) => _api.createCall(conversationId: conversationId, kind: kind);

  /// Reads one call.
  Future<CallModel?> fetchCall(String callId) => _api.fetchCall(callId);

  /// Transactionally answers a ringing call.
  Future<CallModel> answerCall(String callId, {String? deviceId}) =>
      _api.answerCall(callId, deviceId: deviceId);

  /// Declines a ringing call without disturbing any call already held.
  Future<void> declineCall(String callId, {String reason = 'declined'}) =>
      _api.declineCall(callId, reason: reason);

  /// Moves a call through its lifecycle.
  ///
  /// [clientElapsedSeconds] rides along as a diagnostic only — the stored
  /// duration stays server-computed (Requirement 7.8).
  Future<void> updateCallStatus(
    String callId,
    CallStatus status, {
    int? clientElapsedSeconds,
    String? endReason,
  }) => _api.updateCallStatus(
    callId,
    status,
    clientElapsedSeconds: clientElapsedSeconds,
    endReason: endReason,
  );

  /// Merges one operator-facing diagnostic into `calls.diagnostics`.
  ///
  /// Participant-only server side; the RPC merges rather than replaces, so
  /// several keys can be recorded for one call.
  Future<void> recordCallDiagnostic({
    required String callId,
    required String key,
    required Map<String, dynamic> value,
  }) async {
    await _rpc('record_call_diagnostic', <String, dynamic>{
      'p_call': callId,
      'p_key': key,
      'p_value': value,
    });
  }

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
  }) => _api.sendCallSignal(
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
  }) => _client
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
  }) => _client
      .channel('call-state:$callId')
      .onPostgresChanges(
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
  }) => _api.callSignalsChannel(callId: callId, onSignal: onSignal);

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
