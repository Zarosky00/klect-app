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

  testWidgets('follow confirmation is a concise top-right status pill', (
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
            id: 'follow-1',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();
    await tester.pump(KDurations.base);

    expect(find.text('Following Akash'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.textContaining('new shelves'), findsNothing);

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('interaction-feedback-pill')),
    );
    expect(
      rect.right,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio -
            Space.s3,
        0.1,
      ),
    );
    expect(rect.top, greaterThanOrEqualTo(Layout.topBarHeight));
  });

  testWidgets('unfollow, queued and failed copy stay contextual and short', (
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
    expect(find.text('Unfollowed Akash'), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

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
    expect(find.text('Follow queued \u00b7 Akash'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

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
    expect(find.text('Couldn\u2019t follow Akash'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
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

  testWidgets('tapping the pill dismisses it with one native tap effect', (
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
      find.byKey(const ValueKey<String>('interaction-feedback-pill')),
    );
    await tester.pumpAndSettle();

    expect(driver.taps, hasLength(1));
    expect(find.text('Following Akash'), findsNothing);
  });
}
