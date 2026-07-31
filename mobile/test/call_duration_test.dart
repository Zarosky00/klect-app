import 'package:flutter_test/flutter_test.dart';
import 'package:klect/features/chat/calls/call_duration.dart';

void main() {
  group('formatCallDuration', () {
    test('reads m:ss below one hour', () {
      expect(formatCallDuration(Duration.zero), '0:00');
      expect(formatCallDuration(const Duration(seconds: 9)), '0:09');
      expect(
        formatCallDuration(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
      expect(formatCallDuration(const Duration(seconds: 3599)), '59:59');
    });

    test('reads h:mm:ss at or above one hour', () {
      expect(formatCallDuration(const Duration(hours: 1)), '1:00:00');
      expect(formatCallDuration(const Duration(seconds: 86399)), '23:59:59');
      expect(
        formatCallDuration(const Duration(hours: 25, seconds: 1)),
        '25:00:01',
      );
    });

    test('truncates sub-second precision and clamps negatives', () {
      expect(formatCallDuration(const Duration(milliseconds: 1999)), '0:01');
      expect(formatCallDuration(const Duration(seconds: -30)), '0:00');
    });
  });

  group('parseCallDuration', () {
    test('inverts both formats', () {
      expect(parseCallDuration('0:00'), Duration.zero);
      expect(
        parseCallDuration('12:05'),
        const Duration(minutes: 12, seconds: 5),
      );
      expect(parseCallDuration('1:00:00'), const Duration(hours: 1));
      expect(parseCallDuration('23:59:59'), const Duration(seconds: 86399));
    });

    test('rejects malformed strings', () {
      for (final text in <String>[
        '',
        '90',
        '1:60',
        '1:2',
        '60:00',
        'a:bb',
        '1:00:00:00',
      ]) {
        expect(parseCallDuration(text), isNull, reason: text);
      }
    });
  });
}
