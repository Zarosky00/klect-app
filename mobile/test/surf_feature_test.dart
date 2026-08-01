import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/core/supabase.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/chat/inbox_controller.dart';
import 'package:klect/features/surf/surf.dart';
import 'package:klect/features/surf/surf_screen.dart';

import 'support/fake_api.dart';
import 'support/test_harness.dart';

/// A feed whose covers resolve to nothing, so the tiles render their reserved
/// box and never touch the network.
class _SurfFakeApi extends FakeKlectApi {
  _SurfFakeApi(this.cards);

  final List<SurfCard> cards;

  int calls = 0;

  @override
  String? publicUrl(
    String? path, {
    StorageBucket bucket = StorageBucket.media,
  }) => null;

  @override
  Future<List<SurfCard>> surfFeed({
    int limit = 30,
    int offset = 0,
    required String seed,
    SurfFilter filter = SurfFilter.all,
  }) async {
    calls++;
    if (offset > 0) return const <SurfCard>[];
    if (filter == SurfFilter.following) return const <SurfCard>[];
    return cards;
  }
}

SurfCard _card({
  required String id,
  required int width,
  required int height,
  EntityType type = EntityType.item,
  int childCount = 1,
}) => SurfCard(
  entityType: type,
  entityId: id,
  ownerId: 'owner-$id',
  username: 'aria',
  displayName: 'Aria Vale',
  title: 'Card $id',
  width: width,
  height: height,
  likeCount: 5,
  saveCount: 2,
  childCount: childCount,
);

