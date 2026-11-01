// Widget coverage for the v1.7.x engagement sheet, the Alerts screen and
// keyboard-safe settings sheets.
//
// The harness wraps `home` in a MediaQuery with no size, so the openers below
// re-read the real view metrics before a sheet computes its height.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/core/supabase.dart';
import 'package:klect/features/notifications/notifications_controller.dart';
import 'package:klect/features/notifications/notifications_screen.dart';
import 'package:klect/features/pulse/engagement/engagement_sheet.dart';
import 'package:klect/ui/ui.dart';

import 'support/fake_api.dart';
import 'support/test_harness.dart';

class _EngagementApi extends FakeKlectApi {
  _EngagementApi() : super(likeCount: 1, repostCount: 1);

  final List<String> tabs = <String>[];

  @override
  String? publicUrl(
    String? path, {
    StorageBucket bucket = StorageBucket.media,
  }) => null;

  @override
  Future<SocialEngagementPage> socialEngagement({
    required EntityType type,
    required String id,
    required SocialEngagementTab tab,
    int limit = 25,
    Map<String, dynamic>? cursor,
  }) async {
    tabs.add(tab.wire);
    final summary = <String, dynamic>{
      'like_count': 1,
      'repost_count': 1,
      'quote_count': 1,
    };
    final items = switch (tab) {
      SocialEngagementTab.like => <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'actor',
          'user': <String, dynamic>{
            'id': 'u1',
            'username': 'aria',
            'display_name': 'Aria Vale',
          },
          'acted_at': '2026-10-31T08:00:00Z',
        },
      ],
      SocialEngagementTab.repost => <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'actor',
          'user': <String, dynamic>{
            'id': 'u2',
            'username': 'kenji',
            'display_name': 'Kenji Mori',
          },
        },
      ],
      SocialEngagementTab.quote => <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'quote',
          'entry': <String, dynamic>{
            'feed_kind': 'quote',
            'kind': 'quote',
            'entity_type': 'post',
            'entity_id': 'q1',
            'body': 'My whole quote post',
            'created_at': '2026-10-31T08:00:00Z',
            'author': <String, dynamic>{
              'id': 'u3',
              'username': 'mina',
              'display_name': 'Mina Park',
            },
          },
        },
      ],
    };
    return SocialEngagementPage.fromJson(<String, dynamic>{
      'summary': summary,
      'items': items,
      'has_more': false,
    });
  }
}

class _FakeNotifications extends NotificationsController {
  @override
  Future<List<NotificationModel>> build() async => <NotificationModel>[
    NotificationModel(
      id: 'n1',
      type: NotificationType.like,
      entityType: EntityType.post,
      entityId: 'p1',
      createdAt: DateTime.now(),
      actor: Profile.fromJson(<String, dynamic>{
        'id': 'u1',
        'username': 'aria',
        'display_name': 'Aria Vale',
      }),
    ),
    NotificationModel(
      id: 'n2',
      type: NotificationType.comment,
      entityType: EntityType.post,
      entityId: 'p1',
      body: 'Love this shelf',
      readAt: DateTime.now(),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      actor: Profile.fromJson(<String, dynamic>{
        'id': 'u2',
        'username': 'kenji',
        'display_name': 'Kenji Mori',
      }),
    ),
  ];
}

void main() {
  testWidgets('alerts screen renders, filters and cross-fades', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer.test(
      overrides: [
        klectApiProvider.overrideWithValue(_EngagementApi()),
        currentUserIdProvider.overrideWithValue(null),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        notificationsProvider.overrideWith(_FakeNotifications.new),
      ],
    );
    addTearDown(container.dispose);
    await pumpKlect(
      tester,
      const SizedBox(width: 390, height: 800, child: NotificationsScreen()),
      container: container,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Love this shelf'), findsOneWidget);
    expect(find.text('1 new'), findsOneWidget);
    await tester.tap(find.text('Likes').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Love this shelf'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engagement sheet swipes Likes -> Reposts -> Quotes', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _EngagementApi();
    final container = ProviderContainer.test(
      overrides: [
        klectApiProvider.overrideWithValue(api),
        currentUserIdProvider.overrideWithValue('me'),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    addTearDown(container.dispose);

    await pumpKlect(
      tester,
      Builder(
        builder: (outer) => MediaQuery(
          data: MediaQueryData.fromView(View.of(outer)),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => SocialEngagementSheet.show(
                context,
                entity: const EntityRef(EntityType.post, 'p1'),
                initialTab: SocialEngagementTab.like,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      container: container,
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Likes'), findsOneWidget);
    expect(find.text('Reposts'), findsOneWidget);
    expect(find.text('Quotes'), findsOneWidget);
    expect(find.text('Aria Vale'), findsOneWidget);
    expect(api.tabs.toSet(), <String>{'like', 'repost', 'quote'});

    await tester.fling(find.text('Aria Vale'), const Offset(-300, 0), 1200);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Kenji Mori'), findsOneWidget);

    await tester.fling(find.text('Kenji Mori'), const Offset(-300, 0), 1200);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Quotes lists the account behind the quote, never the quote post.
    expect(find.text('Mina Park'), findsOneWidget);
    expect(find.textContaining('mina'), findsOneWidget);
    expect(find.text('My whole quote post'), findsNothing);

    // Tap back to Likes from the rail.
    await tester.tap(find.text('Likes'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Aria Vale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avoidKeyboard lifts a sheet field above the keyboard', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpKlect(
      tester,
      Builder(
        builder: (outer) => MediaQuery(
          data: MediaQueryData.fromView(View.of(outer)),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => KSheet.show<void>(
                context: context,
                title: 'Change password',
                avoidKeyboard: true,
                builder: (_) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    KTextField(label: 'New password', obscureText: true),
                    SizedBox(height: 16),
                    KTextField(label: 'Confirm password', obscureText: true),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final lastBottom = tester.getBottomLeft(fields.last).dy;
    expect(lastBottom, lessThanOrEqualTo(844 - 340));
    expect(tester.takeException(), isNull);
  });
}
