import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/ui/ui.dart';

import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  ProviderContainer harness(RecordingFeedbackDriver driver) =>
      ProviderContainer.test(
        overrides: [
          interactionFeedbackDriverProvider.overrideWithValue(driver),
          keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
      );

  testWidgets('follow confirmation is a wide avatar-backed top panel', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = harness(RecordingFeedbackDriver());
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
    await tester.pump(KDurations.medium);

    expect(
      find.text(
        'Following! Their new shelves and posts will appear in your Pulse.',
      ),
      findsOneWidget,
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('interaction-follow-panel')),
    );
    expect(rect.left, closeTo(Space.s4, 0.1));
    expect(rect.right, closeTo(360 - Space.s4, 0.1));
    expect(rect.top, closeTo(Space.s3, 0.1));
  });

  testWidgets('unfollow, queued and failed copy stay contextual', (
    tester,
  ) async {
    final container = harness(RecordingFeedbackDriver());
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
    );
    final controller = container.read(interactionFeedbackProvider.notifier);

    await controller.dispatch(
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
    expect(
      find.text(
        'Unfollowed. Their new activity will no longer appear in your Pulse.',
      ),
      findsOneWidget,
    );

    await controller.dispatch(
      const InteractionFeedbackEvent(
        id: 'follow-3',
        action: InteractionFeedbackAction.follow,
        result: InteractionFeedbackResult.queued,
        targetKey: 'akash-id',
        active: true,
        targetLabel: 'Akash',
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'Follow queued. We\u2019ll add their activity when you\u2019re back online.',
      ),
      findsOneWidget,
    );

    await controller.dispatch(
      const InteractionFeedbackEvent(
        id: 'follow-4',
        action: InteractionFeedbackAction.follow,
        result: InteractionFeedbackResult.failed,
        targetKey: 'akash-id',
        active: true,
        targetLabel: 'Akash',
      ),
    );
    await tester.pump();
    expect(
      find.text('Couldn\u2019t follow Akash. Nothing changed\u2014try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('interaction-follow-panel')),
      findsOneWidget,
    );
  });

  testWidgets('confirmed likes do not create noisy success notices', (
    tester,
  ) async {
    final container = harness(RecordingFeedbackDriver());
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

    expect(
      find.byKey(const ValueKey<String>('interaction-feedback-pill')),
      findsNothing,
    );
  });

  testWidgets('tapping the panel dismisses it with one native tap effect', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = harness(driver);
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-5',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('interaction-follow-panel')),
    );
    await tester.pumpAndSettle();

    expect(driver.taps, hasLength(1));
    expect(
      find.text(
        'Following! Their new shelves and posts will appear in your Pulse.',
      ),
      findsNothing,
    );
  });

  testWidgets('reduced motion keeps only the follow panel fade', (
    tester,
  ) async {
    final container = harness(RecordingFeedbackDriver());
    await pumpKlect(
      tester,
      const KInteractionFeedbackHost(child: SizedBox.expand()),
      container: container,
      disableAnimations: true,
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-reduced',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();

    final panel = find.byKey(
      const ValueKey<String>('interaction-follow-panel'),
    );
    expect(panel, findsOneWidget);
    expect(tester.getRect(panel).top, closeTo(Space.s3, 0.1));
  });
}
