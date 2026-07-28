import 'enums.dart';
import 'json.dart';
import 'profile.dart';

/// Who may perform one group action.
enum GroupPermissionScope {
  /// Only the group owner.
  owner,

  /// The owner and admins.
  admins,

  /// Every accepted member.
  everyone;

  /// Parses the Postgres policy value without trusting unknown strings.
  static GroupPermissionScope parse(Object? value) => switch (value) {
    'owner' => GroupPermissionScope.owner,
    'everyone' => GroupPermissionScope.everyone,
    _ => GroupPermissionScope.admins,
  };

  /// Postgres wire value.
  String get wire => name;

  /// Short user-facing label.
  String get label => switch (this) {
    GroupPermissionScope.owner => 'Owner only',
    GroupPermissionScope.admins => 'Owners and admins',
    GroupPermissionScope.everyone => 'Everyone',
  };

  /// Whether a member with [role] is permitted.
  bool allows(String? role) => switch (this) {
    GroupPermissionScope.owner => role == 'owner',
    GroupPermissionScope.admins => role == 'owner' || role == 'admin',
    GroupPermissionScope.everyone => role != null,
  };
}

/// Server-enforced permissions for a group conversation.
class GroupPolicy {
  /// Creates a policy snapshot.
  const GroupPolicy({
    this.editInfo = GroupPermissionScope.admins,
    this.addMembers = GroupPermissionScope.admins,
    this.sendMessages = GroupPermissionScope.everyone,
  });

  /// Parses `conversations.group_policy`.
  factory GroupPolicy.fromJson(Map<String, dynamic> json) => GroupPolicy(
    editInfo: GroupPermissionScope.parse(json['edit_info']),
    addMembers: GroupPermissionScope.parse(json['add_members']),
    sendMessages: GroupPermissionScope.parse(json['send_messages']),
  );

  /// Who may edit the title, description, and photo.
  final GroupPermissionScope editInfo;

  /// Who may add people, manage join requests, and rotate invite links.
  final GroupPermissionScope addMembers;

  /// Who may send messages.
  final GroupPermissionScope sendMessages;

  /// Serialises the exact RPC contract.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'edit_info': editInfo.wire,
    'add_members': addMembers.wire,
    'send_messages': sendMessages.wire,
  };

  /// Copy with one or more permission changes.
  GroupPolicy copyWith({
    GroupPermissionScope? editInfo,
    GroupPermissionScope? addMembers,
    GroupPermissionScope? sendMessages,
  }) => GroupPolicy(
    editInfo: editInfo ?? this.editInfo,
    addMembers: addMembers ?? this.addMembers,
    sendMessages: sendMessages ?? this.sendMessages,
  );
}

/// A row of `public.conversations`.
///
/// `start_dm` guarantees exactly one [ConversationKind.dm] row per pair, ever.
class Conversation {
  /// Creates a conversation.
  const Conversation({
    required this.id,
    this.kind = ConversationKind.dm,
    this.title,
    this.description,
    this.avatarPath,
    this.createdBy,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.createdAt,
    this.updatedAt,
    this.members = const <ConversationMember>[],
    this.unreadCount = 0,
    this.otherMember,
    this.groupPolicy = const GroupPolicy(),
    this.joinApprovalRequired = false,
    this.inviteTokenPrefix,
    this.inviteRotatedAt,
  });

