import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/notifications/notification_category.dart';
import 'package:klect/features/notifications/notification_copy.dart';

/// A notification row, with only the fields a banner reads.
NotificationModel _row(
  NotificationType type, {
  String id = 'n1',
  String? actorName = 'Aria',
  EntityType? entityType,
  String? entityId,
  String? conversationId,
  String? body,
  int count = 1,
}) => NotificationModel(
  id: id,
  type: type,
  actorId: actorName == null ? null : 'a1',
  entityType: entityType,
  entityId: entityId,
  conversationId: conversationId,
  body: body,
  count: count,
  actor: actorName == null
      ? null
      : Profile(id: 'a1', username: 'aria', displayName: actorName),
);

void main() {
  group('bannerContentFor — message (3.1)', () {
    test('titles from the sender and previews the body', () {
      final content = bannerContentFor(
        _row(
          NotificationType.message,
          body: '  the Gojo cover\nlanded  ',
          conversationId: 'c1',
        ),
      );

      expect(content.category, NotificationCategory.messages);
      expect(content.title, 'Aria');
      expect(content.message, 'the Gojo cover landed');
      expect(content.destination, '/messages/c1');
      expect(content.actions, isEmpty);
    });

    test('truncates the body to the banner bound', () {
      final content = bannerContentFor(
        _row(NotificationType.message, body: 'x' * 400),
      );

      expect(content.message.length, bannerBodyMaxChars);
      expect(content.message.endsWith('…'), isTrue);
    });

    test('substitutes an attachment label for an empty body', () {
      expect(
        bannerContentFor(_row(NotificationType.message, body: '   ')).message,
        'Sent a photo',
      );
      expect(
        bannerContentFor(
          _row(
            NotificationType.message,
            body: '',
            entityType: EntityType.collection,
            entityId: 'e1',
          ),
        ).message,
        'Shared a collection',
      );
    });
  });

  test('bannerContentFor — follow offers a follow-back action (3.2)', () {
    final content = bannerContentFor(_row(NotificationType.follow));

    expect(content.message, 'started following you');
    expect(content.actions.single.kind, BannerActionKind.followBack);
    expect(content.actions.single.label, 'Follow back');
    expect(content.actions.single.confirmedLabel, 'Following');
  });

  group('bannerContentFor — call (3.3)', () {
    test('offers accept and decline against the call id', () {
      final content = bannerContentFor(
        _row(NotificationType.call, entityId: 'call-1', conversationId: 'c1'),
      );

      expect(content.callId, 'call-1');
      expect(
        content.actions.map((a) => a.kind),
        <BannerActionKind>[
          BannerActionKind.acceptCall,
          BannerActionKind.declineCall,
        ],
      );
      expect(content.thumb, isNull);
    });

    test('offers no action where there is no call id to act on', () {
      final content = bannerContentFor(_row(NotificationType.call));

      expect(content.callId, isNull);
      expect(content.actions, isEmpty);
      expect(content.message, 'is calling you');
    });
  });

  test('bannerContentFor — recommendation carries the cover thumb (3.4)', () {
    final content = bannerContentFor(
      _row(
        NotificationType.recommendation,
        entityType: EntityType.subcollection,
        entityId: 's1',
      ),
    );

    expect(content.title, 'Aria');
    expect(content.thumb, const BannerThumbRef(EntityType.subcollection, 's1'));
  });

  group('bannerContentFor — shared phrase shape (3.5)', () {
    test('reads actor plus phrase, with the preview where text is the point',
        () {
      expect(
        bannerContentFor(
          _row(
            NotificationType.like,
            entityType: EntityType.item,
            entityId: 'i1',
          ),
        ).message,
        'liked your item',
      );
      expect(
        bannerContentFor(
          _row(
            NotificationType.comment,
            entityType: EntityType.collection,
            entityId: 'c9',
            body: 'this is unreal',
          ),
        ).message,
        'commented on your collection: this is unreal',
      );
    });

    test('never leaves the message line unbounded', () {
      final content = bannerContentFor(
        _row(NotificationType.mention, body: 'y' * 500),
      );

      expect(content.message.length, lessThanOrEqualTo(bannerBodyMaxChars));
    });
  });

  test('bannerContentFor — unknown wire labels take the generic shape (3.6)',
      () {
    final unknown = NotificationModel.fromJson(<String, dynamic>{
      'id': 'n9',
      'type': 'something_new',
      'body': 'a thing happened',
    });

    final content = bannerContentFor(unknown);

    expect(content.category, NotificationCategory.system);
    expect(content.title, bannerSystemActor);
    expect(content.message, 'a thing happened');
  });

  group('bannerActorLabel (3.12)', () {
    test('falls back to a placeholder where no name resolves', () {
      expect(
        bannerActorLabel(_row(NotificationType.like, actorName: null)),
        bannerActorPlaceholder,
      );
      expect(
        bannerActorLabel(_row(NotificationType.system, actorName: null)),
        bannerSystemActor,
      );
    });

    test('reads the grouped form where the row rolled events together', () {
      expect(
        bannerActorLabel(_row(NotificationType.like, count: 2)),
        'Aria and 1 other',
      );
      expect(
        bannerActorLabel(_row(NotificationType.like, count: 13)),
        'Aria and 12 others',
      );
    });
  });

  group('truncateBannerText', () {
    test('never splits an emoji cluster', () {
      final cut = truncateBannerText('👩‍👩‍👧‍👦' * 4, maxChars: 3);

      expect(cut, '👩‍👩‍👧‍👦👩‍👩‍👧‍👦…');
    });

    test('is idempotent at the bound', () {
      final once = truncateBannerText('z' * 300);

      expect(truncateBannerText(once), once);
    });
  });
}
