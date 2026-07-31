import 'package:flutter_test/flutter_test.dart';
import 'package:klect/features/chat/calls/call_controller.dart';

/// The transition set from Requirement 7.9, written out edge by edge so a
/// change to the engine has to be a change to the requirement first.
const Set<(CallPhase, CallPhase)> _legalEdges = {
  (CallPhase.idle, CallPhase.dialing),
  (CallPhase.idle, CallPhase.incoming),
  (CallPhase.dialing, CallPhase.connecting),
  (CallPhase.dialing, CallPhase.ended),
  (CallPhase.incoming, CallPhase.connecting),
  (CallPhase.incoming, CallPhase.ended),
  (CallPhase.connecting, CallPhase.active),
  (CallPhase.connecting, CallPhase.ended),
  (CallPhase.active, CallPhase.reconnecting),
  (CallPhase.active, CallPhase.ended),
  (CallPhase.reconnecting, CallPhase.active),
  (CallPhase.reconnecting, CallPhase.ended),
};

void main() {
  group('ActiveCallController.allowedTransitions', () {
    test('declares an entry for every phase', () {
      expect(
        ActiveCallController.allowedTransitions.keys,
        containsAll(CallPhase.values),
      );
    });

    test('permits exactly the transition set and nothing else', () {
      for (final from in CallPhase.values) {
        for (final to in CallPhase.values) {
          final permitted = ActiveCallController.allowedTransitions[from]!
              .contains(to);
          expect(
            permitted,
            _legalEdges.contains((from, to)),
            reason: '$from → $to',
          );
        }
      }
    });

    test('leaves ended absorbing', () {
      expect(ActiveCallController.allowedTransitions[CallPhase.ended], isEmpty);
    });
  });

  group('ActiveCallState', () {
    test('starts idle, chrome visible, with no stale remote frame', () {
      const state = ActiveCallState();

      expect(state.phase, CallPhase.idle);
      expect(state.chromeVisible, isTrue);
      expect(state.remoteFrameStaleSince, isNull);
      expect(state.relayAvailable, isTrue);
      expect(state.elapsed, Duration.zero);
      expect(state.isBusy, isFalse);
    });

    test('carries the new fields through copyWith', () {
      final stale = DateTime.utc(2026, 4, 1, 12);
      final state = const ActiveCallState().copyWith(
        chromeVisible: false,
        remoteFrameStaleSince: stale,
        relayAvailable: false,
      );

      expect(state.chromeVisible, isFalse);
      expect(state.remoteFrameStaleSince, stale);
      expect(state.relayAvailable, isFalse);
      expect(
        state.copyWith(clearRemoteFrameStale: true).remoteFrameStaleSince,
        isNull,
      );
    });
  });
}
