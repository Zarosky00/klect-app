import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/storage/key_value_store.dart';
import '../../core/supabase.dart';
import 'notification_category.dart';

/// Which notification categories the account wants to see.
///
/// Immutable and **total** over the 11 [NotificationCategory] values: the set
/// carries the disabled categories, so an absent key — a category the server
/// has never heard of, or a JSONB payload that predates it — reads as enabled
/// (Requirement 5.8). Encoding always writes all 11 boolean keys, so decoding
/// the encoded form returns an equal set (Requirement 5.9).
@immutable
class NotificationPreferenceSet {
  /// Wraps the disabled categories. Everything not listed is enabled.
  const NotificationPreferenceSet(this._disabled);

  final Set<NotificationCategory> _disabled;

  /// The default state: nothing muted.
  static const NotificationPreferenceSet allEnabled =
      NotificationPreferenceSet(<NotificationCategory>{});

  /// Whether [category] is shown and delivered.
  bool isEnabled(NotificationCategory category) => !_disabled.contains(category);

  /// The muted categories, for callers that need the whole picture.
  Set<NotificationCategory> get disabled =>
      Set<NotificationCategory>.unmodifiable(_disabled);

  /// Whether anything at all is muted.
  bool get hasDisabled => _disabled.isNotEmpty;

  /// The set with [category] switched on or off.
  ///
  /// Applying the same value twice returns an equal set, which is what makes
  /// preference writes idempotent (Requirement 5.10).
  NotificationPreferenceSet withEnabled(
    NotificationCategory category,
    bool enabled,
  ) {
    if (enabled == isEnabled(category)) return this;
    final next = <NotificationCategory>{..._disabled};
    if (enabled) {
      next.remove(category);
    } else {
      next.add(category);
    }
    return NotificationPreferenceSet(next);
  }

  /// The JSONB payload: always all 11 keys, always booleans.
  Map<String, bool> toJson() => <String, bool>{
    for (final category in NotificationCategory.values)
      category.wire: isEnabled(category),
  };

  /// Decodes a stored payload, tolerating anything the wire hands over.
  ///
  /// Unknown keys are ignored, a non-boolean value reads as enabled, and a
  /// null, malformed or non-object payload resolves to [allEnabled] — a bad
  /// row can never mute an account by accident (Requirement 5.8).
  static NotificationPreferenceSet fromJson(Object? json) {
    var decoded = json;
    if (decoded is String) {
      if (decoded.trim().isEmpty) return allEnabled;
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return allEnabled;
      }
    }
    if (decoded is! Map) return allEnabled;
    final disabled = <NotificationCategory>{};
    for (final category in NotificationCategory.values) {
      final value = decoded[category.wire];
      if (value is bool && !value) disabled.add(category);
    }
    return NotificationPreferenceSet(disabled);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferenceSet &&
      other._disabled.length == _disabled.length &&
      other._disabled.containsAll(_disabled);

  @override
  int get hashCode => Object.hashAllUnordered(_disabled);

  @override
  String toString() => 'NotificationPreferenceSet(disabled: $_disabled)';
}

