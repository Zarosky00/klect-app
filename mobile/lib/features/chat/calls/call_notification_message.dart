import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One message emitted by a guarded native or local notification action.
class CallNotificationMessage extends Notifier<String?> {
  @override
  String? build() => null;

  /// Publishes one message for the overlay host to surface.
  void publish(String message) => state = message;

  /// Clears a message after it has been shown once.
  void clear() => state = null;
}

/// Messages raised by call actions, consumed once by CallOverlayHost.
final callNotificationMessageProvider =
    NotifierProvider<CallNotificationMessage, String?>(
      CallNotificationMessage.new,
      name: 'callNotificationMessage',
    );
