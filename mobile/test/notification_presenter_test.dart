import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/tokens.g.dart';
import 'package:klect/features/notifications/notification_category.dart';
import 'package:klect/features/notifications/notification_copy.dart';
import 'package:klect/features/notifications/notification_preferences.dart';
import 'package:klect/features/notifications/notification_surfaces.dart';
import 'package:klect/router.dart';

/// A notification row, with only the fields the decision reads.
NotificationModel _row(
  NotificationType type, {
  String id = 'n1',
  EntityType? entityType,
  String? entityId,
  String? conversationId,
}) => NotificationModel(
  id: id,
  type: type,
  actorId: 'a1',
  entityType: entityType,
  entityId: entityId,
  conversationId: conversationId,
  actor: const Profile(id: 'a1', username: 'aria', displayName: 'Aria'),
);

BannerDecision _decide(
  NotificationModel row, {
  NotificationPreferenceSet preferences = NotificationPreferenceSet.allEnabled,
  String? currentRoute = Routes.surf,
  CallStatus? callStatus,
  bool bannerMounted = false,
  Set<String> recentlyPresented = const <String>{},
}) => decideBanner(
  notification: row,
  preferences: preferences,
  currentRoute: currentRoute,
  callStatus: callStatus,
  bannerMounted: bannerMounted,
  recentlyPresented: recentlyPresented,
  content: bannerContentFor(row),
);