/// The account-synced notification preference store.
///
/// The switches used to be a device preference; they are now
/// `user_preferences.notifications` on the signed-in account, so signing in on
/// a second device renders the same 11 switches (Requirement 5.7) and the
/// push fanout can honour the same flags the client honours (Requirement 5.6).
class NotificationPreferencesService
    extends AsyncNotifier<NotificationPreferenceSet> {
  /// The device-local muted set written by releases before this one.
  ///
  /// Read exactly once per account, then never again (Requirement 5.13). The
  /// key itself is left in place — nothing is deleted.
  static const String legacyMutedKey = 'klect.notifications.muted.v1';

  /// Records which accounts have already had their legacy set migrated.
  static const String migratedKey = 'klect.notifications.migrated.v1';

  /// How long a preference write may take before it is rolled back.
  ///
  /// A network budget, not a motion value: the Token_Set caps *animation*
  /// durations and has nothing to say about how long an RPC may hang
  /// (Requirement 5.11).
  static const Duration writeTimeout = Duration(seconds: 10);

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  Future<NotificationPreferenceSet> build() async {
    final userId = ref.watch(currentUserIdProvider);
    // Signed out: there is no account to hold preferences, and nothing is
    // muted until one signs in.
    if (userId == null) return NotificationPreferenceSet.allEnabled;

    final resolved = await _read(userId);
    return _migrateLegacy(userId, resolved);
  }

  /// Reads the stored set. A missing row or a missing key is enabled.
  Future<NotificationPreferenceSet> _read(String userId) async {
    if (!KlectSupabase.isInitialised) {
      return NotificationPreferenceSet.allEnabled;
    }
    try {
      final row = await ref
          .read(klectApiProvider)
          .client
          .from('user_preferences')
          .select('notifications')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return NotificationPreferenceSet.allEnabled;
      return NotificationPreferenceSet.fromJson(row['notifications']);
    } on Object {
      // An unreachable server means "nothing muted" rather than a broken
      // settings screen; the next build re-reads.
      return NotificationPreferenceSet.allEnabled;
    }
  }

  /// Switches one category on or off.
  ///
  /// Applies optimistically so the switch moves under the finger, then keeps
  /// the authoritative set the RPC returns. On any error, or when the RPC has
  /// not answered within [writeTimeout], the **entire** previous set is
  /// restored and no message is surfaced (Requirement 5.11).
  Future<void> setEnabled(NotificationCategory category, bool enabled) {
    final previous = _current;
    return _write(previous: previous, next: previous.withEnabled(category, enabled));
  }

  /// Turns every category back on.
  Future<void> enableAll() =>
      _write(previous: _current, next: NotificationPreferenceSet.allEnabled);

  NotificationPreferenceSet get _current =>
      state.value ?? NotificationPreferenceSet.allEnabled;

  Future<void> _write({
    required NotificationPreferenceSet previous,
    required NotificationPreferenceSet next,
  }) async {
    state = AsyncData<NotificationPreferenceSet>(next);
    try {
      final result = await _push(next);
      state = AsyncData<NotificationPreferenceSet>(
        NotificationPreferenceSet.fromJson(result),
      );
    } on Object {
      // Requirement 5.11: restore all 11 flags, say nothing. `bad_notification_
      // preferences` and an unauthorised caller both land here — the payload is
      // rejected whole server-side, so the rendered state simply goes back.
      state = AsyncData<NotificationPreferenceSet>(previous);
    }
  }

  Future<Object?> _push(NotificationPreferenceSet set) {
    if (!KlectSupabase.isInitialised) {
      return Future<Object?>.error(StateError('supabase not initialised'));
    }
    final Future<dynamic> request = ref
        .read(klectApiProvider)
        .client
        .rpc<dynamic>(
          'set_notification_preferences',
          params: <String, dynamic>{'p_notifications': set.toJson()},
        );
    return request.timeout(writeTimeout);
  }

  /// Folds a legacy device-local muted set into the account store, once.
  ///
  /// Each muted [NotificationType] maps to its [NotificationCategory] and is
  /// written as `enabled: false`; every other category is left enabled
  /// (Requirement 5.12). The migrated marker records the account id, so a
  /// shared device migrates each account exactly once, and a committed
  /// migration means the device-local key is never read again (5.13).
  Future<NotificationPreferenceSet> _migrateLegacy(
    String userId,
    NotificationPreferenceSet resolved,
  ) async {
    if (_migratedAccounts().contains(userId)) return resolved;

    final muted = _legacyMutedCategories();
    if (muted == null) return resolved;
    if (muted.isEmpty) {
      // Nothing to carry over, but the account is done with the legacy key.
      await _markMigrated(userId);
      return resolved;
    }

    var next = resolved;
    for (final category in muted) {
      next = next.withEnabled(category, false);
    }
    try {
      final result = await _push(next);
      await _markMigrated(userId);
      return NotificationPreferenceSet.fromJson(result);
    } on Object {
      // The marker stays unset so the next sign-in tries again; the account
      // store, not the local set, remains what is rendered meanwhile.
      return resolved;
    }
  }

  /// The categories the legacy key mutes, or null when there is no legacy key.
  Set<NotificationCategory>? _legacyMutedCategories() {
    final raw = _store.getString(legacyMutedKey);
    if (raw == null) return null;
    if (raw.isEmpty) return const <NotificationCategory>{};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <NotificationCategory>{};
    }
    if (decoded is! List) return const <NotificationCategory>{};
    return <NotificationCategory>{
      for (final entry in decoded)
        if (entry is String)
          for (final type in NotificationType.values)
            if (type.wire == entry) NotificationCategory.of(type),
    };
  }

  Set<String> _migratedAccounts() {
    final raw = _store.getString(migratedKey);
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <String>{
          for (final entry in decoded)
            if (entry is String) entry,
        };
      }
    } on FormatException {
      // A marker written by hand or by an older shape still means "done".
    }
    return <String>{raw};
  }

  Future<void> _markMigrated(String userId) => _store.setString(
    migratedKey,
    jsonEncode(<String>[..._migratedAccounts(), userId]),
  );
}

