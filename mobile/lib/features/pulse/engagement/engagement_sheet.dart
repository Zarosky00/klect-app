import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../profile/person_row.dart';
import '../data/pulse_entry_view.dart';
import '../widgets/pulse_card.dart';

typedef EngagementQuery = ({EntityRef entity, SocialEngagementTab tab});

@immutable
class EngagementState {
  const EngagementState({
    this.summary = const EngagementSummary(),
    this.items = const <SocialEngagementItem>[],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.unavailable = false,
    this.error,
  });

  final EngagementSummary summary;
  final List<SocialEngagementItem> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final bool unavailable;
  final KlectError? error;

  EngagementState copyWith({
    EngagementSummary? summary,
    List<SocialEngagementItem>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Map<String, dynamic>? nextCursor,
    bool? unavailable,
    KlectError? error,
    bool clearError = false,
  }) => EngagementState(
    summary: summary ?? this.summary,
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: nextCursor ?? this.nextCursor,
    unavailable: unavailable ?? this.unavailable,
    error: clearError ? null : (error ?? this.error),
  );
}

class EngagementController extends Notifier<EngagementState> {
  EngagementController(this.query);

  final EngagementQuery query;
  final Set<String> _seen = <String>{};
  bool _busy = false;
  bool _disposed = false;

  @override
  EngagementState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen<SocialActivityMutation?>(socialActivityMutationProvider, (
      previous,
      next,
    ) {
      if (next?.entity == query.entity &&
          next?.revision != previous?.revision) {
        unawaited(refresh());
      }
    });
    unawaited(Future<void>.microtask(refresh));
    return const EngagementState();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy || (!reset && !state.hasMore)) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: state.items.isEmpty, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(klectApiProvider)
          .socialEngagement(
            type: query.entity.type,
            id: query.entity.id,
            tab: query.tab,
            cursor: reset ? null : state.nextCursor,
          );
      if (_disposed) return;
      if (reset) _seen.clear();
      final fresh = <SocialEngagementItem>[];
      for (final item in page.items) {
        final key = item.profile?.id ?? item.entry?.key ?? '${item.actedAt}';
        if (_seen.add(key)) fresh.add(item);
      }
      state = EngagementState(
        summary: page.summary,
        items: reset ? fresh : <SocialEngagementItem>[...state.items, ...fresh],
        loading: false,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        unavailable: page.unavailable,
      );
    } on KlectError catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          error: error,
        );
      }
    } finally {
      _busy = false;
    }
  }
}

final engagementProvider = NotifierProvider.autoDispose
    .family<EngagementController, EngagementState, EngagementQuery>(
      EngagementController.new,
      name: 'socialEngagement',
    );

/// Public engagement viewer opened by tapping a non-zero action count.
abstract final class SocialEngagementSheet {
  static Future<void> show(
    BuildContext context, {
    required EntityRef entity,
    required SocialEngagementTab initialTab,
  }) => KSheet.show<void>(
    context: context,
    title: 'Engagement',
    maxHeightFraction: 0.94,
    builder: (_) => _EngagementBody(entity: entity, initialTab: initialTab),
  );
}

class _EngagementBody extends ConsumerStatefulWidget {
  const _EngagementBody({required this.entity, required this.initialTab});

  final EntityRef entity;
  final SocialEngagementTab initialTab;

  @override
  ConsumerState<_EngagementBody> createState() => _EngagementBodyState();
}

class _EngagementBodyState extends ConsumerState<_EngagementBody> {
  late SocialEngagementTab _tab = widget.initialTab;
  EngagementSummary _summary = const EngagementSummary();

  EngagementQuery get _query => (entity: widget.entity, tab: _tab);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(engagementProvider(_query));
    if (state.summary != const EngagementSummary()) {
      _summary = state.summary;
    }
    final summary =
        state.summary.likeCount == 0 &&
            state.summary.repostCount == 0 &&
            state.summary.quoteCount == 0
        ? _summary
        : state.summary;

    return Column(
      children: <Widget>[
        _EngagementTabs(
          selected: _tab,
          summary: summary,
          onSelected: (tab) => setState(() => _tab = tab),
        ),
        const SizedBox(height: Space.s2),
        Expanded(
          child: _EngagementList(query: _query, state: state),
        ),
      ],
    );
  }
}

