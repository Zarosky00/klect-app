/// Wire enums. Every value here mirrors a Postgres enum on `new_klect`
/// (verified against the live database, see `docs/BACKEND_API.md`).
library;

/// `entity_type` — the polymorphic key used by every social table.
enum EntityType {
  /// Top-level shelf a user owns, e.g. "Anime".
  collection('collection', 'collections'),

  /// Themed group inside a collection, e.g. "JJK".
  subcollection('subcollection', 'subcollections'),

  /// A thing, with 1..n photos.
  item('item', 'items'),

  /// A Pulse post.
  post('post', 'posts'),

  /// A comment — likeable in its own right.
  comment('comment', 'comments');

  const EntityType(this.wire, this.table);

  /// The value Postgres expects for `p_type` / `entity_type`.
  final String wire;

  /// The table whose row carries this entity's counter columns. Realtime
  /// counter subscriptions listen to `UPDATE` on this table.
  final String table;

  /// Parses a wire value; returns `null` when unrecognised.
  static EntityType? tryParse(Object? value) {
    if (value is EntityType) return value;
    final s = value?.toString();
    for (final e in EntityType.values) {
      if (e.wire == s) return e;
    }
    return null;
  }

  /// Parses a wire value, defaulting to [EntityType.item].
  static EntityType parse(Object? value) => tryParse(value) ?? EntityType.item;
}

/// `report_reason` — the exact set accepted by `submit_report`.
enum ReportReason {
  /// Unsolicited or repetitive commercial content.
  spam('spam', 'Spam'),

  /// Adult or sexually explicit imagery.
  nudity('nudity', 'Nudity or sexual content'),

  /// Targeted abuse or bullying.
  harassment('harassment', 'Harassment or bullying'),

  /// Hate speech against a protected group.
  hate('hate', 'Hate speech'),

  /// Graphic violence or threats.
  violence('violence', 'Violence or threats'),

  /// Self-harm or suicide content.
  selfHarm('self_harm', 'Self-harm or suicide'),

  /// Copyright or trademark infringement.
  ipViolation('ip_violation', 'Intellectual property'),

  /// False or misleading information.
  misinformation('misinformation', 'Misinformation'),

  /// Pretending to be someone else.
  impersonation('impersonation', 'Impersonation'),

  /// Anything else — the free-text path.
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);

  /// The value Postgres expects for `p_reason`.
  final String wire;

  /// Human label shown in the report sheet.
  final String label;

  /// Parses a wire value, defaulting to [ReportReason.other].
  static ReportReason parse(Object? value) {
    final s = value?.toString();
    for (final r in ReportReason.values) {
      if (r.wire == s) return r;
    }
    return ReportReason.other;
  }
}

/// `visibility` — inherits **down** the hierarchy when null.
enum EntityVisibility {
  /// Anyone, including logged-out visitors and search engines.
  public('public', 'Public'),

  /// Only accounts that follow the owner.
  followers('followers', 'Followers'),

  /// Only the owner.
  private('private', 'Only me');

  const EntityVisibility(this.wire, this.label);

  /// The value Postgres expects.
  final String wire;

  /// Human label for pickers.
  final String label;

