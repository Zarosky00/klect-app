import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/pulse/widgets/pulse_composer.dart';

void main() {
  testWidgets('composer keeps media and submit actions visible', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: MaterialApp(
          theme: KlectThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => PulseComposer.show(context),
                  child: const Text('Open composer'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('pulse-add-photos')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('pulse-submit')), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
  });
}
