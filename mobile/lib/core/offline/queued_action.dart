import '../models/models.dart';

/// The action kinds the offline queue is allowed to replay.
///
/// Only **convergent** actions qualify: replaying one can be made to end in the
/// desired state no matter how many times it runs. Comments are deliberately
/// absent — replaying an insert would duplicate it, so a failed comment
/// restores the draft in the composer instead.
enum QueuedActionKind {
  /// `toggle_like`.
  like,

  /// `toggle_save`.
  save,

  /// `toggle_repost`.
  repost,

  /// `toggle_follow`.
  follow,

  /// `record_view` — already deduped per viewer per day server-side.
  view,
}

/// One durable intent: "this user wants entity X to end up liked".
///
/// The queue stores the **desired end state**, not the transition. On replay we
/// read the current server state and only call the RPC if they differ — which
/// is what makes replay safe after a retry, a crash, or a duplicate enqueue.
class QueuedAction {
  /// Creates an action.
  const QueuedAction({
    required this.id,
    required this.kind,
    required this.targetId,
    this.entityType,
    this.desiredActive = true,
    this.note,
    this.quote,
    required this.createdAt,
    this.attempts = 0,
  });

  /// Rebuilds an action from its persisted form.
  factory QueuedAction.fromJson(Map<String, dynamic> json) => QueuedAction(
        id: asString(json['id']),
        kind: QueuedActionKind.values.firstWhere(
          (k) => k.name == asString(json['kind']),
          orElse: () => QueuedActionKind.like,
        ),
        targetId: asString(json['target_id']),
        entityType: EntityType.tryParse(json['entity_type']),
        desiredActive: asBool(json['desired_active'], fallback: true),
        note: asStringOrNull(json['note']),
        quote: asStringOrNull(json['quote']),
        createdAt: asDate(json['created_at']),
        attempts: asInt(json['attempts']),
      );

  /// Client-side uuid.
  final String id;

  /// Which RPC this replays.
  final QueuedActionKind kind;

  /// The entity id, or the target user id for [QueuedActionKind.follow].
  final String targetId;

  /// The entity type. Null for [QueuedActionKind.follow].
  final EntityType? entityType;

  /// The state the user wants to end in.
  final bool desiredActive;

  /// Optional save note.
  final String? note;

  /// Optional repost quote.
  final String? quote;

  /// When the user performed the action.
  final DateTime createdAt;

  /// How many replay attempts have been made.
  final int attempts;

  /// Two actions with the same key are the same intent: the newer one wins,
  /// so tapping like 10 times offline leaves exactly one queued entry.
  String get dedupeKey =>
      '${kind.name}:${entityType?.wire ?? 'user'}:$targetId';

  /// Persisted form.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'target_id': targetId,
        'entity_type': entityType?.wire,
        'desired_active': desiredActive,
        'note': note,
        'quote': quote,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
      };

  /// Copy with a bumped attempt counter.
  QueuedAction retried() => QueuedAction(
        id: id,
        kind: kind,
        targetId: targetId,
        entityType: entityType,
        desiredActive: desiredActive,
        note: note,
        quote: quote,
        createdAt: createdAt,
        attempts: attempts + 1,
      );
}
