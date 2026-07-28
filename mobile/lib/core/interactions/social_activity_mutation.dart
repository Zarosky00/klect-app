import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entity_ref.dart';

/// Mutations that can change a mounted Pulse/Profile activity surface.
enum SocialActivityMutationKind {
  post,
  quote,
  repost,
  comment,
  like,
  save,
  delete,
}

/// A lightweight typed invalidation signal shared by optimistic controllers.
@immutable
class SocialActivityMutation {
  const SocialActivityMutation({
    required this.revision,
    required this.kind,
    this.entity,
    this.active,
  });

  final int revision;
  final SocialActivityMutationKind kind;
  final EntityRef? entity;
  final bool? active;
}

class SocialActivityMutationController
    extends Notifier<SocialActivityMutation?> {
  int _revision = 0;

  @override
  SocialActivityMutation? build() => null;

  /// Records an accepted local intent. Profile reads may refresh immediately;
  /// authoritative interaction controllers still reconcile counts separately.
  void record(
    SocialActivityMutationKind kind, {
    EntityRef? entity,
    bool? active,
  }) {
    state = SocialActivityMutation(
      revision: ++_revision,
      kind: kind,
      entity: entity,
      active: active,
    );
  }
}

final socialActivityMutationProvider =
    NotifierProvider<SocialActivityMutationController, SocialActivityMutation?>(
      SocialActivityMutationController.new,
      name: 'socialActivityMutation',
    );
