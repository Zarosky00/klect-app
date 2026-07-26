import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// The polymorphic key `(entity_type, entity_id)`.
///
/// This is what the interaction engine is keyed by, so one code path serves
/// likes on a collection, a subcollection, an item, a post or a comment.
@immutable
class EntityRef {
  /// Creates a reference.
  const EntityRef(this.type, this.id);

  /// A collection.
  const EntityRef.collection(this.id) : type = EntityType.collection;

  /// A subcollection.
  const EntityRef.subcollection(this.id) : type = EntityType.subcollection;

  /// An item.
  const EntityRef.item(this.id) : type = EntityType.item;

  /// A post.
  const EntityRef.post(this.id) : type = EntityType.post;

  /// A comment.
  const EntityRef.comment(this.id) : type = EntityType.comment;

  /// Builds a reference from a surf card.
  factory EntityRef.ofCard(SurfCard card) =>
      EntityRef(card.entityType, card.entityId);

  /// Builds a reference from a closeup payload.
  factory EntityRef.ofCloseup(Closeup closeup) =>
      EntityRef(closeup.entityType, closeup.entityId);

  /// Parses `"item:uuid"`.
  static EntityRef? tryParse(String value) {
    final index = value.indexOf(':');
    if (index <= 0) return null;
    final type = EntityType.tryParse(value.substring(0, index));
    final id = value.substring(index + 1);
    if (type == null || id.isEmpty) return null;
    return EntityRef(type, id);
  }

  /// Which of the five entity types.
  final EntityType type;

  /// The entity's uuid.
  final String id;

  /// `"item:uuid"` — stable across rebuilds, safe as a map key or route param.
  String get key => '${type.wire}:$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'EntityRef($key)';
}
