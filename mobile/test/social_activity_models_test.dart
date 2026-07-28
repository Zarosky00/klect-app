import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';

void main() {
  test('Pulse v2 keeps quote count and opaque composite cursor', () {
    final page = PulseEntryPage.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'entity_type': 'post',
          'entity_id': 'post-1',
          'kind': 'post',
          'counts': <String, dynamic>{'like': 8, 'repost': 2, 'quote': 5},
        },
      ],
      'has_more': true,
      'next_cursor': <String, dynamic>{
        'score': 4.25,
        'sort_at': '2026-07-28T10:00:00Z',
        'kind_rank': 1,
        'primary_id': 'post-1',
        'actor_id': 'user-1',
      },
    });

    expect(page.items.single.quoteCount, 5);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor?['score'], 4.25);
  });

  test('engagement response parses actor and quote rows separately', () {
    final page = SocialEngagementPage.fromJson(<String, dynamic>{
      'summary': <String, dynamic>{
        'like_count': 3,
        'repost_count': 2,
        'quote_count': 1,
      },
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'actor',
          'user': <String, dynamic>{
            'id': 'user-1',
            'username': 'akash',
            'display_name': 'Akash',
          },
          'viewer_follows': true,
          'acted_at': '2026-07-28T10:00:00Z',
        },
        <String, dynamic>{
          'kind': 'quote',
          'entry': <String, dynamic>{
            'entity_type': 'post',
            'entity_id': 'quote-1',
            'kind': 'quote',
            'body': 'Worth keeping.',
          },
        },
      ],
      'has_more': false,
    });

    expect(page.summary.quoteCount, 1);
    expect(page.items.first.profile?.name, 'Akash');
    expect(page.items.first.viewerFollows, isTrue);
    expect(page.items.last.isQuote, isTrue);
    expect(page.items.last.entry?.body, 'Worth keeping.');
  });

  test('discussion activity retains surface, parent and deep-link context', () {
    final page = ProfileDiscussionPage.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'comment-2',
          'body': 'That lens is excellent.',
          'created_at': '2026-07-28T10:00:00Z',
          'parent_id': 'comment-1',
          'author': <String, dynamic>{
            'id': 'user-1',
            'username': 'akash',
            'display_name': 'Akash',
          },
          'counts': <String, dynamic>{
            'like': 4,
            'save': 1,
            'repost': 0,
            'reply': 2,
          },
          'viewer': <String, dynamic>{'liked': true},
          'surface': 'surf',
          'context': <String, dynamic>{
            'target_type': 'item',
            'target_id': 'item-1',
            'title': '50mm Lens',
            'unavailable': false,
          },
          'replying_to': <String, dynamic>{
            'id': 'comment-1',
            'username': 'aria',
            'body': 'My favorite portrait lens.',
          },
          'destination': <String, dynamic>{
            'type': 'item',
            'id': 'item-1',
            'highlight_comment_id': 'comment-2',
          },
        },
      ],
      'has_more': false,
    });

    final row = page.items.single;
    expect(row.surface, ProfileSurface.surf);
    expect(row.comment.likeCount, 4);
    expect(row.comment.viewerLiked, isTrue);
    expect(row.replyingTo?.username, 'aria');
    expect(row.context.title, '50mm Lens');
    expect(row.destination.highlightCommentId, 'comment-2');
  });

  test('private reaction response supports Surf targets and Pulse entries', () {
    final surf = ProfileReactionPage.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'acted_at': '2026-07-28T10:00:00Z',
          'target_type': 'collection',
          'target_id': 'collection-1',
          'target': <String, dynamic>{
            'type': 'collection',
            'id': 'collection-1',
            'title': 'Cameras',
          },
        },
      ],
      'has_more': false,
    });
    final pulse = ProfileReactionPage.fromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'target_type': 'post',
          'target_id': 'post-1',
          'entry': <String, dynamic>{
            'entity_type': 'post',
            'entity_id': 'post-1',
            'body': 'Hello Pulse',
          },
        },
      ],
      'has_more': false,
    });

    expect(surf.items.single.target?.title, 'Cameras');
    expect(pulse.items.single.entry?.body, 'Hello Pulse');
  });
}
