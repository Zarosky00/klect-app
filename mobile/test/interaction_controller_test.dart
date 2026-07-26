import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/api_error.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/core/offline/action_queue.dart';
import 'package:klect/core/offline/queued_action.dart';
import 'package:klect/core/storage/key_value_store.dart';

import 'support/fake_api.dart';

void main() {
  const entity = EntityRef.item('cccccccc-0000-0000-0000-000000000001');

  ProviderContainer harness(FakeKlectApi api, InteractionState seed) {
    final container = ProviderContainer.test(
      overrides: [
        klectApiProvider.overrideWithValue(api),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    container.read(interactionSeedStoreProvider).put(entity, seed);
    return container;
  }

  group('InteractionController', () {
    test('seeds from the feed row instead of flashing zeros', () {
      final api = FakeKlectApi(liked: true, likeCount: 5);
      final container = harness(
        api,
        const InteractionState(liked: true, likeCount: 5, hydrated: true),
      );

      final state = container.read(interactionProvider(entity));
      expect(state.liked, isTrue);
      expect(state.likeCount, 5);
      expect(state.hydrated, isTrue);
      expect(api.likeCalls, 0);
    });

    test('a single like applies optimistically, then reconciles', () async {
      final api = FakeKlectApi(likeCount: 5);
      final container = harness(
        api,
        const InteractionState(likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      final pending = controller.toggleLike();

      // Before the RPC resolves, the UI already shows the user's intent.
      expect(container.read(interactionProvider(entity)).liked, isTrue);
      expect(container.read(interactionProvider(entity)).likeCount, 6);

      await pending;

      expect(container.read(interactionProvider(entity)).liked, isTrue);
      expect(container.read(interactionProvider(entity)).likeCount, 6);
      expect(api.likeCalls, 1);
      expect(api.serverLiked, isTrue);
      expect(api.serverLikeCount, 6);
    });

    test('10 rapid taps converge on the right state and count', () async {
      final api = FakeKlectApi(likeCount: 5);
      final container = harness(
        api,
        const InteractionState(likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      // Ten taps inside one frame — no awaits between them.
      final taps = <Future<void>>[
        for (var i = 0; i < 10; i++) controller.toggleLike(),
      ];
      await Future.wait(taps);

      final state = container.read(interactionProvider(entity));
      // Even number of taps: back where we started.
      expect(state.liked, isFalse);
      expect(state.likeCount, 5);

      // And the client and the server agree.
      expect(api.serverLiked, isFalse);
      expect(api.serverLikeCount, 5);

      // Coalesced: at most two round trips, never ten.
      expect(api.likeCalls, lessThanOrEqualTo(2));
      expect(api.likeCalls, greaterThan(0));
    });

    test('11 rapid taps end liked, with the count up by one', () async {
      final api = FakeKlectApi(likeCount: 5);
      final container = harness(
        api,
        const InteractionState(likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      await Future.wait(<Future<void>>[
        for (var i = 0; i < 11; i++) controller.toggleLike(),
      ]);

      final state = container.read(interactionProvider(entity));
      expect(state.liked, isTrue);
      expect(state.likeCount, 6);
      expect(api.serverLiked, isTrue);
      expect(api.serverLikeCount, 6);
      expect(api.likeCalls, lessThanOrEqualTo(2));
    });

    test('save and repost coalesce independently of like', () async {
      final api = FakeKlectApi(likeCount: 5, saveCount: 2, repostCount: 0);
      final container = harness(
        api,
        const InteractionState(
          likeCount: 5,
          saveCount: 2,
          repostCount: 0,
          hydrated: true,
        ),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      await Future.wait(<Future<void>>[
        controller.toggleLike(),
        controller.toggleSave(),
        controller.toggleRepost(),
      ]);

      final state = container.read(interactionProvider(entity));
      expect(state.liked, isTrue);
      expect(state.likeCount, 6);
      expect(state.saved, isTrue);
      expect(state.saveCount, 3);
      expect(state.reposted, isTrue);
      expect(state.repostCount, 1);
      expect(api.likeCalls, 1);
      expect(api.saveCalls, 1);
      expect(api.repostCalls, 1);
    });

    test('a permanent failure rolls the delta back and surfaces the error',
        () async {
      final api = FakeKlectApi(likeCount: 5)
        ..failWith = const KlectError(
          KlectErrorKind.forbidden,
          'You can no longer interact with this.',
          code: '42501',
        );
      final container = harness(
        api,
        const InteractionState(likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      await controller.toggleLike();

      final state = container.read(interactionProvider(entity));
      expect(state.liked, isFalse, reason: 'rolled back');
      expect(state.likeCount, 5, reason: 'rolled back');
      expect(state.error?.kind, KlectErrorKind.forbidden);
    });

    test('a transport failure keeps the intent and queues it for replay',
        () async {
      final api = FakeKlectApi(likeCount: 5)
        ..failWith = const KlectError(
          KlectErrorKind.network,
          'You appear to be offline.',
        );
      final container = harness(
        api,
        const InteractionState(likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      await controller.toggleLike();

      final state = container.read(interactionProvider(entity));
      expect(state.liked, isTrue, reason: 'the intent stays on screen');
      expect(state.likeCount, 6);
      expect(state.error, isNull, reason: 'offline is not an error state here');

      final queue = container.read(offlineQueueProvider);
      expect(queue.length, 1);
      expect(queue.pending.single.kind, QueuedActionKind.like);
      expect(queue.pending.single.desiredActive, isTrue);
    });

    test('realtime counters merge without clobbering the viewer flags', () {
      final api = FakeKlectApi(liked: true, likeCount: 5);
      final container = harness(
        api,
        const InteractionState(liked: true, likeCount: 5, hydrated: true),
      );
      final controller = container.read(interactionProvider(entity).notifier);

      controller.mergeCounters(<String, dynamic>{
        'like_count': 41,
        'save_count': 9,
        'comment_count': 3,
        'view_count': 900,
      });

      final state = container.read(interactionProvider(entity));
      expect(state.likeCount, 41);
      expect(state.saveCount, 9);
      expect(state.commentCount, 3);
      expect(state.viewCount, 900);
      expect(state.liked, isTrue, reason: 'not present in the row payload');
    });
  });

  group('OfflineActionQueue', () {
    test('collapses repeated intents for the same entity to one row', () async {
      final api = FakeKlectApi(likeCount: 0);
      final store = MemoryKeyValueStore();
      final queue = OfflineActionQueue(api: api, store: store);
      addTearDown(queue.dispose);

      for (var i = 0; i < 10; i++) {
        await queue.enqueueToggle(
          kind: QueuedActionKind.like,
          entityType: EntityType.item,
          entityId: 'abc',
          desiredActive: i.isEven,
        );
      }

      expect(queue.length, 1);
      expect(queue.pending.single.desiredActive, isFalse);
    });

    test('replay converges instead of blindly re-toggling', () async {
      // Server already reflects the desired state: replay must be a no-op.
      final api = FakeKlectApi(liked: true, likeCount: 1);
      final queue = OfflineActionQueue(
        api: api,
        store: MemoryKeyValueStore(),
      );
      addTearDown(queue.dispose);

      await queue.enqueueToggle(
        kind: QueuedActionKind.like,
        entityType: EntityType.item,
        entityId: 'abc',
        desiredActive: true,
      );
      await queue.flush();

      expect(api.likeCalls, 0, reason: 'already in the desired state');
      expect(queue.isEmpty, isTrue);
      expect(api.serverLikeCount, 1, reason: 'the count was not corrupted');
    });

    test('replay applies the toggle when the server disagrees', () async {
      final api = FakeKlectApi(likeCount: 0);
      final queue = OfflineActionQueue(
        api: api,
        store: MemoryKeyValueStore(),
      );
      addTearDown(queue.dispose);

      await queue.enqueueToggle(
        kind: QueuedActionKind.like,
        entityType: EntityType.item,
        entityId: 'abc',
        desiredActive: true,
      );
      await queue.flush();

      expect(api.likeCalls, 1);
      expect(api.serverLiked, isTrue);
      expect(api.serverLikeCount, 1);
      expect(queue.isEmpty, isTrue);
    });

    test('survives a cold start', () async {
      final store = MemoryKeyValueStore();
      final first = OfflineActionQueue(
        api: FakeKlectApi(),
        store: store,
      );
      await first.enqueueToggle(
        kind: QueuedActionKind.save,
        entityType: EntityType.collection,
        entityId: 'xyz',
        desiredActive: true,
      );
      first.dispose();

      final api = FakeKlectApi();
      final second = OfflineActionQueue(api: api, store: store);
      addTearDown(second.dispose);
      await second.restore();

      expect(second.length, 1);
      expect(second.pending.single.entityType, EntityType.collection);

      await second.flush();
      expect(api.saveCalls, 1);
    });
  });
}
