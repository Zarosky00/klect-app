import 'package:flutter_test/flutter_test.dart';
import 'package:klect/features/chat/calls/call_config.dart';
import 'package:klect/features/chat/calls/call_controller.dart';

/// The termination budgets of Requirement 7 as the engine computes them.
///
/// Both helpers are pure, so they can be pinned without a peer connection, a
/// Supabase session or a real clock.
void main() {
  group('ringTimeoutRemaining (7.5)', () {
    final created = DateTime.utc(2026, 4, 1, 12);

    test('measures from the row, not from the arm time', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(
          created,
          now: created.add(const Duration(seconds: 10)),
        ),
        KlectCallTimings.ringTimeout - const Duration(seconds: 10),
      );
    });

    test('gives a row armed at its creation the whole budget', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(created, now: created),
        KlectCallTimings.ringTimeout,
      );
    });

    test('yields zero for a row already past its budget', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(
          created,
          now: created.add(KlectCallTimings.ringTimeout),
        ),
        Duration.zero,
      );
      expect(
        ActiveCallController.ringTimeoutRemaining(
          created,
          now: created.add(const Duration(minutes: 5)),
        ),
        Duration.zero,
      );
    });

    test('caps a future creation timestamp at the full budget', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(
          created,
          now: created.subtract(const Duration(minutes: 5)),
        ),
        KlectCallTimings.ringTimeout,
      );
    });

    test('falls back to the full budget when the row carries no timestamp', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(null, now: created),
        KlectCallTimings.ringTimeout,
      );
    });

    test('compares across time zones by absolute time', () {
      expect(
        ActiveCallController.ringTimeoutRemaining(
          created,
          now: created.add(const Duration(seconds: 5)).toLocal(),
        ),
        KlectCallTimings.ringTimeout - const Duration(seconds: 5),
      );
    });
  });

  group('clientElapsedSeconds (7.8)', () {
    test('reports zero for a call that never connected', () {
      expect(ActiveCallController.clientElapsedSeconds(Duration.zero), 0);
    });

    test('never reports a negative value', () {
      expect(
        ActiveCallController.clientElapsedSeconds(
          const Duration(seconds: -30),
        ),
        0,
      );
    });

    test('reports whole seconds, truncating sub-second time', () {
      expect(
        ActiveCallController.clientElapsedSeconds(
          const Duration(seconds: 42, milliseconds: 900),
        ),
        42,
      );
    });

    test('clamps to one day', () {
      expect(
        ActiveCallController.clientElapsedSeconds(const Duration(days: 1)),
        KlectCallTimings.maxClientElapsedSeconds,
      );
      expect(
        ActiveCallController.clientElapsedSeconds(const Duration(days: 400)),
        KlectCallTimings.maxClientElapsedSeconds,
      );
    });
  });

  group('KlectCallTimings', () {
    test('carries the Requirement 7 budgets', () {
      expect(KlectCallTimings.ringTimeout, const Duration(seconds: 45));
      expect(KlectCallTimings.connectTimeout, const Duration(seconds: 30));
      expect(KlectCallTimings.answerTimeout, const Duration(seconds: 15));
      expect(KlectCallTimings.reconnectTimeout, const Duration(seconds: 25));
      expect(KlectCallTimings.maxClientElapsedSeconds, 86400);
    });
  });
}
