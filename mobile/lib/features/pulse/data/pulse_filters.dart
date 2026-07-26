import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import 'pulse_entry_view.dart';

/// What kind of Pulse rows to show.
enum PulseTypeFilter {
  /// Everything.
  all('All'),

  /// Text-only posts — no photos, nothing attached.
  text('Text'),

  /// Rows whose content is photographs.
  photos('Photos'),

  /// Rows sharing a collection / shelf / thing.
  collections('Collections'),

  /// Quote posts.
  quotes('Quotes');

  const PulseTypeFilter(this.label);

  /// Chip label.
  final String label;
}

/// How far back the stream reaches.
enum PulseTimeFilter {
  /// The last day.
  today('Today', Duration(days: 1)),

  /// The last seven days.
  week('Week', Duration(days: 7)),

  /// The last thirty days.
  month('Month', Duration(days: 30)),

  /// No cutoff.
  all('All', null);

  const PulseTimeFilter(this.label, this.window);

  /// Chip label.
  final String label;

  /// The lookback window; null = unbounded.
  final Duration? window;
}

/// The Pulse filter drawer's state — Type, Time and the shared-taste toggle.
///
/// These are **client-side** filters over the pages already fetched (the
/// stream keeps paging normally underneath), which keeps the drawer instant
/// and costs zero extra round-trips; the drawer's search field is the one
/// thing that talks to the server (`search_all`'s 0021 posts section).
@immutable
class PulseFilters {
  /// Creates a filter set.
  const PulseFilters({
    this.type = PulseTypeFilter.all,
    this.time = PulseTimeFilter.all,
    this.sharedTaste = false,
  });

  /// Which row shapes pass.
  final PulseTypeFilter type;

  /// How recent a row must be.
  final PulseTimeFilter time;

  /// Only rows from collectors whose taste overlaps the viewer's
  /// (`get_matches`).
  final bool sharedTaste;

  /// Whether anything deviates from the defaults — drives the active dot on
  /// the drawer toggle.
  bool get isActive =>
      type != PulseTypeFilter.all ||
      time != PulseTimeFilter.all ||
      sharedTaste;

  /// Copy with overrides.
  PulseFilters copyWith({
    PulseTypeFilter? type,
    PulseTimeFilter? time,
    bool? sharedTaste,
  }) =>
      PulseFilters(
        type: type ?? this.type,
        time: time ?? this.time,
        sharedTaste: sharedTaste ?? this.sharedTaste,
      );

  /// Whether one row passes. [tasteIds] is the matched-collector set when
  /// the shared-taste toggle is on and loaded; while it is still loading the
  /// toggle is a no-op rather than blanking the stream.
  bool matches(PulseItem item, Set<String>? tasteIds) {
    if (!_matchesType(item)) return false;

    final window = time.window;
    if (window != null) {
      final at = item.sortAt;
      if (at == null || at.isBefore(DateTime.now().subtract(window))) {
        return false;
      }
    }

    if (sharedTaste && tasteIds != null) {
      final authorId = item.author?.id ?? item.reposter?.id;
      if (authorId == null || !tasteIds.contains(authorId)) return false;
    }
    return true;
  }

  bool _matchesType(PulseItem item) {
    switch (type) {
      case PulseTypeFilter.all:
        return true;
      case PulseTypeFilter.text:
        return item.media.isEmpty &&
            item.target == null &&
            item.attachment == null &&
            (item.text?.isNotEmpty ?? false);
      case PulseTypeFilter.photos:
        return item.media.isNotEmpty ||
            (item.target?.type == EntityType.post &&
                item.target?.coverPath != null);
      case PulseTypeFilter.collections:
        final targetType = item.targetType;
        return targetType == EntityType.collection ||
            targetType == EntityType.subcollection ||
            targetType == EntityType.item;
      case PulseTypeFilter.quotes:
        return item.kind == PulseKind.quote;
    }
  }

  /// Applies the whole set to a page of rows.
  List<PulseItem> apply(List<PulseItem> items, Set<String>? tasteIds) {
    if (!isActive) return items;
    return <PulseItem>[
      for (final item in items)
        if (matches(item, tasteIds)) item,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PulseFilters &&
          other.type == type &&
          other.time == time &&
          other.sharedTaste == sharedTaste;

  @override
  int get hashCode => Object.hash(type, time, sharedTaste);
}

/// Owns the drawer's selections. Shared by both tabs — a filter describes
/// what the viewer wants to see, not which feed they are looking at.
class PulseFiltersController extends Notifier<PulseFilters> {
  @override
  PulseFilters build() => const PulseFilters();

  /// Picks a type chip.
  void setType(PulseTypeFilter type) => state = state.copyWith(type: type);

  /// Picks a time chip.
  void setTime(PulseTimeFilter time) => state = state.copyWith(time: time);

  /// Flips the shared-taste toggle.
  void toggleSharedTaste() =>
      state = state.copyWith(sharedTaste: !state.sharedTaste);

  /// Back to defaults.
  void clear() => state = const PulseFilters();
}

/// The active Pulse filters.
final pulseFiltersProvider =
    NotifierProvider<PulseFiltersController, PulseFilters>(
  PulseFiltersController.new,
  name: 'pulseFilters',
);

/// Collector ids whose taste overlaps the viewer's — `get_matches`, fetched
/// once per session for the shared-taste toggle.
final matchedCollectorIdsProvider = FutureProvider<Set<String>>(
  (ref) async {
    final matches = await ref.watch(klectApiProvider).getMatches(limit: 50);
    return <String>{for (final match in matches) match.profile.id};
  },
  name: 'matchedCollectorIds',
);
