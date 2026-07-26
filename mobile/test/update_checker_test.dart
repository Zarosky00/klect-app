import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/core/updates/update_checker.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/shell/update_banner.dart';
import 'package:klect/ui/ui.dart';

/// A canned GitHub `releases/latest` payload.
String releaseJson({String tag = 'v1.3.0', String body = 'Bug fixes.'}) =>
    jsonEncode(<String, Object?>{
      'tag_name': tag,
      'body': body,
      'html_url': 'https://github.com/Zarosky00/klect-app/releases/tag/$tag',
    });

void main() {
  group('UpdateChecker.isNewer', () {
    test('strictly newer versions win', () {
      expect(UpdateChecker.isNewer('1.3.0', '1.2.0'), isTrue);
      expect(UpdateChecker.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateChecker.isNewer('1.10.0', '1.9.9'), isTrue);
      expect(UpdateChecker.isNewer('1.2.1', '1.2.0'), isTrue);
    });

    test('equal and older versions do not', () {
      expect(UpdateChecker.isNewer('1.2.0', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('1.1.9', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('0.9.0', '1.0.0'), isFalse);
    });

    test('accepts a leading v and ignores build metadata / pre-release', () {
      expect(UpdateChecker.isNewer('v1.3.0', '1.2.0'), isTrue);
      expect(UpdateChecker.isNewer('V1.3.0', '1.2.0'), isTrue);
      expect(UpdateChecker.isNewer('v1.2.0+42', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('v1.3.0-rc.1+sha.abc', '1.2.0'), isTrue);
      expect(UpdateChecker.isNewer('1.2.0', 'v1.2.0+7'), isFalse);
    });

    test('short tags read missing segments as zero', () {
      expect(UpdateChecker.isNewer('v2', '1.9.9'), isTrue);
      expect(UpdateChecker.isNewer('1.2', '1.2.0'), isFalse);
    });

    test('garbage never banners', () {
      expect(UpdateChecker.isNewer('latest', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('1.3.0', 'not-a-version'), isFalse);
      expect(UpdateChecker.isNewer('1.2.3.4', '1.2.0'), isFalse);
    });
  });

  group('UpdateChecker.check', () {
    late MemoryKeyValueStore store;
    late int networkCalls;
    var nowMs = DateTime.utc(2026, 7, 27).millisecondsSinceEpoch;

    setUp(() {
      store = MemoryKeyValueStore();
      networkCalls = 0;
      nowMs = DateTime.utc(2026, 7, 27).millisecondsSinceEpoch;
    });

    UpdateChecker checker(MockClient client, {String current = '1.2.0'}) =>
        UpdateChecker(
          store: store,
          client: client,
          currentVersion: current,
          now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
        );

    MockClient github({String tag = 'v1.3.0', String body = 'Bug fixes.'}) =>
        MockClient((request) async {
          networkCalls++;
          expect(
            request.headers['Accept'],
            'application/vnd.github+json',
            reason: 'GitHub asks for its media type on every call',
          );
          return http.Response(releaseJson(tag: tag, body: body), 200);
        });

    test('surfaces a newer release with its notes', () async {
      final update =
          await checker(github(tag: 'v1.3.0', body: 'Shiny.')).check();
      expect(update, isNotNull);
      expect(update!.version, '1.3.0');
      expect(update.notes, 'Shiny.');
      expect(networkCalls, 1);
    });

    test('an equal or older release stays silent', () async {
      expect(await checker(github(tag: 'v1.2.0')).check(), isNull);
      expect(await checker(github(tag: 'v1.1.0')).check(), isNull);
    });

    test('a skipped version stops bannering; the next one banners', () async {
      final first = checker(github());
      final update = await first.check();
      expect(update!.version, '1.3.0');

      await first.skip('1.3.0');
      expect(await checker(github()).check(), isNull);

      // 6h+ later a newer release lands — the skip must not silence it.
      nowMs += const Duration(hours: 7).inMilliseconds;
      final next = await checker(github(tag: 'v1.4.0')).check();
      expect(next!.version, '1.4.0');
    });

    test('at most one network check per 6 hours, cache answers between',
        () async {
      final client = github();
      expect((await checker(client).check())!.version, '1.3.0');
      expect(networkCalls, 1);

      // Inside the window: still bannering, but from cache.
      nowMs += const Duration(hours: 5).inMilliseconds;
      expect((await checker(client).check())!.version, '1.3.0');
      expect(networkCalls, 1);

      // Past the window: the network is consulted again.
      nowMs += const Duration(hours: 2).inMilliseconds;
      expect((await checker(client).check())!.version, '1.3.0');
      expect(networkCalls, 2);
    });

    test('rate limiting is silent and retried next cold start', () async {
      final limited = MockClient((request) async {
        networkCalls++;
        return http.Response('{"message":"API rate limit exceeded"}', 403);
      });
      expect(await checker(limited).check(), isNull);
      expect(networkCalls, 1);

      // The failure must not consume the throttle window.
      expect((await checker(github()).check())!.version, '1.3.0');
      expect(networkCalls, 2);
    });

    test('offline is silent, and falls back to the cached answer', () async {
      final offline = MockClient((request) async {
        networkCalls++;
        throw http.ClientException('network is unreachable');
      });
      expect(await checker(offline).check(), isNull);

      // Learn about 1.3.0, then go offline past the throttle window: the
      // banner survives on the cached release.
      expect((await checker(github()).check())!.version, '1.3.0');
      nowMs += const Duration(hours: 7).inMilliseconds;
      expect((await checker(offline).check())!.version, '1.3.0');
    });

    test('malformed payloads never banner', () async {
      final broken = MockClient(
        (request) async => http.Response('<!doctype html>', 200),
      );
      expect(await checker(broken).check(), isNull);

      final tagless = MockClient(
        (request) async =>
            http.Response(jsonEncode(<String, Object?>{'body': 'hi'}), 200),
      );
      expect(await checker(tagless).check(), isNull);
    });
  });

  group('UpdateBanner', () {
    ProviderContainer harness({String tag = 'v9.9.9'}) =>
        ProviderContainer.test(
          overrides: [
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
            updateCheckerProvider.overrideWith(
              (ref) => UpdateChecker(
                store: ref.watch(keyValueStoreProvider),
                client: MockClient(
                  (request) async => http.Response(
                    releaseJson(tag: tag, body: 'Notes for $tag.'),
                    200,
                  ),
                ),
                currentVersion: '1.0.0',
              ),
            ),
          ],
        );

    // Not `pumpKlect`: the sheet caps its height from `MediaQuery.sizeOf`,
    // and that harness pins a zero-size MediaQuery over the child. A plain
    // MaterialApp gives the banner the real test-surface size, as the app
    // shell does.
    Future<void> pumpBanner(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: KlectThemeData.dark(),
            home: const Scaffold(bottomNavigationBar: UpdateBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the release and opens the sheet', (tester) async {
      final container = harness();
      await pumpBanner(tester, container);

      expect(find.text('Klect 9.9.9 is available'), findsOneWidget);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.text('Klect 9.9.9'), findsOneWidget);
      expect(find.text('Notes for v9.9.9.'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Skip this version'), findsOneWidget);
    });

    testWidgets('dismiss hides the banner for the session', (tester) async {
      final container = harness();
      await pumpBanner(tester, container);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Klect 9.9.9 is available'), findsNothing);
      // Session-only: nothing was persisted.
      expect(
        container
            .read(keyValueStoreProvider)
            .getString(UpdateChecker.skippedVersionKey),
        isNull,
      );
    });

    testWidgets('skip persists the version and hides the banner',
        (tester) async {
      final container = harness();
      await pumpBanner(tester, container);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip this version'));
      await tester.pumpAndSettle();

      expect(find.byType(KSheetShell), findsNothing);
      expect(find.text('Klect 9.9.9 is available'), findsNothing);
      expect(
        container
            .read(keyValueStoreProvider)
            .getString(UpdateChecker.skippedVersionKey),
        '9.9.9',
      );
    });
  });
}
