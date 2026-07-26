import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/storage/key_value_store.dart';

/// Which kinds of notification the viewer has switched off **on this device**.
///
/// KLECT stores no per-type notification columns server-side, so this is
/// deliberately a device preference: it filters what the Alerts tab shows and
/// what the tab badge counts. It is stored as the list of *muted* types, so a
/// notification type added in a later release defaults to on rather than
/// silently disappearing for everyone who upgraded.
class NotificationPreferences extends Notifier<Set<NotificationType>> {
  /// Where the muted set is persisted.
  static const String storageKey = 'klect.notifications.muted.v1';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  Set<NotificationType> build() {
    final raw = _store.getString(storageKey);
    if (raw == null || raw.isEmpty) return <NotificationType>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <NotificationType>{};
      return <NotificationType>{
        for (final entry in decoded)
          if (entry is String)
            for (final type in NotificationType.values)
              if (type.wire == entry) type,
      };
    } on FormatException {
      return <NotificationType>{};
    }
  }

  /// Whether [type] is currently shown.
  bool isEnabled(NotificationType type) => !state.contains(type);

  /// Switches one type on or off and persists the change.
  Future<void> setEnabled(NotificationType type, bool enabled) async {
    final next = <NotificationType>{...state};
    if (enabled) {
      next.remove(type);
    } else {
      next.add(type);
    }
    state = next;
    await _store.setString(
      storageKey,
      jsonEncode(<String>[for (final muted in next) muted.wire]),
    );
  }

  /// Turns everything back on.
  Future<void> enableAll() async {
    state = <NotificationType>{};
    await _store.setString(storageKey, jsonEncode(const <String>[]));
  }
}

/// The muted notification types.
final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferences, Set<NotificationType>>(
  NotificationPreferences.new,
  name: 'notificationPreferences',
);

/// Human labels for the settings screen, in the order they are shown.
const Map<NotificationType, ({String title, String subtitle})>
    notificationTypeCopy = <NotificationType, ({
  String title,
  String subtitle
})>{
  NotificationType.like: (
    title: 'Likes',
    subtitle: 'When someone likes your collection, shelf or item.',
  ),
  NotificationType.save: (
    title: 'Saves',
    subtitle: 'When someone saves something of yours.',
  ),
  NotificationType.repost: (
    title: 'Reposts',
    subtitle: 'When your work is put back into circulation.',
  ),
  NotificationType.comment: (
    title: 'Comments',
    subtitle: 'New comments on anything you own.',
  ),
  NotificationType.reply: (
    title: 'Replies',
    subtitle: 'Replies to your comments.',
  ),
  NotificationType.mention: (
    title: 'Mentions',
    subtitle: 'When someone writes your handle.',
  ),
  NotificationType.follow: (
    title: 'Follows',
    subtitle: 'New followers.',
  ),
  NotificationType.message: (
    title: 'Messages',
    subtitle: 'Direct messages.',
  ),
  NotificationType.call: (
    title: 'Calls',
    subtitle: 'Incoming and missed calls.',
  ),
  NotificationType.match: (
    title: 'Taste matches',
    subtitle: 'When a collector with your taste shows up.',
  ),
  NotificationType.system: (
    title: 'From KLECT',
    subtitle: 'Product notices and moderation decisions. '
        'Safety notices always arrive by email as well.',
  ),
};
