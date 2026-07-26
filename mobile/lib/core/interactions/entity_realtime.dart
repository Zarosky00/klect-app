import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/klect_api.dart';
import 'entity_ref.dart';
import 'interaction_controller.dart';

/// Live counters for one entity.
///
/// Per `docs/BACKEND_API.md` §3 we subscribe to `UPDATE` on the **entity row**,
/// never to `likes`: one event carries every fresh counter at once and RLS is
/// honoured on the stream.
///
/// Watch it from any widget that wants counts to move while it is on screen:
///
/// ```dart
/// ref.watch(entityLiveCountersProvider(entity));           // subscribes
/// final counts = ref.watch(interactionProvider(entity));   // renders
/// ```
///
/// The subscription is torn down automatically when the last watcher goes away.
final entityLiveCountersProvider =
    Provider.autoDispose.family<RealtimeChannel, EntityRef>(
  (ref, entity) {
    final api = ref.watch(klectApiProvider);
    final controller = ref.read(interactionProvider(entity).notifier);

    final channel = api.entityCounterChannel(
      type: entity.type,
      id: entity.id,
      onRow: controller.mergeCounters,
    );

    channel.subscribe();
    ref.onDispose(() {
      unawaited(api.removeChannel(channel));
    });
    return channel;
  },
  name: 'entityLiveCounters',
);

/// Subscribes to several entities at once — one channel per entity, all torn
/// down together. Useful for a closeup that shows an item plus its siblings.
final entityLiveCountersGroupProvider =
    Provider.autoDispose.family<void, List<EntityRef>>(
  (ref, entities) {
    for (final entity in entities) {
      ref.watch(entityLiveCountersProvider(entity));
    }
  },
  name: 'entityLiveCountersGroup',
);
