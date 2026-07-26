import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/pulse/data/pulse_entry_view.dart';
import 'package:klect/features/pulse/data/pulse_filters.dart';
import 'package:klect/features/pulse/widgets/pulse_card.dart';

/// The 0021 thread-first contracts: `get_post_thread` parsing, the composite
/// feed cursor, the client-side Pulse filters and the bounded stream photo.
void main() {
  Map<String, dynamic> envelope({
    String id = 'p1',
    String? cursorId,
    String kind = 'post',
    String? body = 'hello shelf',
    List<Map<String, dynamic>> media = const <Map<String, dynamic>>[],
    Map<String, dynamic>? target,
    Map<String, dynamic>? reposter,
    String feedKind = 'post',
    String entityType = 'post',
    String? sortAt,
  }) =>
      <String, dynamic>{
        'feed_kind': feedKind,
        'kind': feedKind == 'repost' ? null : kind,
        'post_id': feedKind == 'repost' ? null : id,
        'cursor_id': ?cursorId,
        'entity_type': entityType,
        'entity_id': id,
        'sort_at': sortAt ?? '2026-07-27T10:00:00+00:00',
        'created_at': sortAt ?? '2026-07-27T10:00:00+00:00',
        'body': body,
        'like_count': 2,
        'save_count': 1,
        'repost_count': 0,
        'comment_count': 3,
        'view_count': 9,
        'viewer_liked': true,
        'viewer_saved': false,
        'viewer_reposted': false,
        'author': <String, dynamic>{
          'id': 'u-author',
          'username': 'aria',
          'display_name': 'Aria Vale',
        },
        'reposter': reposter,
        'media': media,
        'target': target,
      };

  group('PostThread', () {
    test('parses the get_post_thread payload', () {
      final thread = PostThread.fromJson(<String, dynamic>{
        'post': envelope(cursorId: 'p1'),
        'stats': <String, dynamic>{
          'like_count': 2,
          'repost_count': 1,
          'save_count': 0,
          'comment_count': 3,
          'view_count': 9,
        },
        'comments': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'body': 'first!',
            'author': <String, dynamic>{'id': 'u2', 'username': 'kenji'},
            'created_at': '2026-07-27T10:05:00+00:00',
            'like_count': 4,
            'save_count': 1,
            'repost_count': 2,
            'reply_count': 1,
            'parent_id': null,
            'depth': 0,
            'viewer': <String, dynamic>{
              'liked': true,
              'saved': false,
              'reposted': true,
            },
          },
        ],
        'has_more': true,
      }, 'p1');

      expect(thread.hasMore, isTrue);
      expect(thread.stats.commentCount, 3);
      expect(thread.post.entityId, 'p1');

      final comment = thread.comments.single;
      // Stamped by the parser — the RPC omits them because they are implied.
      expect(comment.entityType, EntityType.post);
      expect(comment.entityId, 'p1');
      // 0021: comments are full social citizens, nested viewer state parses.
      expect(comment.saveCount, 1);
      expect(comment.repostCount, 2);
      expect(comment.viewerLiked, isTrue);
      expect(comment.viewerSaved, isFalse);
      expect(comment.viewerReposted, isTrue);

      final seed = InteractionState.fromComment(comment);
      expect(seed.liked, isTrue);
      expect(seed.reposted, isTrue);
      expect(seed.saveCount, 1);
      expect(seed.hydrated, isTrue);
    });
  });

  group('composite cursor', () {
    test('cursor_id rides the envelope into the view model', () {
      final item = PulseItem.fromEntry(
        PulseEntry.fromJson(envelope(cursorId: 'cursor-1')),
      );
      expect(item.cursorId, 'cursor-1');
    });

    test('a pre-0021 payload falls back to the row id', () {
      final item = PulseItem.fromEntry(PulseEntry.fromJson(envelope()));
      // No cursor_id key (offline cache from an older build): the post id
      // still pages correctly.
      expect(item.cursorId, 'p1');
    });
  });

  group('PulseFilters', () {
    PulseItem row(Map<String, dynamic> json) =>
        PulseItem.fromEntry(PulseEntry.fromJson(json));

    final textPost = row(envelope());
    final photoPost = row(
      envelope(
        id: 'p2',
        media: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'm1',
            'storage_path': 'u/1.jpg',
            'width': 800,
            'height': 600,
            'position': 0,
          },
        ],
      ),
    );
    final quotePost = row(envelope(id: 'p3', kind: 'quote'));
    final entityRepost = row(
      envelope(
        id: 'e1',
        feedKind: 'repost',
        entityType: 'collection',
        body: null,
        reposter: <String, dynamic>{'id': 'u-rep', 'username': 'kenji'},
        target: <String, dynamic>{
          'type': 'collection',
          'id': 'e1',
          'title': 'Anime',
          'unavailable': false,
        },
      ),
    );
    final stale = row(
      envelope(id: 'p4', sortAt: '2026-07-10T10:00:00+00:00'),
    );

    test('type chips pick the right shapes', () {
      const text = PulseFilters(type: PulseTypeFilter.text);
      expect(text.matches(textPost, null), isTrue);
      expect(text.matches(photoPost, null), isFalse);
      expect(text.matches(entityRepost, null), isFalse);

      const photos = PulseFilters(type: PulseTypeFilter.photos);
      expect(photos.matches(photoPost, null), isTrue);
      expect(photos.matches(textPost, null), isFalse);

      const collections = PulseFilters(type: PulseTypeFilter.collections);
      expect(collections.matches(entityRepost, null), isTrue);
      expect(collections.matches(textPost, null), isFalse);

      const quotes = PulseFilters(type: PulseTypeFilter.quotes);
      expect(quotes.matches(quotePost, null), isTrue);
      expect(quotes.matches(textPost, null), isFalse);
    });

    test('time window drops old rows', () {
      const week = PulseFilters(time: PulseTimeFilter.week);
      expect(week.matches(stale, null), isFalse);
    });

    test('shared taste keeps matched collectors only, and is a no-op while '
        'the match set is still loading', () {
      const taste = PulseFilters(sharedTaste: true);
      expect(taste.matches(textPost, <String>{'u-author'}), isTrue);
      expect(taste.matches(textPost, <String>{'somebody-else'}), isFalse);
      // Null set = matches not loaded yet: never blank the stream.
      expect(taste.matches(textPost, null), isTrue);
    });

    test('defaults pass everything through untouched', () {
      const none = PulseFilters();
      final items = <PulseItem>[textPost, photoPost, quotePost, entityRepost];
      expect(none.apply(items, null), same(items));
    });
  });

  group('bounded stream photo', () {
    test('a tall photo is widened until it fits the height ceiling', () {
      // Intrinsic 1:2 portrait in a 400px column with a 384px ceiling:
      // the grid clamp alone (0.62) would still be 645px tall, so the
      // bound wins.
      final aspect = PostMediaGrid.boundedAspect(0.5, 400, 384);
      expect(aspect, closeTo(400 / 384, 0.0001));
    });

    test('a landscape photo keeps its own ratio', () {
      final aspect = PostMediaGrid.boundedAspect(1.5, 400, 384);
      expect(aspect, 1.5);
    });

    test('no ceiling means the plain grid clamp', () {
      final aspect = PostMediaGrid.boundedAspect(0.2, 400, null);
      expect(aspect, closeTo(0.62, 0.0001));
    });
  });
}
