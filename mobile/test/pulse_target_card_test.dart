import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/pulse/data/pulse_entry_view.dart';
import 'package:klect/features/pulse/widgets/pulse_card.dart';
import 'package:klect/features/pulse/widgets/pulse_target_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/test_harness.dart';

void main() {
  testWidgets(
    'plain post repost renders original byline, media and Surf attachment',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final container = ProviderContainer.test(
        overrides: [klectApiProvider.overrideWithValue(KlectApi(client))],
      );
      addTearDown(container.dispose);

      final entry = PulseEntry.fromJson(<String, dynamic>{
        'feed_kind': 'repost',
        'kind': null,
        'entity_type': 'post',
        'entity_id': 'post-1',
        'cursor_id': 'post-1',
        'created_at': '2026-07-28T08:30:00+00:00',
        'author': <String, dynamic>{
          'id': 'author-1',
          'username': 'aria',
          'display_name': 'Aria Vale',
        },
        'reposter': <String, dynamic>{
          'id': 'reposter-1',
          'username': 'kenji',
          'display_name': 'Kenji Mori',
        },
        'target': <String, dynamic>{
          'type': 'post',
          'id': 'post-1',
          'body': 'The complete original post',
          'author': <String, dynamic>{
            'id': 'author-1',
            'username': 'aria',
            'display_name': 'Aria Vale',
          },
          'media': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'post-media-1',
              'storage_path': 'post-media-1.jpg',
              'width': 1200,
              'height': 900,
              'position': 0,
            },
          ],
          'attached_target': <String, dynamic>{
            'type': 'item',
            'id': 'item-1',
            'title': 'Going Merry model',
            'subtitle': 'Attached from Surf',
          },
        },
      });

      await pumpKlect(
        tester,
        SingleChildScrollView(
          child: PulseCard(item: PulseItem.fromEntry(entry)),
        ),
        container: container,
      );
      await tester.pump();

      expect(find.text('Kenji Mori reposted'), findsOneWidget);
      expect(find.text('Aria Vale'), findsOneWidget);
      expect(find.text('@aria'), findsOneWidget);
      expect(find.text('The complete original post'), findsOneWidget);
      expect(find.byType(PostMediaGrid), findsOneWidget);
      expect(find.text('Going Merry model'), findsOneWidget);
      expect(find.text('Attached from Surf'), findsOneWidget);
    },
  );

  testWidgets('entity repost keeps its owner, text and complete media grid', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final container = ProviderContainer.test(
      overrides: [klectApiProvider.overrideWithValue(KlectApi(client))],
    );
    addTearDown(container.dispose);

    final target = PulseTarget(
      id: 'collection-1',
      type: EntityType.collection,
      title: 'Desk Objects',
      subtitle: 'Boards, caps, and the surface they sit on.',
      childCount: 8,
      author: const Profile(
        id: 'dev-1',
        username: 'dev',
        displayName: 'Dev Raman',
      ),
      media: <ItemMedia>[
        for (var index = 0; index < 4; index++)
          ItemMedia(
            id: 'media-$index',
            storagePath: 'https://example.invalid/$index.jpg',
            position: index,
            width: 800,
            height: 600,
          ),
      ],
    );

    await pumpKlect(
      tester,
      PulseTargetCard(target: target, interactive: false),
      container: container,
    );

    expect(find.text('Dev Raman'), findsOneWidget);
    expect(find.text('@dev'), findsOneWidget);
    expect(find.text('Desk Objects'), findsOneWidget);
    expect(
      find.text('Boards, caps, and the surface they sit on.'),
      findsOneWidget,
    );
    expect(find.text('8 things'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pulse-target-media-grid')),
      findsOneWidget,
    );
  });

  testWidgets('single portrait attachment stays bounded in the timeline', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final container = ProviderContainer.test(
      overrides: [klectApiProvider.overrideWithValue(KlectApi(client))],
    );
    addTearDown(container.dispose);

    await pumpKlect(
      tester,
      const PulseTargetCard(
        interactive: false,
        target: PulseTarget(
          id: 'item-1',
          type: EntityType.item,
          title: 'Gaon',
          childCount: 1,
          media: <ItemMedia>[
            ItemMedia(
              id: 'portrait-1',
              storagePath: 'https://example.invalid/portrait.jpg',
              width: 736,
              height: 1314,
            ),
          ],
        ),
      ),
      container: container,
    );

    final media = find.byKey(const ValueKey<String>('pulse-target-media-grid'));
    expect(media, findsOneWidget);
    expect(tester.getSize(media).height, lessThanOrEqualTo(Space.s24 * 3));
    expect(find.text('1 photo'), findsOneWidget);
  });
}