  /// Parses a `conversations` row.
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final members = <ConversationMember>[
      for (final m in asMapList(
        json['conversation_members'] ?? json['members'],
      ))
        ConversationMember.fromJson(m),
    ];
    final other = asMap(json['other_member'] ?? json['other']);
    return Conversation(
      id: asString(json['id']),
      kind: ConversationKind.parse(json['kind']),
      title: asStringOrNull(json['title']),
      description: asStringOrNull(json['description']),
      avatarPath: asStringOrNull(json['avatar_path']),
      createdBy: asStringOrNull(json['created_by']),
      lastMessageAt: asDateOrNull(json['last_message_at']),
      lastMessagePreview: asStringOrNull(json['last_message_preview']),
      createdAt: asDateOrNull(json['created_at']),
      updatedAt: asDateOrNull(json['updated_at']),
      members: members,
      unreadCount: asInt(json['unread_count']),
      otherMember: other.isEmpty ? null : Profile.fromJson(other),
      groupPolicy: GroupPolicy.fromJson(asMap(json['group_policy'])),
      joinApprovalRequired: asBool(json['join_approval_required']),
      inviteTokenPrefix: asStringOrNull(json['invite_token_prefix']),
      inviteRotatedAt: asDateOrNull(json['invite_rotated_at']),
    );
  }

  /// Primary key.
  final String id;

  /// DM or group.
  final ConversationKind kind;

  /// Group title. Null for DMs — use the other member's name.
  final String? title;

  /// Group description. Null for DMs, optional for groups.
  final String? description;

  /// Group avatar. Null for DMs — use the other member's avatar.
  final String? avatarPath;

  /// Who opened it.
  final String? createdBy;

  /// Sort key for the inbox.
  final DateTime? lastMessageAt;

  /// One-line preview maintained by a trigger on `messages`.
  final String? lastMessagePreview;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// Members, when the query embedded them.
  final List<ConversationMember> members;

  /// The viewer's own unread count, lifted from their membership row.
  final int unreadCount;

  /// For DMs: the other participant's profile, when joined.
  final Profile? otherMember;

  /// Server-enforced group permissions. Defaults are ignored for DMs.
  final GroupPolicy groupPolicy;

  /// Whether invite-link joins wait for an admin decision.
  final bool joinApprovalRequired;

  /// Non-secret prefix proving that an active invite exists.
  final String? inviteTokenPrefix;

  /// When the current invite was rotated or revoked.
  final DateTime? inviteRotatedAt;

  /// Inbox row title.
  String get displayTitle =>
      title ??
      otherMember?.name ??
      (kind == ConversationKind.dm ? 'Direct message' : 'Group');

  /// Whether the badge should show.
  bool get hasUnread => unreadCount > 0;

  /// Copy with overrides — used to zero the badge optimistically.
  Conversation copyWith({
    String? title,
    String? description,
    String? avatarPath,
    int? unreadCount,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    Profile? otherMember,
    List<ConversationMember>? members,
    GroupPolicy? groupPolicy,
    bool? joinApprovalRequired,
    String? inviteTokenPrefix,
    DateTime? inviteRotatedAt,
    bool clearDescription = false,
    bool clearAvatar = false,
    bool clearInvite = false,
  }) => Conversation(
    id: id,
    kind: kind,
    title: title ?? this.title,
    description: clearDescription ? null : (description ?? this.description),
    avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    createdBy: createdBy,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    createdAt: createdAt,
    updatedAt: updatedAt,
    members: members ?? this.members,
    unreadCount: unreadCount ?? this.unreadCount,
    otherMember: otherMember ?? this.otherMember,
    groupPolicy: groupPolicy ?? this.groupPolicy,
    joinApprovalRequired: joinApprovalRequired ?? this.joinApprovalRequired,
    inviteTokenPrefix: clearInvite
        ? null
        : (inviteTokenPrefix ?? this.inviteTokenPrefix),
    inviteRotatedAt: inviteRotatedAt ?? this.inviteRotatedAt,
  );
}

/// A row of `public.conversation_members`. Composite key `(conversation_id, user_id)`.
class ConversationMember {
  /// Creates a membership.
  const ConversationMember({
    required this.conversationId,
    required this.userId,
    this.role = 'member',
    this.joinedAt,
    this.lastReadAt,
    this.unreadCount = 0,
    this.mutedUntil,
    this.requestState = 'accepted',
    this.notificationLevel = 'all',
    this.leftAt,
    this.profile,
  });

