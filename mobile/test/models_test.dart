import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/design/tokens.g.dart';

/// These payloads are verbatim slices of what the live `new_klect` project
/// returns, so a schema drift breaks a test rather than a screen.
void main() {
  group('SurfCard', () {
    test('parses a surf_feed row', () {
      final card = SurfCard.fromJson(<String, dynamic>{
        'entity_type': 'item',
        'entity_id': 'cccccccc-0000-0000-0000-000000000002',
        'owner_id': '11111111-1111-1111-1111-111111111111',
        'username': 'aria',
        'display_name': 'Aria Vale',
        'avatar_path': 'https://picsum.photos/seed/av111111/200/200',
        'is_verified': true,
        'title': 'Sukuna Finger Replica',
        'subtitle': 'Bandai',
        'cover_path': 'media/1111/sukuna.jpg',
        'cover_blurhash': 'L6PZfSi_.AyE_3t7t7R**0o#DgR4',
        'width': 1000,
        'height': 1500,
        'accent_color': null,
        'like_count': 5,
        'save_count': 1,
        'repost_count': 0,
        'comment_count': 0,
        'view_count': 7,
        'child_count': 1,
        'created_at': '2026-07-26T11:47:25.294063+00:00',
        'score': 6.74361,
        'viewer_liked': false,
        'viewer_saved': false,
        'viewer_reposted': false,
        'viewer_follows': false,
      });

      expect(card.entityType, EntityType.item);
      expect(card.ownerName, 'Aria Vale');
      expect(card.key, 'item:cccccccc-0000-0000-0000-000000000002');
      expect(card.width, 1000);
      expect(card.height, 1500);
      expect(card.tileAspect, closeTo(1000 / 1500, 0.0001));
    });

    test('clamps a pathological aspect into the grid band', () {
      final tall = SurfCard.fromJson(<String, dynamic>{
        'entity_type': 'item',
        'entity_id': 'x',
        'owner_id': 'y',
        'username': 'z',
        'width': 100,
        'height': 4000,
      });
      expect(tall.tileAspect, Aspect.gridMin);

      final unknown = SurfCard.fromJson(<String, dynamic>{
        'entity_type': 'collection',
        'entity_id': 'x',
        'owner_id': 'y',
        'username': 'z',
      });
      expect(unknown.tileAspect, Aspect.cover);
    });
  });

  group('Closeup', () {
    test('parses the item shape with media, breadcrumb and siblings', () {
      final closeup = Closeup.fromJson(<String, dynamic>{
        'entity_type': 'item',
        'entity_id': 'cccccccc-0000-0000-0000-000000000001',
        'item': <String, dynamic>{
          'id': 'cccccccc-0000-0000-0000-000000000001',
          'title': 'Gojo — Vol. 11 Cover',
          'brand': 'Shueisha',
          'description': 'First print, spine intact.',
          'collection_id': 'aaaaaaaa-0000-0000-0000-000000000001',
          'subcollection_id': 'bbbbbbbb-0000-0000-0000-000000000001',
          'attributes': <String, dynamic>{},
        },
        'media': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'm2',
            'position': 1,
            'storage_path': 'media/1111/gojo-2.jpg',
            'width': 1200,
            'height': 900,
            'blurhash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
          },
          <String, dynamic>{
            'id': 'm1',
            'position': 0,
            'storage_path': 'media/1111/gojo-1.jpg',
            'width': 1200,
            'height': 1600,
            'blurhash': 'LKO2?U%2Tw=w]~RBVZRi};RPxuwH',
          },
        ],
        'owner': <String, dynamic>{
          'id': '11111111-1111-1111-1111-111111111111',
          'username': 'aria',
          'display_name': 'Aria Vale',
          'is_verified': true,
          'follower_count': 4,
        },
        'counts': <String, dynamic>{
          'like': 5,
          'save': 2,
          'view': 6,
          'repost': 0,
          'comment': 2,
        },
        'viewer': <String, dynamic>{
          'liked': false,
          'saved': false,
          'follows': false,
          'is_owner': null,
          'reposted': false,
        },
        'siblings': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cccccccc-0000-0000-0000-000000000002',
            'title': 'Sukuna Finger Replica',
            'cover_path': 'media/1111/sukuna.jpg',
            'like_count': 5,
            'cover_width': 1000,
            'cover_height': 1500,
          },
        ],
        'breadcrumb': <String, dynamic>{
          'collection': <String, dynamic>{
            'id': 'aaaaaaaa-0000-0000-0000-000000000001',
            'name': 'Anime',
            'slug': 'anime',
          },
          'subcollection': <String, dynamic>{
            'id': 'bbbbbbbb-0000-0000-0000-000000000001',
            'name': 'JJK',
            'slug': 'jjk',
          },
        },
        'tags': <String>[],
      });

      expect(closeup.entityType, EntityType.item);
      expect(closeup.title, 'Gojo — Vol. 11 Cover');
      expect(closeup.counts.like, 5);
      expect(
        closeup.viewer.isOwner,
        isFalse,
        reason: 'null is_owner reads as "not the owner"',
      );
      expect(
        closeup.media.first.position,
        0,
        reason: 'media is sorted by position',
      );
      expect(closeup.media.map((m) => m.id).toList(), <String>['m1', 'm2']);
      expect(closeup.breadcrumb!.trail.map((e) => e.name).toList(), <String>[
        'Anime',
        'JJK',
      ]);
      expect(closeup.siblings.single.title, 'Sukuna Finger Replica');
      expect(closeup.immersivePaths.length, 2);
    });

    test('parses the collection shape', () {
      final closeup = Closeup.fromJson(<String, dynamic>{
        'entity_type': 'collection',
        'entity_id': 'aaaaaaaa-0000-0000-0000-000000000001',
        'collection': <String, dynamic>{
          'id': 'aaaaaaaa-0000-0000-0000-000000000001',
          'name': 'Anime',
          'slug': 'anime',
          'item_count': 3,
          'subcollection_count': 2,
          'accent_color': '#F0B429',
        },
        'subcollections': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'bbbbbbbb-0000-0000-0000-000000000001',
            'name': 'JJK',
            'slug': 'jjk',
            'item_count': 2,
            'position': 0,
          },
        ],
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cccccccc-0000-0000-0000-000000000003',
            'title': 'Going Merry Model',
            'media_count': 1,
          },
        ],
        'owner': <String, dynamic>{'id': 'u', 'username': 'aria'},
        'counts': <String, dynamic>{'like': 3, 'repost': 1},
        'viewer': <String, dynamic>{},
        'tags': <String>['anime'],
      });

      expect(closeup.collection!.name, 'Anime');
      expect(closeup.subcollections.single.name, 'JJK');
      expect(closeup.items.single.title, 'Going Merry Model');
      expect(closeup.tags, <String>['anime']);
      expect(closeup.item, isNull);
    });
  });

  group('PulseTargetEnvelope', () {
    test('keeps ordered media and one immutable nested attachment', () {
      final target = PulseTarget.fromJson(<String, dynamic>{
        'type': 'post',
        'id': 'post-1',
        'availability': 'available',
        'body': 'The original words',
        'media': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'second',
            'storage_path': 'u/posts/second.jpg',
            'position': 1,
          },
          <String, dynamic>{
            'id': 'first',
            'storage_path': 'u/posts/first.jpg',
            'position': 0,
          },
        ],
        'author': <String, dynamic>{
          'id': 'u',
          'username': 'aria',
          'display_name': 'Aria Vale',
        },
        'attached_target': <String, dynamic>{
          'type': 'collection',
          'id': 'collection-1',
          'availability': 'available',
          'title': 'Collected stories',
          'media': <Map<String, dynamic>>[],
        },
      });

      expect(target.unavailable, isFalse);
      expect(target.availability, 'available');
      expect(target.media.map((item) => item.id), <String>['first', 'second']);
      expect(target.attachedTarget?.type, EntityType.collection);
      expect(target.attachedTarget?.title, 'Collected stories');
    });

    test('parses an unavailable target as a renderable tombstone', () {
      final target = PulseTarget.fromJson(<String, dynamic>{
        'type': 'post',
        'id': 'gone',
        'availability': 'unavailable',
        'unavailable': true,
        'media': <Map<String, dynamic>>[],
      });

      expect(target.unavailable, isTrue);
      expect(target.media, isEmpty);
    });
  });

  group('CommentThreadPage', () {
    test('hydrates reply context, tombstones and its opaque cursor', () {
      final page = CommentThreadPage.fromJson(<String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'root',
            'entity_type': 'post',
            'entity_id': 'post-1',
            'author_id': 'u1',
            'body': null,
            'depth': 0,
            'relative_depth': 0,
            'root_id': 'root',
            'deleted': true,
            'tombstone': true,
            'viewer': <String, dynamic>{},
          },
          <String, dynamic>{
            'id': 'reply',
            'entity_type': 'post',
            'entity_id': 'post-1',
            'author_id': 'u2',
            'body': 'The surviving reply',
            'parent_id': 'root',
            'depth': 1,
            'relative_depth': 1,
            'root_id': 'root',
            'replying_to': <String, dynamic>{'id': 'root', 'username': 'aria'},
            'viewer': <String, dynamic>{'liked': true},
          },
        ],
        'has_more': true,
        'next_cursor': <String, dynamic>{
          'created_at': '2026-07-27T12:00:00Z',
          'id': 'root',
          'like_count': 4,
        },
      });

      expect(page.hasMore, isTrue);
      expect(page.nextCursor?['id'], 'root');
      expect(page.nodes.first.tombstone, isTrue);
      expect(page.nodes.last.replyingToUsername, 'aria');
      expect(page.nodes.last.viewerLiked, isTrue);
    });
  });

  group('enums', () {
    test('entity types map to their counter tables', () {
      expect(EntityType.collection.table, 'collections');
      expect(EntityType.subcollection.table, 'subcollections');
      expect(EntityType.item.table, 'items');
      expect(EntityType.post.table, 'posts');
      expect(EntityType.comment.table, 'comments');
    });

    test('report reasons match the Postgres enum exactly', () {
      expect(ReportReason.values.map((r) => r.wire).toList(), <String>[
        'spam',
        'nudity',
        'harassment',
        'hate',
        'violence',
        'self_harm',
        'ip_violation',
        'misinformation',
        'impersonation',
        'other',
      ]);
    });

    test('unknown wire values fall back rather than throwing', () {
      expect(EntityType.tryParse('galaxy'), isNull);
      expect(EntityType.parse('galaxy'), EntityType.item);
      expect(ReportReason.parse('galaxy'), ReportReason.other);
      expect(EntityVisibility.tryParse(null), isNull);
    });
  });

  group('EntityRef', () {
    test('is a value type', () {
      const a = EntityRef.item('abc');
      const b = EntityRef(EntityType.item, 'abc');
      const c = EntityRef.collection('abc');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('round-trips through its key', () {
      const ref = EntityRef.subcollection('bbbb');
      expect(ref.key, 'subcollection:bbbb');
      expect(EntityRef.tryParse(ref.key), ref);
      expect(EntityRef.tryParse('nonsense'), isNull);
    });
  });

  group('GroupPolicy', () {
    test('parses conversation controls and preserves safe defaults', () {
      final conversation = Conversation.fromJson(<String, dynamic>{
        'id': 'group-1',
        'kind': 'group',
        'title': 'Collectors',
        'group_policy': <String, dynamic>{
          'edit_info': 'owner',
          'add_members': 'everyone',
          'send_messages': 'admins',
        },
        'join_approval_required': true,
        'invite_token_prefix': 'deadbeef',
      });

      expect(conversation.groupPolicy.editInfo, GroupPermissionScope.owner);
      expect(
        conversation.groupPolicy.addMembers,
        GroupPermissionScope.everyone,
      );
      expect(
        conversation.groupPolicy.sendMessages,
        GroupPermissionScope.admins,
      );
      expect(conversation.joinApprovalRequired, isTrue);
      expect(conversation.inviteTokenPrefix, 'deadbeef');
      expect(conversation.groupPolicy.editInfo.allows('admin'), isFalse);
      expect(conversation.groupPolicy.addMembers.allows('member'), isTrue);
    });

    test('serialises the exact RPC wire shape', () {
      const policy = GroupPolicy(
        editInfo: GroupPermissionScope.everyone,
        addMembers: GroupPermissionScope.owner,
        sendMessages: GroupPermissionScope.admins,
      );
      expect(policy.toJson(), <String, dynamic>{
        'edit_info': 'everyone',
        'add_members': 'owner',
        'send_messages': 'admins',
      });
    });
  });

  group('Profile', () {
    test('reads the onboarding gate', () {
      final fresh = Profile.fromJson(<String, dynamic>{
        'id': 'u',
        'username': 'newbie',
        'onboarded_at': null,
      });
      expect(fresh.isOnboarded, isFalse);
      expect(fresh.name, 'newbie', reason: 'falls back to the handle');

      final done = Profile.fromJson(<String, dynamic>{
        'id': 'u',
        'username': 'aria',
        'display_name': 'Aria Vale',
        'onboarded_at': '2026-07-26T11:46:50.71366+00:00',
        'allow_messages_from': 'following',
      });
      expect(done.isOnboarded, isTrue);
      expect(done.name, 'Aria Vale');
      expect(done.handle, '@aria');
      expect(done.allowMessagesFrom, AllowMessagesFrom.following);
    });
  });
}
