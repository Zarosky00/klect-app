import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/features/pulse/widgets/comment_action_bar.dart';

import 'support/fake_api.dart';
import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  testWidgets('reply and comment like use the same immediate tap feedback', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        klectApiProvider.overrideWithValue(FakeKlectApi()),
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore(<String, String>{
            AppSettingsController.hapticsKey: 'true',
          }),
        ),
      ],
    );
    var replies = 0;
    await pumpKlect(
      tester,
      CommentActionBar(
        comment: const CommentModel(
          id: 'comment-1',
          body: 'A comment',
          entityType: EntityType.post,
          entityId: 'post-1',
          replyCount: 2,
        ),
        onReply: () => replies++,
      ),
      container: container,
    );

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pumpAndSettle();
    expect(replies, 1);
    expect(driver.taps, hasLength(1));

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(driver.taps, hasLength(2));
    expect(driver.taps.every((tap) => tap.sound && tap.haptic), isTrue);
  });
}