class _EngagementTabs extends StatelessWidget {
  const _EngagementTabs({
    required this.selected,
    required this.summary,
    required this.onSelected,
  });

  final SocialEngagementTab selected;
  final EngagementSummary summary;
  final ValueChanged<SocialEngagementTab> onSelected;

  int _count(SocialEngagementTab tab) => switch (tab) {
    SocialEngagementTab.like => summary.likeCount,
    SocialEngagementTab.repost => summary.repostCount,
    SocialEngagementTab.quote => summary.quoteCount,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: <Widget>[
          for (final tab in SocialEngagementTab.values)
            Expanded(
              child: KPressable(
                semanticLabel:
                    '${tab.label}, ${_count(tab)}, ${selected == tab ? 'selected' : 'not selected'}',
                onTap: () => onSelected(tab),
                child: AnimatedContainer(
                  duration: KMotion.duration(context, KDurations.base),
                  curve: Curves_.emphasized,
                  padding: const EdgeInsets.symmetric(vertical: Space.s2),
                  decoration: BoxDecoration(
                    color: selected == tab ? colors.surface4 : colors.surface2,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(tab.label, style: context.kt.label),
                      KRollingCount(
                        value: _count(tab),
                        style: context.kt.micro.copyWith(
                          color: selected == tab
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EngagementList extends StatelessWidget {
  const _EngagementList({required this.query, required this.state});

  final EngagementQuery query;
  final EngagementState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const KSkeletonList(rows: 6);
    }
    if (state.unavailable) {
      return const KEmptyState(
        title: 'Activity unavailable',
        message: 'This content is no longer visible to you.',
        icon: Icons.visibility_off_outlined,
        compact: true,
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return Consumer(
        builder: (context, ref, _) => KErrorState(
          error: state.error,
          compact: true,
          onRetry: () => ref.read(engagementProvider(query).notifier).refresh(),
        ),
      );
    }
    if (state.items.isEmpty) {
      return KEmptyState(
        title: switch (query.tab) {
          SocialEngagementTab.like => 'No likes yet',
          SocialEngagementTab.repost => 'No reposts yet',
          SocialEngagementTab.quote => 'No quotes yet',
        },
        message: switch (query.tab) {
          SocialEngagementTab.like =>
            'The first person to like this appears here.',
          SocialEngagementTab.repost => 'Bare reposts appear here.',
          SocialEngagementTab.quote =>
            'Posts that add their own perspective appear here.',
        },
        compact: true,
      );
    }

    return Consumer(
      builder: (context, ref, _) => ListView.builder(
        key: PageStorageKey<String>(
          'engagement:${query.entity.key}:${query.tab.wire}',
        ),
        itemCount: state.items.length + 1,
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            if (!state.hasMore && state.error == null) {
              return const SizedBox(height: Space.s4);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s3),
              child: state.error != null
                  ? KInlineError(
                      message: state.error!.message,
                      onRetry: () => ref
                          .read(engagementProvider(query).notifier)
                          .loadMore(),
                    )
                  : KButton(
                      label: state.loadingMore ? 'Loading…' : 'Show more',
                      variant: KButtonVariant.ghost,
                      size: KButtonSize.small,
                      expand: true,
                      busy: state.loadingMore,
                      onPressed: state.loadingMore
                          ? null
                          : () => ref
                                .read(engagementProvider(query).notifier)
                                .loadMore(),
                    ),
            );
          }
          final item = state.items[index];
          final profile = item.profile;
          if (profile != null) {
            return TweenAnimationBuilder<double>(
              duration: KMotion.duration(context, KDurations.medium),
              curve: Curves_.emphasized,
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: KMotion.reduced(context)
                      ? Offset.zero
                      : Offset(0, Space.s2 * (1 - value)),
                  child: child,
                ),
              ),
              child: PersonRow(
                profile: profile,
                dense: true,
                subtitle: profile.handle,
              ),
            );
          }
          final entry = item.entry;
          return entry == null
              ? const SizedBox.shrink()
              : PulseCard(item: PulseItem.fromEntry(entry));
        },
      ),
    );
  }
}