  /// Parses a wire value; `null` means "inherit from the parent".
  static EntityVisibility? tryParse(Object? value) {
    final s = value?.toString();
    for (final v in EntityVisibility.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// `profiles.account_visibility`.
enum AccountVisibility {
  /// Profile and public content visible to everyone.
  public('public', 'Public'),

  /// Content limited to followers.
  followers('followers', 'Followers only'),

  /// Content limited to the owner.
  private('private', 'Private');

  const AccountVisibility(this.wire, this.label);

  /// The value Postgres expects.
  final String wire;

  /// Human label for the privacy screen.
  final String label;

  /// Parses a wire value, defaulting to [AccountVisibility.public].
  static AccountVisibility parse(Object? value) {
    final s = value?.toString();
    for (final v in AccountVisibility.values) {
      if (v.wire == s) return v;
    }
    return AccountVisibility.public;
  }
}

/// `profiles.allow_messages_from` — enforced server-side by `start_dm`.
enum AllowMessagesFrom {
  /// Anyone may open a DM.
  everyone('everyone', 'Everyone'),

  /// Only people the user follows.
  following('following', 'People I follow'),

  /// Only taste matches.
  matches('matches', 'My matches'),

  /// Only people who follow each other.
  mutual('mutual', 'Mutual follows'),

  /// Nobody.
  nobody('nobody', 'No one');

  const AllowMessagesFrom(this.wire, this.label);

  /// The value Postgres expects.
  final String wire;

  /// Human label for the privacy screen.
  final String label;

  /// Parses a wire value, defaulting to [AllowMessagesFrom.everyone].
  static AllowMessagesFrom parse(Object? value) {
    final s = value?.toString();
    for (final v in AllowMessagesFrom.values) {
      if (v.wire == s) return v;
    }
    return AllowMessagesFrom.everyone;
  }
}

/// `notification_type`.
enum NotificationType {
  /// Someone liked one of your entities.
  like('like'),

  /// Someone saved one of your entities.
  save('save'),

  /// Someone reposted one of your entities.
  repost('repost'),

  /// Someone commented on one of your entities.
  comment('comment'),

  /// Someone replied to your comment.
  reply('reply'),

  /// Someone followed you.
  follow('follow'),

  /// Someone mentioned you.
  mention('mention'),

  /// A new direct message.
  message('message'),

  /// An incoming or missed call.
  call('call'),

  /// A new taste match.
  match('match'),

  /// Product/system notice.
  system('system');

  const NotificationType(this.wire);

  /// The value Postgres emits.
  final String wire;

  /// Parses a wire value, defaulting to [NotificationType.system].
  static NotificationType parse(Object? value) {
    final s = value?.toString();
    for (final t in NotificationType.values) {
      if (t.wire == s) return t;
    }
    return NotificationType.system;
  }
}

/// `post_kind`.
enum PostKind {
  /// An original post.
  post('post'),

  /// A repost carrying commentary.
  quote('quote'),

  /// A reply to another post.
  reply('reply');

  const PostKind(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Parses a wire value, defaulting to [PostKind.post].
  static PostKind parse(Object? value) {
    final s = value?.toString();
    for (final k in PostKind.values) {
      if (k.wire == s) return k;
    }
    return PostKind.post;
  }
}

/// `conversation_kind`.
enum ConversationKind {
  /// One-to-one. `start_dm` guarantees exactly one per pair, ever.
  dm('dm'),

  /// Three or more members.
  group('group');

  const ConversationKind(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Parses a wire value, defaulting to [ConversationKind.dm].
  static ConversationKind parse(Object? value) {
    final s = value?.toString();
    for (final k in ConversationKind.values) {
      if (k.wire == s) return k;
    }
    return ConversationKind.dm;
  }
}

/// `message_kind`. A "shared entity" message is a `text` message that also
/// carries `shared_entity_type` / `shared_entity_id`.
enum MessageKind {
  /// Plain text (optionally with a shared entity attached).
  text('text'),

  /// One or more images in `attachments`.
  image('image'),

  /// Generated by the server (member joined, etc).
  system('system'),

  /// A call started/ended/missed marker, linked by `call_id`.
  callEvent('call_event');

  const MessageKind(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Parses a wire value, defaulting to [MessageKind.text].
  static MessageKind parse(Object? value) {
    final s = value?.toString();
    for (final k in MessageKind.values) {
      if (k.wire == s) return k;
    }
    return MessageKind.text;
  }
}

/// `call_kind`.
enum CallKind {
  /// Voice only.
  audio('audio'),

  /// Voice + camera.
  video('video');

  const CallKind(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Parses a wire value, defaulting to [CallKind.audio].
  static CallKind parse(Object? value) {
    final s = value?.toString();
    for (final k in CallKind.values) {
      if (k.wire == s) return k;
    }
    return CallKind.audio;
  }
}

/// `call_status`.
enum CallStatus {
  /// Created, waiting for an answer.
  ringing('ringing'),

  /// Connected.
  active('active'),

  /// Hung up normally.
  ended('ended'),

  /// Nobody answered.
  missed('missed'),

  /// Explicitly rejected.
  declined('declined'),

  /// Signalling or media failed.
  failed('failed');

  const CallStatus(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Whether the call is still live.
  bool get isLive => this == ringing || this == active;

  /// Parses a wire value, defaulting to [CallStatus.ended].
  static CallStatus parse(Object? value) {
    final s = value?.toString();
    for (final k in CallStatus.values) {
      if (k.wire == s) return k;
    }
    return CallStatus.ended;
  }
}

/// `call_signals.type` — the WebRTC signalling envelope.
enum CallSignalType {
  /// SDP offer.
  offer('offer'),

  /// SDP answer.
  answer('answer'),

  /// ICE candidate.
  ice('ice'),

  /// Renegotiation request (e.g. camera turned on mid-call).
  renegotiate('renegotiate'),

  /// Hang up.
  bye('bye');

  const CallSignalType(this.wire);

  /// The value Postgres expects.
  final String wire;

  /// Parses a wire value, defaulting to [CallSignalType.ice].
  static CallSignalType parse(Object? value) {
    final s = value?.toString();
    for (final k in CallSignalType.values) {
      if (k.wire == s) return k;
    }
    return CallSignalType.ice;
  }
}

/// `pulse_feed(p_mode)` — which half of the Pulse stream to serve.
enum PulseMode {
  /// Ranked discovery: engagement with time-decay, taste match, follow bonus.
  foryou('foryou', 'For you'),

  /// Chronological posts + reposts from people you follow. The default.
  following('following', 'Following');

  const PulseMode(this.wire, this.label);

  /// The value Postgres expects for `p_mode`.
  final String wire;

  /// Human label for the segmented control.
  final String label;
}

/// How a comment thread is ordered. Client-side for the closeup's table
/// reads (`fetchComments` turns it into `order()` calls) and the wire value
/// of `get_post_thread(p_sort)` for the post thread (0021).
enum CommentSort {
  /// Most-liked first, ties oldest-first — X's "Top".
  top('Top', 'top'),

  /// Newest first.
  newest('Newest', 'new');

  const CommentSort(this.label, this.wire);

  /// Human label for the sort toggle.
  final String label;

  /// The value `get_post_thread` expects for `p_sort`.
  final String wire;
}

/// `surf_feed(p_filter)`.
enum SurfFilter {
  /// Everything the ranker surfaces.
  all('all', 'All'),

  /// Only accounts you follow.
  following('following', 'Following'),

  /// Only items.
  items('items', 'Items'),

  /// Only collections and subcollections.
  collections('collections', 'Collections');

  const SurfFilter(this.wire, this.label);

  /// The value Postgres expects for `p_filter`.
  final String wire;

  /// Human label for the filter chips.
  final String label;
}

/// Storage buckets, with the size ceiling the bucket enforces.
enum StorageBucket {
  /// Public avatars — `{user_id}/{uuid}.webp`.
  avatars('avatars', 5),

  /// Public profile banners — `{user_id}/{uuid}.webp`.
  banners('banners', 10),

  /// Public item media — `{user_id}/{item_id}/{uuid}.webp`.
  media('media', 25),

  /// Private chat attachments — `{user_id}/{conversation_id}/{uuid}.webp`.
  chat('chat', 25);

  const StorageBucket(this.id, this.limitMb);

  /// The bucket name.
  final String id;

  /// Upload ceiling in megabytes, as configured server-side.
  final int limitMb;

  /// Whether objects are readable without a signed URL.
  bool get isPublic => this != StorageBucket.chat;

  /// Looks a bucket up by name.
  static StorageBucket? tryParse(String? name) {
    for (final b in StorageBucket.values) {
      if (b.id == name) return b;
    }
    return null;
  }
}
