/// View models the chat feature layers on top of `core/models/messaging.dart`.
///
/// `MessageModel` and `Conversation` mirror their tables exactly; these add the
/// things a bubble or an inbox row also needs — reactions, the quoted parent,
/// the viewer's own membership flags — without touching the shared models.
library;

import '../../core/models/models.dart';
import '../../design/tokens.g.dart';

/// One emoji reaction on a message.
///
/// `message_reactions` has no surrogate key: the primary key is
/// `(message_id, user_id, emoji)`, which is also what a realtime DELETE
/// payload carries, so [key] is enough to reconcile the stream.
class MessageReaction {
  /// Creates a reaction.
  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    this.createdAt,
  });

  /// Parses a `message_reactions` row.
  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        messageId: asString(json['message_id']),
        userId: asString(json['user_id']),
        emoji: asString(json['emoji']),
        createdAt: asDateOrNull(json['created_at']),
      );

  /// The message reacted to.
  final String messageId;

  /// Who reacted.
  final String userId;

  /// The emoji itself.
  final String emoji;

  /// When it landed.
  final DateTime? createdAt;

  /// The composite primary key, flattened.
  String get key => '$messageId:$userId:$emoji';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageReaction &&
          other.messageId == messageId &&
          other.userId == userId &&
          other.emoji == emoji;

  @override
  int get hashCode => Object.hash(messageId, userId, emoji);
}

/// One emoji plus how many people picked it — what the bubble actually draws.
class ReactionSummary {
  /// Creates a summary.
  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  /// The emoji.
  final String emoji;

  /// How many people reacted with it.
  final int count;

  /// Whether the viewer is one of them — tapping again removes it.
  final bool mine;
}

/// A photo attached to a message.
///
/// Stored in `messages.attachments` as jsonb. The `chat` bucket is **private**,
/// so [storagePath] must be resolved through a signed URL before it renders.
class ChatAttachment {
  /// Creates an attachment descriptor.
  const ChatAttachment({
    required this.storagePath,
    required this.width,
    required this.height,
    this.mimeType,
    this.sizeBytes,
    this.blurhash,
  });

  /// Parses one entry of `messages.attachments`.
  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        storagePath: asString(json['storage_path']),
        width: asInt(json['width']),
        height: asInt(json['height']),
        mimeType: asStringOrNull(json['mime_type']),
        sizeBytes: asIntOrNull(json['bytes']),
        blurhash: asStringOrNull(json['blurhash']),
      );

  /// Object key inside the `chat` bucket, `{user_id}/{conversation_id}/{uuid}`.
  final String storagePath;

  /// Intrinsic pixel width — reserves the bubble before the bytes arrive.
  final int width;

  /// Intrinsic pixel height.
  final int height;

  /// Content type as uploaded.
  final String? mimeType;

  /// Payload size in bytes.
  final int? sizeBytes;

  /// Optional blurhash placeholder.
  final String? blurhash;

  /// The ratio the bubble reserves, clamped to the grid range so a panorama
  /// or a very tall screenshot still reads as a message.
  double get aspect {
    if (width <= 0 || height <= 0) return Aspect.cover;
    final raw = width / height;
    return raw.clamp(Aspect.gridMin, Aspect.gridMax);
  }

  /// Serialises back into the jsonb column.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'storage_path': storagePath,
        'width': width,
        'height': height,
        'mime_type': ?mimeType,
        'bytes': ?sizeBytes,
        'blurhash': ?blurhash,
      };
}

/// A message plus everything the bubble needs to render it in one pass.
class ChatMessage {
  /// Creates a chat message.
  const ChatMessage({
    required this.message,
    this.reactions = const <MessageReaction>[],
    this.replyTo,
    this.pending = false,
    this.failed = false,
  });