void main() {
  group('decideBanner presents and suppresses (3.8–3.11, 5.5, 2.8)', () {
    test('presents the composed content on an unrelated route', () {
      final row = _row(
        NotificationType.like,
        entityType: EntityType.item,
        entityId: 'i1',
      );
      final decision = _decide(row);

      expect(decision, isA<PresentBanner>());
      expect(decision.suppression, isNull);
      expect(decision.content, bannerContentFor(row));
    });

    test('a repeated id is dropped (3.10)', () {
      expect(
        _decide(
          _row(NotificationType.like),
          recentlyPresented: <String>{'n1'},
        ).suppression,
        BannerSuppression.duplicateId,
      );
    });

    test('a mounted entry drops the newer notification (2.8)', () {
      expect(
        _decide(_row(NotificationType.like), bannerMounted: true).suppression,
        BannerSuppression.bannerMounted,
      );
    });

    test('a switched-off category is suppressed (5.5)', () {
      final muted = NotificationPreferenceSet.allEnabled.withEnabled(
        NotificationCategory.likes,
        false,
      );

      expect(
        _decide(_row(NotificationType.like), preferences: muted).suppression,
        BannerSuppression.categoryDisabled,
      );
      // Every other category still presents.
      expect(
        _decide(
          _row(NotificationType.save, id: 'n2'),
          preferences: muted,
        ),
        isA<PresentBanner>(),
      );
    });

    test('the Alert Center suppresses everything (3.9)', () {
      expect(
        _decide(
          _row(NotificationType.like),
          currentRoute: Routes.notifications,
        ).suppression,
        BannerSuppression.onAlertCenter,
      );
    });

    test('the destination route and its children suppress (3.8)', () {
      final row = _row(NotificationType.message, conversationId: 'c1');

      expect(
        _decide(row, currentRoute: '/messages/c1').suppression,
        BannerSuppression.onDestinationRoute,
      );
      expect(
        _decide(row, currentRoute: '/messages/c1/info').suppression,
        BannerSuppression.onDestinationRoute,
      );
      // A sibling conversation is a different screen.
      expect(_decide(row, currentRoute: '/messages/c2'), isA<PresentBanner>());
      // And the inbox is not the thread.
      expect(_decide(row, currentRoute: '/messages'), isA<PresentBanner>());
    });

    test('a call presents only while the row is ringing (3.11)', () {
      final row = _row(NotificationType.call, entityId: 'call-1');

      expect(
        _decide(row, callStatus: CallStatus.ringing),
        isA<PresentBanner>(),
      );
      for (final status in CallStatus.values.where(
        (status) => status != CallStatus.ringing,
      )) {
        expect(
          _decide(row, callStatus: status).suppression,
          BannerSuppression.callNotRinging,
          reason: status.wire,
        );
      }
      // An unconfirmable row is not a ringing row.
      expect(_decide(row).suppression, BannerSuppression.callNotRinging);
    });

    test('a null route cannot suppress', () {
      expect(
        _decide(_row(NotificationType.like), currentRoute: null),
        isA<PresentBanner>(),
      );
    });
  });

  group('bannerRouteMatches compares whole segments (3.8)', () {
    test('matches the route, its children and nothing else', () {
      expect(bannerRouteMatches('/messages/abc', '/messages/abc'), isTrue);
      expect(bannerRouteMatches('/messages/abc/info', '/messages/abc'), isTrue);
      expect(bannerRouteMatches('/messages/abcd', '/messages/abc'), isFalse);
      expect(bannerRouteMatches('/messages', '/messages/abc'), isFalse);
    });

    test('ignores query strings and a trailing slash', () {
      expect(bannerRouteMatches('/i/1?from=surf', '/i/1'), isTrue);
      expect(bannerRouteMatches('/i/1/', '/i/1'), isTrue);
    });

    test('a missing side never matches', () {
      expect(bannerRouteMatches(null, '/i/1'), isFalse);
      expect(bannerRouteMatches('/i/1', null), isFalse);
    });
  });

  group('RecentNotificationIds is a bounded ring (3.10)', () {
    test('remembers the newest 50 and forgets the oldest', () {
      final ring = RecentNotificationIds();
      for (var index = 0; index < 60; index++) {
        expect(ring.remember('n$index'), isTrue);
      }

      expect(ring.length, bannerRecentIdCapacity);
      expect(ring.contains('n9'), isFalse);
      expect(ring.contains('n10'), isTrue);
      expect(ring.contains('n59'), isTrue);
    });

    test('a repeat is reported and changes nothing', () {
      final ring = RecentNotificationIds()..remember('n1');

      expect(ring.remember('n1'), isFalse);
      expect(ring.length, 1);
    });
  });

  group('BannerEffectGuard runs each effect once (3.2, 3.3)', () {
    test('a second activation issues nothing', () async {
      final guard = BannerEffectGuard();
      var runs = 0;

      final key = BannerEffectKeys.follow('a1');
      await guard.runOnce(key, () async => runs++);
      await guard.runOnce(key, () async => runs++);

      expect(runs, 1);
      expect(guard.isClaimed(key), isTrue);
    });

    test('accept and decline share one key per call, so only one lands',
        () async {
      final guard = BannerEffectGuard();
      final issued = <String>[];

      final key = BannerEffectKeys.call('call-1');
      await guard.runOnce(key, () async => issued.add('answer_call'));
      await guard.runOnce(key, () async => issued.add('decline_call'));

      expect(issued, <String>['answer_call']);
      // A different call is a different decision.
      expect(guard.isClaimed(BannerEffectKeys.call('call-2')), isFalse);
    });

    test('a failure releases the key and rethrows so it can be retried',
        () async {
      final guard = BannerEffectGuard();
      var runs = 0;

      final key = BannerEffectKeys.follow('a1');
      await expectLater(
        guard.runOnce(key, () async {
          runs++;
          throw StateError('offline');
        }),
        throwsStateError,
      );
      expect(guard.isClaimed(key), isFalse);

      await guard.runOnce(key, () async => runs++);
      expect(runs, 2);
    });

    test('different actors keep their own keys', () async {
      final guard = BannerEffectGuard();
      final followed = <String>[];

      for (final actor in <String>['a1', 'a2', 'a1']) {
        await guard.runOnce(
          BannerEffectKeys.follow(actor),
          () async => followed.add(actor),
        );
      }

      expect(followed, <String>['a1', 'a2']);
    });
  });

  group('BannerResolutionBudget bounds the wait (1.3, 1.4, 1.11)', () {
    // A real timer, kept short so the suite does not sit out the whole 2 s.
    BannerResolutionBudget short() =>
        BannerResolutionBudget(budget: KDurations.instant);

    test('defaults to the Token_Set thumbnail budget', () {
      final budget = BannerResolutionBudget();
      addTearDown(budget.close);

      expect(budget.budget, Timeouts.thumbnail);
    });

    test('a resolved lookup wins the race', () async {
      final budget = short();
      addTearDown(budget.close);

      expect(
        await budget.race(Future<String?>.value('cover.jpg'), null),
        'cover.jpg',
      );
      expect(budget.isExpired, isFalse);
    });

    test('a never-resolving lookup falls back at the budget', () async {
      final budget = short();
      addTearDown(budget.close);

      expect(await budget.race(Completer<String?>().future, null), isNull);
      expect(budget.isExpired, isTrue);
    });

    test('a failing lookup falls back without surfacing an error', () async {
      final budget = short();
      addTearDown(budget.close);

      expect(
        await budget.race(Future<String?>.error(StateError('offline')), null),
        isNull,
      );
    });

    test('one budget bounds every lookup it is shared by', () async {
      final budget = short();
      addTearDown(budget.close);

      final results = await Future.wait(<Future<String?>>[
        for (var index = 0; index < 3; index++)
          budget.race(Completer<String?>().future, null),
      ]);

      expect(results, <String?>[null, null, null]);
    });

    test('closing releases the lookups still in flight', () async {
      final budget = BannerResolutionBudget();
      final race = budget.race(Completer<String?>().future, 'fallback');
      budget.close();

      expect(await race, 'fallback');
    });
  });
}
