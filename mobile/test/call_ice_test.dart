import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:klect/features/chat/calls/call_config.dart';

Map<String, dynamic> _stun(String host) => <String, dynamic>{
  'urls': <String>['stun:$host:3478'],
};

Map<String, dynamic> _relay(String host) => <String, dynamic>{
  'urls': <String>['turn:$host:3478?transport=udp'],
  'username': 'ephemeral',
  'credential': 'secret',
};

void main() {
  setUp(KlectCallIce.resetResolution);
  tearDown(() {
    KlectCallIce.resetResolution();
    KlectCallIce.credentialFetcher = () async => null;
  });

  group('KlectCallIce.resolutionFrom', () {
    test('orders every STUN entry before every relay entry', () {
      final resolution = KlectCallIce.resolutionFrom(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[
          _relay('relay.example.com'),
          _stun('stun.example.com'),
        ],
      });

      expect(resolution.relayAvailable, isTrue);
      expect(resolution.failure, isNull);
      final urls = <String>[
        for (final server in resolution.iceServers)
          (server['urls'] as List<dynamic>).first as String,
      ];
      expect(urls.first, startsWith('stun:'));
      expect(urls.last, startsWith('turn:'));
    });

    test('truncates to eight entries by dropping the tail of that order', () {
      final resolution = KlectCallIce.resolutionFrom(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[
          for (var i = 0; i < 7; i++) _stun('stun$i.example.com'),
          for (var i = 0; i < 3; i++) _relay('relay$i.example.com'),
        ],
      });

      expect(resolution.iceServers, hasLength(KlectCallIce.maxIceServers));
      final kept = <String>[
        for (final server in resolution.iceServers)
          (server['urls'] as List<dynamic>).first as String,
      ];
      expect(kept.where((url) => url.startsWith('stun:')), hasLength(7));
      expect(kept.last, startsWith('turn:'));
      expect(kept.last, contains('relay0'));
    });

    test('drops a relay entry that cannot authenticate', () {
      final resolution = KlectCallIce.resolutionFrom(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[
          _stun('stun.example.com'),
          <String, dynamic>{
            'urls': <String>['turn:relay.example.com:3478'],
            'username': 'ephemeral',
          },
        ],
      });

      expect(resolution.relayAvailable, isFalse);
      expect(resolution.failure, 'turn_not_configured');
      expect(resolution.iceServers, hasLength(1));
    });

    test('degrades to STUN only when the payload has no server list', () {
      final resolution = KlectCallIce.resolutionFrom('nonsense');

      expect(resolution.relayAvailable, isFalse);
      expect(resolution.failure, 'provider_unavailable');
      expect(resolution.iceServers, isNotEmpty);
    });
  });

  group('KlectCallIce.resolve', () {
    test('degrades instead of throwing when the fetch fails', () async {
      KlectCallIce.credentialFetcher = () async => throw StateError('down');

      final resolution = await KlectCallIce.resolve(callId: 'call-1');

      expect(resolution.relayAvailable, isFalse);
      expect(resolution.failure, 'provider_unavailable');
      expect(resolution.diagnostic['relay_available'], isFalse);
    });

    test('degrades on a timeout without throwing', () async {
      KlectCallIce.credentialFetcher = () async =>
          throw TimeoutException('slow');

      final resolution = await KlectCallIce.resolve(callId: 'call-1');

      expect(resolution.relayAvailable, isFalse);
      expect(resolution.failure, 'timeout');
    });

    test('issues no second request for the same call id', () async {
      var calls = 0;
      KlectCallIce.credentialFetcher = () async {
        calls++;
        throw StateError('down');
      };

      final first = await KlectCallIce.resolve(callId: 'call-1');
      final second = await KlectCallIce.resolve(callId: 'call-1');

      expect(calls, 1);
      expect(second, same(first));
    });

    test('re-resolves for a different call id', () async {
      var calls = 0;
      KlectCallIce.credentialFetcher = () async {
        calls++;
        return <String, dynamic>{
          'iceServers': <Map<String, dynamic>>[_relay('relay.example.com')],
        };
      };

      final first = await KlectCallIce.resolve(callId: 'call-1');
      final second = await KlectCallIce.resolve(callId: 'call-2');

      expect(calls, 2);
      expect(first.relayAvailable, isTrue);
      expect(second.relayAvailable, isTrue);
      expect(second, isNot(same(first)));
    });
  });
}
