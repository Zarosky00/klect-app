import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/api_error.dart';
import 'package:klect/core/supabase.dart';
import 'package:klect/features/chat/calls/call_availability.dart';
import 'package:klect/features/chat/chat_api.dart';

/// A `call_feature_enabled` RPC scripted per call.
class _GateApi extends Fake implements ChatApi {
  _GateApi(this._answers);

  final List<Future<bool> Function()> _answers;
  int calls = 0;

  @override
  Future<bool> callFeatureEnabled() {
    final index = calls < _answers.length ? calls : _answers.length - 1;
    calls++;
    return _answers[index]();
  }
}

const _rpcFailed = KlectError(KlectErrorKind.network, 'offline');

ProviderContainer _containerFor(_GateApi api, {String? userId = 'me'}) =>
    ProviderContainer.test(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        currentUserIdProvider.overrideWithValue(userId),
      ],
    );

void main() {
  var now = DateTime(2026, 7, 27, 12);
  setUp(() => CallAvailability.clock = () => now);
  tearDown(() => CallAvailability.clock = DateTime.now);

  test('starts disabled and adopts a successful read', () async {
    final api = _GateApi([() async => true]);
    final container = _containerFor(api);

    expect(container.read(callAvailabilityProvider), isFalse);
    await container.read(callAvailabilityProvider.notifier).refreshIfStale();
    expect(container.read(callAvailabilityProvider), isTrue);
    expect(api.calls, 1);
  });

  test('an error resolves to disabled and surfaces nothing', () async {
    final api = _GateApi([() async => throw _rpcFailed]);
    final container = _containerFor(api);

    await container.read(callAvailabilityProvider.notifier).refreshIfStale();
    expect(container.read(callAvailabilityProvider), isFalse);
    expect(
      container.read(callAvailabilityProvider.notifier).lastSuccessAt,
      isNull,
    );
  });

  test('a failed read after a success falls closed', () async {
    final api = _GateApi([
      () async => true,
      () async => throw _rpcFailed,
    ]);
    final container = _containerFor(api);
    final gate = container.read(callAvailabilityProvider.notifier);

    await gate.refreshIfStale();
    expect(container.read(callAvailabilityProvider), isTrue);

    now = now.add(CallAvailability.staleAfter);
    await gate.refreshIfStale();
    expect(container.read(callAvailabilityProvider), isFalse);
    // Nothing to trust, so the next foreground tries again immediately.
    expect(gate.lastSuccessAt, isNull);
  });

  test('an unresolved read stays disabled and is not stacked', () async {
    final api = _GateApi([() => Completer<bool>().future]);
    final container = _containerFor(api);
    final gate = container.read(callAvailabilityProvider.notifier);

    unawaited(gate.refreshIfStale());
    unawaited(gate.refreshIfStale());
    await Future<void>.delayed(Duration.zero);

    expect(container.read(callAvailabilityProvider), isFalse);
    expect(gate.lastSuccessAt, isNull);
    expect(api.calls, 1, reason: 'one read in flight at a time');
  });

  test('foreground refresh is skipped until the success is 5 minutes old',
      () async {
    final api = _GateApi([() async => true]);
    final container = _containerFor(api);
    final gate = container.read(callAvailabilityProvider.notifier);

    await gate.refreshIfStale();
    expect(api.calls, 1);

    now = now.add(CallAvailability.staleAfter - const Duration(seconds: 1));
    await gate.refreshIfStale();
    expect(api.calls, 1, reason: 'still fresh');

    now = now.add(const Duration(seconds: 1));
    await gate.refreshIfStale();
    expect(api.calls, 2, reason: 'exactly 5 minutes old is stale');
  });

  // The widget binding runs the body in a fake-async zone, so pumping past the
  // budget fires the real `.timeout()` timer without a real 10 s wait.
  testWidgets('a read that never returns is disabled after the 10 s budget',
      (tester) async {
    final api = _GateApi([
      () => Completer<bool>().future,
      () async => true,
    ]);
    final container = _containerFor(api);
    final gate = container.read(callAvailabilityProvider.notifier);

    var settled = false;
    unawaited(gate.refreshIfStale().then((_) => settled = true));
    await tester.pump(CallAvailability.readTimeout + const Duration(seconds: 1));

    expect(settled, isTrue, reason: 'the read stops waiting at the budget');
    expect(container.read(callAvailabilityProvider), isFalse);
    expect(gate.lastSuccessAt, isNull);
    expect(api.calls, 1);

    // A timed-out read is not a success, so the next foreground tries again.
    unawaited(gate.refreshIfStale());
    await tester.pump();
    expect(api.calls, 2);
    expect(container.read(callAvailabilityProvider), isTrue);
  });

  test('signed out never asks the server', () async {
    final api = _GateApi([() async => true]);
    final container = _containerFor(api, userId: null);

    expect(container.read(callAvailabilityProvider), isFalse);
    await container.read(callAvailabilityProvider.notifier).refreshIfStale();
    expect(api.calls, 0);
  });
}