void main() {
  setUpAll(() async {
    final sans = FontLoader('Instrument Sans')
      ..addFont(rootBundle.load('assets/fonts/InstrumentSans[wdth,wght].ttf'));
    final display = FontLoader('Fraunces')
      ..addFont(
        rootBundle.load('assets/fonts/Fraunces[SOFT,WONK,opsz,wght].ttf'),
      );
    await Future.wait(<Future<void>>[sans.load(), display.load()]);
  });

  ProviderContainer containerFor(_SurfFakeApi api) => ProviderContainer.test(
    overrides: [
      klectApiProvider.overrideWithValue(api),
      currentUserIdProvider.overrideWithValue('me'),
      // The app bar's MessagesAction watches this; stubbing it here keeps
      // the realtime inbox (which needs a live Supabase client) out of
      // these widget tests.
      unreadMessageCountProvider.overrideWith((ref) => 0),
    ],
  );

  group('surf masonry', () {
    testWidgets('reserves every tile from its intrinsic size', (tester) async {
      final api = _SurfFakeApi(<SurfCard>[
        _card(id: 'a', width: 1000, height: 1000),
        _card(id: 'b', width: 1000, height: 1500),
        _card(id: 'c', width: 1600, height: 1000),
        _card(id: 'd', width: 1000, height: 1000),
      ]);

      await pumpKlect(
        tester,
        const SurfScreen(),
        container: containerFor(api),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      // Lazily built: only what the viewport plus the cache extent needs.
      expect(find.byType(SurfTile), findsAtLeastNWidgets(3));

      final first = tester.getSize(find.byType(SurfTile).at(0));
      final second = tester.getSize(find.byType(SurfTile).at(1));

      // Square cover → square tile; 2:3 cover → tile 1.5x taller than wide.
      expect(first.height, closeTo(first.width, 0.5));
      expect(second.height, closeTo(second.width * 1.5, 0.5));

      // Same column count means identical widths, which is what stops the
      // grid shifting sideways when a photo finally decodes.
      expect(second.width, closeTo(first.width, 0.01));
    });

    testWidgets('clamps a pathological aspect into the grid band', (
      tester,
    ) async {
      final api = _SurfFakeApi(<SurfCard>[
        _card(id: 'tall', width: 100, height: 4000),
      ]);

      await pumpKlect(
        tester,
        const SurfScreen(),
        container: containerFor(api),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SurfTile).first);
      // Aspect is clamped to Aspect.gridMin, so height / width tops out there.
      expect(size.height / size.width, closeTo(1 / Aspect.gridMin, 0.02));
    });

    testWidgets('offers all four filters and switching reloads', (
      tester,
    ) async {
      final api = _SurfFakeApi(<SurfCard>[
        _card(id: 'a', width: 1000, height: 1000),
      ]);

      await pumpKlect(
        tester,
        const SurfScreen(),
        container: containerFor(api),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      for (final filter in SurfFilter.values) {
        expect(find.text(filter.label), findsOneWidget);
      }

      await tester.tap(find.text(SurfFilter.following.label));
      await tester.pumpAndSettle();

      // The following feed is its own controller with its own fetch.
      expect(api.calls, greaterThanOrEqualTo(2));
      expect(find.byType(SurfTile), findsNothing);
    });

    testWidgets('header and filters are not duplicated during a page drag', (
      tester,
    ) async {
      final api = _SurfFakeApi(<SurfCard>[
        _card(id: 'a', width: 1000, height: 1000),
      ]);

      await pumpKlect(
        tester,
        const SurfScreen(),
        container: containerFor(api),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();

      expect(find.text('Surf'), findsOneWidget);
      for (final filter in SurfFilter.values) {
        expect(find.text(filter.label), findsOneWidget);
      }

      await gesture.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'fixed header layout at reference phone size',
      (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _SurfFakeApi(<SurfCard>[
          _card(id: 'a', width: 1000, height: 1000),
          _card(id: 'b', width: 1000, height: 1500),
          _card(id: 'c', width: 1600, height: 1000),
          _card(id: 'd', width: 1000, height: 1200),
        ]);

        await pumpKlect(
          tester,
          const SurfScreen(),
          container: containerFor(api),
          disableAnimations: true,
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(SurfScreen),
          matchesGoldenFile('goldens/surf_fixed_header_360x800.png'),
        );
      },
      tags: const <String>['golden'],
    );
  });

  group('immersiveMediaOf', () {
    test('an item pages through its own media in position order', () {
      final closeup = Closeup.fromJson(<String, dynamic>{
        'entity_type': 'item',
        'entity_id': 'i1',
        'owner': <String, dynamic>{'id': 'u1', 'username': 'aria'},
        'counts': <String, dynamic>{'like': 1},
        'viewer': <String, dynamic>{},
        'item': <String, dynamic>{'id': 'i1', 'title': 'Gojo'},
        'media': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'm2',
            'storage_path': 'media/b.jpg',
            'position': 1,
            'alt_text': 'back',
          },
          <String, dynamic>{
            'id': 'm1',
            'storage_path': 'media/a.jpg',
            'position': 0,
            'alt_text': 'front',
          },
        ],
      });

      final media = immersiveMediaOf(closeup);
      expect(media.map((m) => m.path).toList(), <String>[
        'media/a.jpg',
        'media/b.jpg',
      ]);
      expect(media.first.altText, 'front');
    });

    test('a collection leads with its own cover so the hero lands right', () {
      final closeup = Closeup.fromJson(<String, dynamic>{
        'entity_type': 'collection',
        'entity_id': 'c1',
        'owner': <String, dynamic>{'id': 'u1', 'username': 'aria'},
        'counts': <String, dynamic>{},
        'viewer': <String, dynamic>{},
        'collection': <String, dynamic>{
          'id': 'c1',
          'name': 'Anime',
          'cover_path': 'media/anime.jpg',
        },
        'subcollections': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 's1',
            'name': 'JJK',
            'cover_path': 'media/jjk.jpg',
          },
        ],
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'i1',
            'title': 'Gojo',
            'cover_path': 'media/gojo.jpg',
            'cover_width': 1200,
            'cover_height': 1600,
          },
          // A duplicate path must not produce a duplicate page.
          <String, dynamic>{
            'id': 'i2',
            'title': 'Again',
            'cover_path': 'media/gojo.jpg',
          },
        ],
      });

      final media = immersiveMediaOf(closeup);
      expect(media.map((m) => m.path).toList(), <String>[
        'media/anime.jpg',
        'media/jjk.jpg',
        'media/gojo.jpg',
      ]);
      expect(media.last.aspect, closeTo(0.75, 0.001));
    });
  });
}