  /// Parses a `conversation_members` row.
  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    final profile = asMap(json['profile'] ?? json['profiles']);
    return ConversationMember(
      conversationId: asString(json['conversation_id']),
      userId: asString(json['user_id']),
      role: asString(json['role'], 'member'),
      joinedAt: asDateOrNull(json['joined_at']),
      lastReadAt: asDateOrNull(json['last_read_at']),
      unreadCount: asInt(json['unread_count']),
      mutedUntil: asDateOrNull(json['muted_until']),
      requestState: asString(json['request_state'], 'accepted'),
      notificationLevel: asString(json['notification_level'], 'all'),
      leftAt: asDateOrNull(json['left_at']),
      profile: profile.isEmpty ? null : Profile.fromJson(profile),
    );
  }

  /// Which conversation.
  final String conversationId;

  /// Which user.
  final String userId;

  /// `member` | `admin` | `owner`.
  final String role;

  /// When they joined.
  final DateTime? joinedAt;

  /// Read receipt watermark.
  final DateTime? lastReadAt;

  /// Trigger-maintained unread count for this member.
  final int unreadCount;

  /// Notifications muted until this instant.
  final DateTime? mutedUntil;

  /// `pending`, `accepted`, or `declined` for message requests.
  final String requestState;

  /// `all`, `mentions`, or `muted` for per-chat notifications.
  final String notificationLevel;

  /// Set when they leave a group.
  final DateTime? leftAt;

  /// Embedded profile when joined.
  final Profile? profile;

  /// Whether this member is still in the conversation.
  bool get isActive => leftAt == null;
}

/// A row of `public.messages`.
///
/// Send by **inserting** into `messages`; triggers then update the conversation
/// preview, bump every other member's unread count, and create notifications.
class MessageModel {
  /// Creates a message.
  const MessageModel({
    required this.id,
    required this.conversationId,
    this.authorId,
    this.body,
    this.kind = MessageKind.text,
    this.attachments = const <Map<String, dynamic>>[],
    this.sharedEntityType,
    this.sharedEntityId,
    this.replyToId,
    this.callId,
    this.editedAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
    this.author,
    this.isPending = false,
    this.failed = false,
  });

  /// Parses a `messages` row.
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final author = asMap(json['author'] ?? json['profiles']);
    return MessageModel(
      id: asString(json['id']),
      conversationId: asString(json['conversation_id']),
      authorId: asStringOrNull(json['author_id']),
      body: asStringOrNull(json['body']),
      kind: MessageKind.parse(json['kind']),
      attachments: asMapList(json['attachments']),
      sharedEntityType: EntityType.tryParse(json['shared_entity_type']),
      sharedEntityId: asStringOrNull(json['shared_entity_id']),
      replyToId: asStringOrNull(json['reply_to_id']),
      callId: asStringOrNull(json['call_id']),
      editedAt: asDateOrNull(json['edited_at']),
      deletedAt: asDateOrNull(json['deleted_at']),
      createdAt: asDateOrNull(json['created_at']),
      updatedAt: asDateOrNull(json['updated_at']),
      author: author.isEmpty ? null : Profile.fromJson(author),
    );
  }

  /// Primary key.
  final String id;

  /// Owning conversation.
  final String conversationId;

  /// Sender.
  final String? authorId;

  /// Text body.
  final String? body;

  /// text / image / system / call_event.
  final MessageKind kind;

  /// Attachment descriptors: `{storage_path, width, height, blurhash, ...}`.
  final List<Map<String, dynamic>> attachments;

  /// Type of a shared collection/subcollection/item, rendered as a rich card.
  final EntityType? sharedEntityType;

  /// Id of the shared entity.
  final String? sharedEntityId;

  /// The message this replies to.
  final String? replyToId;

  /// The call this event describes, for [MessageKind.callEvent].
  final String? callId;

  /// Set when edited.
  final DateTime? editedAt;

  /// Soft delete.
  final DateTime? deletedAt;

  /// Row creation time — the ordering key.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// Embedded author profile when joined.
  final Profile? author;

  /// Client-only: awaiting server acknowledgement.
  final bool isPending;

  /// Client-only: the insert failed; offer a retry.
  final bool failed;

  /// True when this message shares a KLECT entity.
  bool get hasSharedEntity =>
      sharedEntityType != null && sharedEntityId != null;

  /// Copy with overrides.
  MessageModel copyWith({
    String? id,
    String? body,
    bool? isPending,
    bool? failed,
    DateTime? createdAt,
    Profile? author,
  }) => MessageModel(
    id: id ?? this.id,
    conversationId: conversationId,
    authorId: authorId,
    body: body ?? this.body,
    kind: kind,
    attachments: attachments,
    sharedEntityType: sharedEntityType,
    sharedEntityId: sharedEntityId,
    replyToId: replyToId,
    callId: callId,
    editedAt: editedAt,
    deletedAt: deletedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt,
    author: author ?? this.author,
    isPending: isPending ?? this.isPending,
    failed: failed ?? this.failed,
  );
}

