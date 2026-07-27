import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/ui/ui.dart';

import 'support/recording_feedback_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final sans = FontLoader('Instrument Sans')
      ..addFont(rootBundle.load('assets/fonts/InstrumentSans[wdth,wght].ttf'));
    final display = FontLoader('Fraunces')
      ..addFont(
        rootBundle.load('assets/fonts/Fraunces[SOFT,WONK,opsz,wght].ttf'),
      );
    await Future.wait(<Future<void>>[sans.load(), display.load()]);
  });

  testWidgets('Pinterest-style follow panel at reference phone width', (
    tester,
  ) async {
    const viewport = Size(358, 800);
    tester.view
      ..physicalSize = viewport
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(
          RecordingFeedbackDriver(),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: KlectThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: viewport,
              padding: EdgeInsets.only(top: 44),
              viewPadding: EdgeInsets.only(top: 44),
            ),
            child: Scaffold(
              body: KInteractionFeedbackHost(
                child: ColoredBox(color: (const KlectColorsDark()).bgBase),
              ),
            ),
          ),
        ),
      ),
    );

    await container
        .read(interactionFeedbackProvider.notifier)
        .dispatch(
          const InteractionFeedbackEvent(
            id: 'follow-golden',
            action: InteractionFeedbackAction.follow,
            result: InteractionFeedbackResult.confirmed,
            targetKey: 'akash-id',
            active: true,
            targetLabel: 'Akash',
          ),
        );
    await tester.pump();
    await tester.pump(KDurations.medium);

    await expectLater(
      find.byType(KInteractionFeedbackHost),
      matchesGoldenFile('goldens/follow_panel_358x800.png'),
    );
  });
}
