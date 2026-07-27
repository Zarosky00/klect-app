import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/auth/auth_controller.dart';
import 'package:klect/features/pulse/widgets/pulse_composer.dart';

void main() {
  testWidgets('composer keeps media and submit actions visible', (
    tester,
  ) async {
    await _pumpComposer(tester);

    expect(
      find.byKey(const ValueKey<String>('pulse-add-photos')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('pulse-submit')), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
  });

  testWidgets(
    'small keyboard viewport keeps header, caret and toolbar visible',
    (tester) async {
      await _pumpComposer(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(
        find.byKey(const ValueKey<String>('pulse-composer-text')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('pulse-composer-text')),
        'A visible draft',
      );
      await tester.pump();

      final submitRect = tester.getRect(
        find.byKey(const ValueKey<String>('pulse-submit')),
      );
      final fieldRect = tester.getRect(
        find.byKey(const ValueKey<String>('pulse-composer-text')),
      );
      final toolbarRect = tester.getRect(
        find.byKey(const ValueKey<String>('pulse-media-toolbar')),
      );

      expect(submitRect.top, greaterThanOrEqualTo(0));
      expect(fieldRect.top, greaterThan(submitRect.bottom));
      expect(toolbarRect.bottom, lessThanOrEqualTo(340));
      expect(fieldRect.top, lessThan(toolbarRect.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quote opens with immediate immutable X-style preview', (
    tester,
  ) async {
    const author = Profile(
      id: 'author-1',
      username: 'akash',
      displayName: 'Akash',
    );
    final subject = PulseComposerSubject(
      entity: const EntityRef.post('post-1'),
      preview: PulseTarget(
        id: 'post-1',
        type: EntityType.post,
        body: 'The original message stays visible.',
        author: author,
        createdAt: DateTime.utc(2026, 7, 27, 7, 52),
      ),
    );

    await _pumpComposer(tester, subject: subject);

    expect(find.text('Quote'), findsOneWidget);
    expect(find.text('Add your take'), findsOneWidget);
    expect(find.text('Akash'), findsOneWidget);
    expect(find.text('@akash'), findsOneWidget);
    expect(find.text('The original message stays visible.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pulse-quoted-preview')),
      findsOneWidget,
    );
  });

  testWidgets('unavailable quote renders a tombstone immediately', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      subject: const PulseComposerSubject(
        entity: EntityRef.post('missing-post'),
        preview: PulseTarget(
          id: 'missing-post',
          type: EntityType.post,
          unavailable: true,
        ),
      ),
    );

    expect(find.text('This content is unavailable'), findsOneWidget);
  });
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  PulseComposerSubject? subject,
}) async {
  tester.view
    ..physicalSize = const Size(360, 640)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        myProfileProvider.overrideWithValue(const AsyncData<Profile?>(null)),
      ],
      child: MaterialApp(
        theme: KlectThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => PulseComposer.show(context, subject: subject),
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
}