/// A row of `public.calls`.
class CallModel {
  /// Creates a call.
  const CallModel({
    required this.id,
    required this.conversationId,
    this.kind = CallKind.audio,
    this.status = CallStatus.ringing,
    this.createdBy,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.endReason,
    this.createdAt,
    this.participants = const <CallParticipant>[],
  });

  /// Parses a `calls` row.
  factory CallModel.fromJson(Map<String, dynamic> json) => CallModel(
    id: asString(json['id']),
    conversationId: asString(json['conversation_id']),
    kind: CallKind.parse(json['kind']),
    status: CallStatus.parse(json['status']),
    createdBy: asStringOrNull(json['created_by']),
    startedAt: asDateOrNull(json['started_at']),
    endedAt: asDateOrNull(json['ended_at']),
    durationSeconds: asIntOrNull(json['duration_seconds']),
    endReason: asStringOrNull(json['end_reason']),
    createdAt: asDateOrNull(json['created_at']),
    participants: <CallParticipant>[
      for (final p in asMapList(
        json['call_participants'] ?? json['participants'],
      ))
        CallParticipant.fromJson(p),
    ],
  );

  /// Primary key.
  final String id;

  /// The conversation the call belongs to.
  final String conversationId;

  /// Audio or video.
  final CallKind kind;

  /// Lifecycle state.
  final CallStatus status;

  /// Caller.
  final String? createdBy;

  /// When the call connected.
  final DateTime? startedAt;

  /// When it ended.
  final DateTime? endedAt;

  /// Recorded duration, written when the call ends.
  final int? durationSeconds;

  /// Why it ended.
  final String? endReason;

  /// Row creation time.
  final DateTime? createdAt;

  /// Participants when joined.
  final List<CallParticipant> participants;

  /// Whether the call is still ringing or connected.
  bool get isLive => status.isLive;

  /// `mm:ss` for the call log.
  String get formattedDuration {
    final total = durationSeconds ?? 0;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// A row of `public.call_participants`.
class CallParticipant {
  /// Creates a participant.
  const CallParticipant({
    required this.callId,
    required this.userId,
    this.joinedAt,
    this.leftAt,
    this.profile,
  });

  /// Parses a `call_participants` row.
  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    final profile = asMap(json['profile'] ?? json['profiles']);
    return CallParticipant(
      callId: asString(json['call_id']),
      userId: asString(json['user_id']),
      joinedAt: asDateOrNull(json['joined_at']),
      leftAt: asDateOrNull(json['left_at']),
      profile: profile.isEmpty ? null : Profile.fromJson(profile),
    );
  }

  /// Which call.
  final String callId;

  /// Which user.
  final String userId;

  /// When they joined the media session.
  final DateTime? joinedAt;

  /// When they left.
  final DateTime? leftAt;

  /// Embedded profile when joined.
  final Profile? profile;

  /// Whether they are still connected.
  bool get isConnected => joinedAt != null && leftAt == null;
}

/// A row of `public.call_signals` — the WebRTC signalling envelope carried
/// over Supabase Realtime.
class CallSignal {
  /// Creates a signal.
  const CallSignal({
    required this.id,
    required this.callId,
    required this.type,
    this.senderId,
    this.recipientId,
    this.payload = const <String, dynamic>{},
    this.createdAt,
  });

  /// Parses a `call_signals` row.
  factory CallSignal.fromJson(Map<String, dynamic> json) => CallSignal(
    id: asString(json['id']),
    callId: asString(json['call_id']),
    type: CallSignalType.parse(json['type']),
    senderId: asStringOrNull(json['sender_id']),
    recipientId: asStringOrNull(json['recipient_id']),
    payload: asMap(json['payload']),
    createdAt: asDateOrNull(json['created_at']),
  );

  /// Primary key.
  final String id;

  /// Which call.
  final String callId;

  /// offer / answer / ice / renegotiate / bye.
  final CallSignalType type;

  /// Who sent it.
  final String? senderId;

  /// Who it is addressed to.
  final String? recipientId;

  /// SDP or ICE payload.
  final Map<String, dynamic> payload;

  /// Row creation time — signals must be applied in order.
  final DateTime? createdAt;
}
