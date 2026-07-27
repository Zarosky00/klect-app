import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/ui/ui.dart';

import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  testWidgets('follow confirmation uses the collector name and premium copy', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(
          RecordingFeedbackDriver(),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-1',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();

    expect(find.text('You’re following Akash'), findsOneWidget);
    expect(
      find.text('Their new shelves and posts can now reach your Pulse.'),
      findsOneWidget,
    );
  });

  testWidgets('unfollow and failure copy are action-specific', (tester) async {
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(
          RecordingFeedbackDriver(),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-2',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: false,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();
    expect(find.text('Akash left your Pulse'), findsOneWidget);

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-3',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.failed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();
    expect(find.text('Couldn’t follow Akash'), findsOneWidget);
    expect(
      find.text('Nothing changed. Check your connection and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed likes do not create noisy success toasts', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(
          RecordingFeedbackDriver(),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'like-1',
            action: InteractionFeedbackAction.like,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'post:1',
            active: true,
          ),
        );
    await tester.pump();

    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.textContaining('Like'), findsNothing);
  });
}
