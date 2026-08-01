import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/notifications/push_notifications.dart';

void main() {
  test('foreground push payload exposes notification id and deep link', () {
    final data = <String, dynamic>{
      'notification_id': 'notification-1',
      'link': '/messages/conversation-1',
    };

    expect(pushDataString(data, 'notification_id'), 'notification-1');
    expect(pushDataString(data, 'link'), '/messages/conversation-1');
  });

  test('missing, empty and non-string push values are ignored', () {
    expect(pushDataString(const <String, dynamic>{}, 'link'), isNull);
    expect(pushDataString(const <String, dynamic>{'link': ''}, 'link'), isNull);
    expect(pushDataString(const <String, dynamic>{'link': 7}, 'link'), isNull);
  });
}
