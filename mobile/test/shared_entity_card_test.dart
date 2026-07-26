import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/chat/chat_api.dart';
import 'package:klect/features/chat/chat_models.dart';
import 'package:klect/features/chat/thread_controller.dart';
import 'package:klect/features/chat/widgets/message_bubble.dart';
import 'package:klect/features/chat/widgets/shared_entity_card.dart';

import 'support/test_harness.dart';

/// Only what the shared-entity card actually touches offline: [publicUrl].
/// Everything else throwing keeps the test honest about what renders.
class _FakeChatApi extends Fake implements ChatApi {
  @override
  String? publicUrl(
    String? path, {
    StorageBucket bucket = StorageBucket.media,
  }) => null;
}

/// A text message carrying a shared entity — the exact shape a thread renders.
ChatMessage _sharedEntityMessage() => ChatMessage(
  message: MessageModel(
    id: 'msg-1',
    conversationId: 'conv-1',
    authorId: 'me',
    sharedEntityType: EntityType.item,
    sharedEntityId: 'item-1',
    createdAt: DateTime(2026, 7, 27, 12),
  ),
);

/// The harness's MediaQuery reports a zero size; the bubble sizes its card
/// from `MediaQuery.sizeOf`, so give it a phone's worth of width.
Widget _phoneSized(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(390, 844)),
  child: child,
);

void main() {
  setUpAll(useOfflineFonts);

  group('SharedEntityCard inside a ListView', () {
    testWidgets(
      'renders the resolved preview without unbounded-height errors',
      (tester) async {
        final container = ProviderContainer.test(
          overrides: [
            chatApiProvider.overrideWithValue(_FakeChatApi()),
            sharedEntityPreviewProvider.overrideWith(
              (ref, key) async => const SharedEntityPreview(
                entityType: EntityType.item,
                entityId: 'item-1',
                title: 'Gojo — Vol.11 cover',
                subtitle: 'Shueisha',
              ),
            ),
          ],
        );

        await pumpKlect(
          tester,
          _phoneSized(
            ListView(
              children: <Widget>[
                MessageBubble(message: _sharedEntityMessage(), isMine: true),
              ],
            ),
          ),
          container: container,
        );
        await tester.pump();

        // The stretch bug made this exact layout throw ("BoxConstraints forces
        // an infinite height") — a ListView item has no height to stretch into.
        expect(tester.takeException(), isNull);
        expect(find.byType(SharedEntityCard), findsOneWidget);
        expect(find.text('Gojo — Vol.11 cover'), findsOneWidget);
        expect(find.text('Shueisha'), findsOneWidget);
        expect(find.text('ITEM'), findsOneWidget);

        // The card must size itself to its content, not the viewport.
        final size = tester.getSize(find.byType(SharedEntityCard));
        expect(size.height, lessThan(200));
      },
    );

    testWidgets('the loading skeleton lays out in unbounded height too', (
      tester,
    ) async {
      final never = Completer<SharedEntityPreview?>();
      final container = ProviderContainer.test(
        overrides: [
          chatApiProvider.overrideWithValue(_FakeChatApi()),
          sharedEntityPreviewProvider.overrideWith((ref, key) => never.future),
        ],
      );

      await pumpKlect(
        tester,
        _phoneSized(
          ListView(
            children: <Widget>[
              MessageBubble(message: _sharedEntityMessage(), isMine: false),
            ],
          ),
        ),
        container: container,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SharedEntityCard), findsOneWidget);
    });

    testWidgets('a vanished entity renders the missing row, not an error', (
      tester,
    ) async {
      final container = ProviderContainer.test(
        overrides: [
          chatApiProvider.overrideWithValue(_FakeChatApi()),
          sharedEntityPreviewProvider.overrideWith((ref, key) async => null),
        ],
      );

      await pumpKlect(
        tester,
        ListView(
          children: const <Widget>[
            SharedEntityCard(
              entityType: EntityType.collection,
              entityId: 'gone',
            ),
          ],
        ),
        container: container,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('no longer available'), findsOneWidget);
    });
  });

  // Guards the fetchEntityPreview post branch's card contract: a shared post
  // renders its body excerpt, its author and the POST eyebrow.
  testWidgets('a shared post renders body excerpt + author', (tester) async {
    final container = ProviderContainer.test(
      overrides: [
        chatApiProvider.overrideWithValue(_FakeChatApi()),
        sharedEntityPreviewProvider.overrideWith(
          (ref, key) async => const SharedEntityPreview(
            entityType: EntityType.post,
            entityId: 'post-1',
            title: 'Shelf day. New resin grail landed.',
            subtitle: 'by Aria Vale',
          ),
        ),
      ],
    );

    await pumpKlect(
      tester,
      ListView(
        children: const <Widget>[
          SharedEntityCard(entityType: EntityType.post, entityId: 'post-1'),
        ],
      ),
      container: container,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('Shelf day. New resin grail landed.'), findsOneWidget);
    expect(find.text('by Aria Vale'), findsOneWidget);
  });
}