/// The signed-in account's notification preferences.
final notificationPreferencesProvider =
    AsyncNotifierProvider<
      NotificationPreferencesService,
      NotificationPreferenceSet
    >(NotificationPreferencesService.new, name: 'notificationPreferences');

/// The resolved set, falling back to "nothing muted" while it loads.
///
/// Presenters and gates need a total answer synchronously; the settings screen
/// watches the [AsyncValue] instead so it can render the store's state before
/// any switch accepts input.
final resolvedNotificationPreferencesProvider =
    Provider<NotificationPreferenceSet>(
      (ref) =>
          ref.watch(notificationPreferencesProvider).value ??
          NotificationPreferenceSet.allEnabled,
      name: 'resolvedNotificationPreferences',
    );

/// Human labels for the settings screen, in the order they are shown.
const Map<NotificationCategory, ({String title, String subtitle})>
notificationCategoryCopy =
    <NotificationCategory, ({String title, String subtitle})>{
      NotificationCategory.likes: (
        title: 'Likes',
        subtitle: 'When someone likes your collection, shelf or item.',
      ),
      NotificationCategory.saves: (
        title: 'Saves',
        subtitle: 'When someone saves something of yours.',
      ),
      NotificationCategory.reposts: (
        title: 'Reposts',
        subtitle: 'When your work is put back into circulation.',
      ),
      NotificationCategory.commentsAndReplies: (
        title: 'Comments & replies',
        subtitle: 'New comments on anything you own, and replies to yours.',
      ),
      NotificationCategory.mentions: (
        title: 'Mentions',
        subtitle: 'When someone writes your handle.',
      ),
      NotificationCategory.follows: (title: 'Follows', subtitle: 'New followers.'),
      NotificationCategory.messages: (
        title: 'Messages',
        subtitle: 'Direct messages.',
      ),
      NotificationCategory.calls: (
        title: 'Calls',
        subtitle: 'Incoming and missed calls.',
      ),
      NotificationCategory.recommendations: (
        title: 'Recommendations',
        subtitle: 'Collections picked for your taste.',
      ),
      NotificationCategory.matches: (
        title: 'Taste matches',
        subtitle: 'When a collector with your taste shows up.',
      ),
      NotificationCategory.system: (
        title: 'From KLECT',
        subtitle:
            'Product notices and moderation decisions. '
            'Safety notices always arrive by email as well.',
      ),
    };
