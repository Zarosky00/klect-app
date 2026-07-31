/// The Alert Center's filter and count maths.
///
/// Everything here is a pure transform over rows that are **already loaded**:
/// no I/O, no `BuildContext`, no refetch. That is what makes selecting a
/// category a synchronous rebuild rather than a network round-trip, and it is
/// why the 300 ms render budget in Requirement 4.2 is met trivially.
library;

import '../../core/models/models.dart';
import 'notification_category.dart';
import 'notification_preferences.dart';

/// The highest count rendered as digits. Anything above reads `99+`.
const int notificationCountCap = 99;

/// The rows to render for [selection], newest-first order preserved.
///
/// `null` for [selection] is `All`.
///
/// Two things happen in one pass, and the order matters:
///
/// 1. Rows whose category [preferences] suppresses are dropped under **every**
///    selection, `All` included. Filtering can therefore never reveal a muted
///    row that `All` hides.
/// 2. Rows whose category is not [selection] are dropped.
///
/// Because the second step only ever removes more of what the first step kept,
/// the result for any single category is a subsequence of the result for `All`
/// with relative order intact (Requirements 4.2–4.5). Applying the same
/// selection to an already-filtered list is a no-op, so the transform is
/// idempotent.
List<NotificationModel> filterNotifications(
  Iterable<NotificationModel> rows,
  NotificationCategory? selection,
  NotificationPreferenceSet preferences,
) {
  final kept = <NotificationModel>[];
  for (final row in rows) {
    final category = NotificationCategory.of(row.type);
    if (!preferences.isEnabled(category)) continue;
    if (selection != null && category != selection) continue;
    kept.add(row);
  }
  return List<NotificationModel>.unmodifiable(kept);
}

/// Unread rows per category, read off each row's own `read_at`.
///
/// This is the whole counting story: one unread row contributes exactly one,
/// derived from state already carried on the loaded row. There is no aggregate
/// query, no counter column and no trigger behind these numbers — Requirement
/// 4.7 forbids all three. A row that rolled several identical events together
/// still counts once, because the chip counts alerts you have not read, not
/// events that happened.
///
/// The result is **total** over [NotificationCategory]: every category is
/// present, with `0` where nothing is unread. Rendering, not this map, is what
/// hides a zero — see [notificationCountLabel].
Map<NotificationCategory, int> unreadCountsByCategory(
  Iterable<NotificationModel> rows,
) {
  final counts = <NotificationCategory, int>{
    for (final category in NotificationCategory.values) category: 0,
  };
  for (final row in rows) {
    if (!row.isUnread) continue;
    final category = NotificationCategory.of(row.type);
    counts[category] = counts[category]! + 1;
  }
  return Map<NotificationCategory, int>.unmodifiable(counts);
}

/// The badge copy for [count], or null when there is nothing to show.
///
/// `1..99` render as digits — the caller draws them in `context.kt.count` so
/// the tabular figures keep the chip from twitching as the count climbs — and
/// anything above the cap reads `99+` (Requirements 4.7, 1.7). Zero and any
/// negative value produce no badge at all.
String? notificationCountLabel(int count) {
  if (count <= 0) return null;
  if (count > notificationCountCap) return '$notificationCountCap+';
  return '$count';
}