  /// Parses the embed shape used by `ChatApi.fetchMessages`.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final parent = asMap(json['reply_to']);
    return ChatMessage(
      message: MessageModel.fromJson(json),
      reactions: <MessageReaction>[
        for (final row in asMapList(json['reactions']))
          MessageReaction.fromJson(row),
      ],
      replyTo: parent.isEmpty ? null : MessageModel.fromJson(parent),
    );
  }

  /// The row itself.
  final MessageModel message;

  /// Every reaction on it.
  final List<MessageReaction> reactions;

  /// The message this one replies to, when the query embedded it.
  final MessageModel? replyTo;

  /// Client-only: inserted optimistically, no server acknowledgement yet.
  final bool pending;

  /// Client-only: the insert failed and the bubble offers a retry.
  final bool failed;

  /// Primary key — for a pending message this is the client-generated uuid the
  /// insert will actually use, so the realtime echo dedupes cleanly.
  String get id => message.id;

  /// Sender.
  String? get authorId => message.authorId;

  /// Ordering key. Never null in practice; pending messages are stamped
  /// locally at creation.
  DateTime get createdAt =>
      message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Soft-deleted messages are removed from the thread rather than tombstoned.
  bool get isDeleted => message.deletedAt != null;

  /// Whether the sender edited it after the fact.
  bool get isEdited => message.editedAt != null;

  /// Photos carried by this message.
  List<ChatAttachment> get attachments => <ChatAttachment>[
        for (final row in message.attachments) ChatAttachment.fromJson(row),
      ];

  /// True when the body is worth rendering as text.
  bool get hasText => (message.body ?? '').trim().isNotEmpty;

  /// Collapses [reactions] into one row per emoji, most popular first.
  List<ReactionSummary> summarise(String? viewerId) {
    if (reactions.isEmpty) return const <ReactionSummary>[];
    final counts = <String, int>{};
    final mine = <String>{};
    for (final reaction in reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
      if (reaction.userId == viewerId) mine.add(reaction.emoji);
    }
    final summaries = <ReactionSummary>[
      for (final entry in counts.entries)
        ReactionSummary(
          emoji: entry.key,
          count: entry.value,
          mine: mine.contains(entry.key),
        ),
    ]..sort((a, b) => b.count.compareTo(a.count));
    return summaries;
  }

  /// Whether the viewer already reacted with [emoji].
  bool reactedWith(String emoji, String? viewerId) => reactions.any(
        (r) => r.emoji == emoji && r.userId == viewerId,
      );

  /// Copy with overrides.
  ChatMessage copyWith({
    MessageModel? message,
    List<MessageReaction>? reactions,
    MessageModel? replyTo,
    bool? pending,
    bool? failed,
  }) =>
      ChatMessage(
        message: message ?? this.message,
        reactions: reactions ?? this.reactions,
        replyTo: replyTo ?? this.replyTo,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

/// One row of the inbox: a conversation seen through the viewer's membership.
///
/// `pinned`, `archived_at` and `muted_until` live on `conversation_members`,
/// so they are per-viewer, not per-conversation.
class ChatInboxEntry {
  /// Creates an inbox row.
  const ChatInboxEntry({
    required this.conversation,
    this.pinned = false,
    this.archivedAt,
    this.mutedUntil,
    this.lastReadAt,
  });

  /// The conversation.
  final Conversation conversation;

  /// Pinned to the top of the inbox.
  final bool pinned;

  /// Set when the viewer archived it.
  final DateTime? archivedAt;

  /// Notifications silenced until this instant.
  final DateTime? mutedUntil;

  /// Read watermark.
  final DateTime? lastReadAt;

  /// Conversation id — the map key everywhere in this feature.
  String get id => conversation.id;

  /// Whether this row belongs in the archive.
  bool get isArchived => archivedAt != null;

  /// Whether notifications are currently silenced.
  bool get isMuted {
    final until = mutedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Unread badge count, lifted from the membership row.
  int get unreadCount => conversation.unreadCount;

  /// Sort key: last activity, falling back to creation.
  DateTime get sortKey =>
      conversation.lastMessageAt ??
      conversation.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Copy with overrides. Pass the `clear*` flags to null a timestamp, which
  /// `??` alone cannot express.
  ChatInboxEntry copyWith({
    Conversation? conversation,
    bool? pinned,
    DateTime? archivedAt,
    DateTime? mutedUntil,
    DateTime? lastReadAt,
    bool clearArchived = false,
    bool clearMuted = false,
  }) =>
      ChatInboxEntry(
        conversation: conversation ?? this.conversation,
        pinned: pinned ?? this.pinned,
        archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
        mutedUntil: clearMuted ? null : (mutedUntil ?? this.mutedUntil),
        lastReadAt: lastReadAt ?? this.lastReadAt,
      );

  /// Orders the inbox: pinned first, then most recent activity.
  static int compare(ChatInboxEntry a, ChatInboxEntry b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.sortKey.compareTo(a.sortKey);
  }
}

/// The lite preview of a shared collection / subcollection / item, rendered as
/// a rich card inside a bubble.
class SharedEntityPreview {
  /// Creates a preview.
  const SharedEntityPreview({
    required this.entityType,
    required this.entityId,
    required this.title,
    this.subtitle,
    this.coverPath,
    this.coverBlurhash,
  });

  /// Which level of the hierarchy this is.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  /// Collection/subcollection name, or item title.
  final String title;

  /// A second line: the owner, the child count, the brand.
  final String? subtitle;

  /// Cover path or absolute URL.
  final String? coverPath;

  /// Blurhash placeholder for the cover.
  final String? coverBlurhash;
}

/// Somebody typing, learned over Realtime broadcast — never a table.
class TypingUser {
  /// Creates a typing marker.
  const TypingUser({required this.userId, required this.name, required this.at});

  /// Who is typing.
  final String userId;

  /// Their display name, carried in the broadcast payload so the indicator
  /// needs no extra fetch.
  final String name;

  /// When the last keystroke event arrived — markers expire on a timer.
  final DateTime at;
}

/// Everything one open thread needs.
class ChatThreadState {
  /// Creates a thread state.
  const ChatThreadState({
    this.messages = const <ChatMessage>[],
    this.members = const <ConversationMember>[],
    this.typing = const <TypingUser>[],
    this.presentUserIds = const <String>{},
    this.conversation,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  /// Newest first — the thread renders in a reversed list.
  final List<ChatMessage> messages;

  /// Everyone in the conversation, with profiles.
  final List<ConversationMember> members;

  /// Who is typing right now.
  final List<TypingUser> typing;

  /// Who currently has this thread open, from Realtime presence.
  final Set<String> presentUserIds;

  /// The conversation row, once loaded.
  final Conversation? conversation;

  /// First page in flight.
  final bool loading;

  /// Older page in flight.
  final bool loadingMore;

  /// Whether another page exists.
  final bool hasMore;

  /// The last failure, if the thread could not load.
  final Object? error;

  /// The other party of a DM, when the members are loaded.
  ConversationMember? otherMember(String? viewerId) {
    for (final member in members) {
      if (member.userId != viewerId) return member;
    }
    return null;
  }

  /// The furthest anybody else has read — drives the "Seen" receipt.
  DateTime? peerReadAt(String? viewerId) {
    DateTime? furthest;
    for (final member in members) {
      if (member.userId == viewerId) continue;
      final read = member.lastReadAt;
      if (read == null) continue;
      if (furthest == null || read.isAfter(furthest)) furthest = read;
    }
    return furthest;
  }

  /// Whether [userId] has this thread open right now.
  bool isPresent(String? userId) =>
      userId != null && presentUserIds.contains(userId);

  /// Copy with overrides.
  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    List<ConversationMember>? members,
    List<TypingUser>? typing,
    Set<String>? presentUserIds,
    Conversation? conversation,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      ChatThreadState(
        messages: messages ?? this.messages,
        members: members ?? this.members,
        typing: typing ?? this.typing,
        presentUserIds: presentUserIds ?? this.presentUserIds,
        conversation: conversation ?? this.conversation,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}
