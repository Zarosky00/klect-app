import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/storage/key_value_store.dart';
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

  testWidgets(
    'enabled app controls respond once and disabled controls do not',
    (tester) async {
      final driver = RecordingFeedbackDriver();
      var accepted = 0;
      await pumpKlect(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            KButton(label: 'Enabled', onPressed: () => accepted++),
            const KButton(label: 'Disabled'),
          ],
        ),
        container: harness(driver),
      );

      await tester.tap(find.text('Enabled'));
      await tester.pump();
      expect(accepted, 1);
      expect(driver.taps, hasLength(1));

      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(accepted, 1);
      expect(driver.taps, hasLength(1));
    },
  );

  testWidgets('nested pressables do not duplicate one accepted callback', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    var inner = 0;
    var outer = 0;
    await pumpKlect(
      tester,
      KPressable(
        onTap: () => outer++,
        child: KPressable(
          onTap: () => inner++,
          child: const SizedBox(
            width: 100,
            height: 100,
            child: Center(child: Text('Inner')),
          ),
        ),
      ),
      container: harness(driver),
    );

    await tester.tap(find.text('Inner'));
    await tester.pump();

    expect(inner + outer, 1);
    expect(driver.taps, hasLength(1));
  });

  testWidgets('visible app back responds but system back remains silent', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    await pumpKlect(tester, const _BackHarness(), container: harness(driver));

    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    driver.taps.clear();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(driver.taps, hasLength(1));
    expect(find.text('Open detail'), findsOneWidget);

    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    driver.taps.clear();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(driver.taps, isEmpty);
    expect(find.text('Open detail'), findsOneWidget);
  });

  testWidgets('collapsing app bar replaces the automatic back control', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    await pumpKlect(
      tester,
      const _SliverBackHarness(),
      container: harness(driver),
    );

    await tester.tap(find.text('Open sliver detail'));
    await tester.pumpAndSettle();
    driver.taps.clear();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(driver.taps, hasLength(1));
    expect(find.text('Open sliver detail'), findsOneWidget);
  });
}

class _BackHarness extends StatelessWidget {
  const _BackHarness();

  @override
  Widget build(BuildContext context) => KButton(
    label: 'Open detail',
    onPressed: () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const KScaffold(
          appBar: KFixedAppBar(title: 'Detail', showBack: true),
          body: SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _SliverBackHarness extends StatelessWidget {
  const _SliverBackHarness();

  @override
  Widget build(BuildContext context) => KButton(
    label: 'Open sliver detail',
    onPressed: () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              KAppBar(title: 'Sliver detail'),
              SliverFillRemaining(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    ),
  );
}
