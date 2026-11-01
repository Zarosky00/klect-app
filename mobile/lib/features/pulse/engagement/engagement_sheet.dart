import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../profile/follow_button.dart';
import '../../profile/profile_queries.dart';
import '../../profile/user_actions.dart';
import '../data/pulse_entry_view.dart';

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
        if (_seen.add(engagementItemKey(item))) fresh.add(item);
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

/// The account behind one engagement row and when it acted.
///
/// Likes and reposts carry the account directly. A quote row carries the
/// quote post instead, so its account is the post's quoter: the reposter on a
/// repost-shaped envelope, otherwise the author.
({Profile? profile, DateTime? actedAt}) engagementActor(
  SocialEngagementItem item,
) {
  final profile = item.profile;
  final entry = item.entry;
  if (profile != null || entry == null) {
    return (profile: profile, actedAt: item.actedAt);
  }
  final view = PulseItem.fromEntry(entry);
  return (
    profile: view.reposter ?? view.author,
    actedAt: item.actedAt ?? view.sortAt,
  );
}

/// Stable identity of one engagement row: the account, on every tab. Someone
/// who quoted twice is listed once, like someone who liked once.
String engagementItemKey(SocialEngagementItem item) =>
    engagementActor(item).profile?.id ?? item.entry?.key ?? '${item.actedAt}';

/// The engagement page's three tabs, in rail order.
const List<SocialEngagementTab> engagementTabs = SocialEngagementTab.values;

/// The count a tab shows on the rail.
int engagementTabCount(EngagementSummary summary, SocialEngagementTab tab) =>
    switch (tab) {
      SocialEngagementTab.like => summary.likeCount,
      SocialEngagementTab.repost => summary.repostCount,
      SocialEngagementTab.quote => summary.quoteCount,
    };

/// Picks the counts the rail shows.
///
/// Every tab's response carries the same three authoritative totals, so the
/// selected tab's loaded summary wins, then any other loaded one, and until
/// the first response lands the action bar's own optimistic counts fill in so
/// the rail never flashes zeros.
EngagementSummary resolveEngagementSummary({
  required List<EngagementSummary?> loaded,
  required int selectedIndex,
  required EngagementSummary seed,
}) {
  if (selectedIndex >= 0 && selectedIndex < loaded.length) {
    final selected = loaded[selectedIndex];
    if (selected != null) return selected;
  }
  for (final summary in loaded) {
    if (summary != null) return summary;
  }
  return seed;
}

/// Where the rail's indicator sits and how wide it is for a fractional
/// [page] on a rail of [slotWidth]-wide tabs.
///
/// The indicator stretches by up to a third mid-swipe and settles back to its
/// rest width on a tab, which is what makes the travel read as fluid rather
/// than a rigid slide.
({double left, double width}) engagementIndicatorGeometry({
  required double page,
  required double slotWidth,
  required int length,
}) {
  if (length <= 0 || slotWidth <= 0) return (left: 0, width: 0);
  final clamped = page.isNaN ? 0.0 : page.clamp(0.0, (length - 1).toDouble());
  final rest = math.max(Space.s8, slotWidth - Space.s12);
  final fraction = clamped - clamped.floorToDouble();
  final width = math.min(
    slotWidth,
    rest * (1 + math.sin(math.pi * fraction) / 3),
  );
  final left = slotWidth * clamped + (slotWidth - width) / 2;
  return (left: left, width: width);
}

/// Public engagement viewer opened by tapping a non-zero action count.
///
/// Every tab lists the accounts behind the number — who liked, who reposted,
/// who quoted — never the quote posts themselves. Swipe sideways or tap the
/// rail to move between them.
abstract final class SocialEngagementSheet {
  static Future<void> show(
    BuildContext context, {
    required EntityRef entity,
    required SocialEngagementTab initialTab,
  }) => KSheet.show<void>(
    context: context,
    title: 'Engagement',
    maxHeightFraction: 0.92,
    // The rail and the rows run edge to edge; each row owns its own inset so
    // avatars and the indicator share one left edge.
    padding: EdgeInsets.zero,
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
  late int _index = math.max(0, engagementTabs.indexOf(widget.initialTab));
  late final ValueNotifier<double> _page = ValueNotifier<double>(
    _index.toDouble(),
  );

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    // Watching every tab keeps all three lists warm, so a swipe lands on rows
    // that are already there instead of a skeleton.
    final loaded = <EngagementSummary?>[
      for (final tab in engagementTabs)
        ref.watch(
          engagementProvider((
            entity: widget.entity,
            tab: tab,
          )).select((state) => state.loading ? null : state.summary),
        ),
    ];
    final live = ref.watch(interactionProvider(widget.entity));
    final summary = resolveEngagementSummary(
      loaded: loaded,
      selectedIndex: _index,
      seed: EngagementSummary(
        likeCount: live.likeCount,
        repostCount: live.repostCount,
        quoteCount: live.quoteCount,
      ),
    );

    return Column(
      children: <Widget>[
        _EngagementRail(
          page: _page,
          summary: summary,
          selectedIndex: _index,
          onSelected: _select,
        ),
        Expanded(
          child: KTabPager(
            tabs: <KTabPagerTab>[
              for (final tab in engagementTabs)
                KTabPagerTab(id: tab.wire, label: tab.label),
            ],
            selectedIndex: _index,
            showRail: false,
            onSelected: _select,
            onPageProgress: (page) => _page.value = page,
            builder: (context, index) => _EngagementPage(
              entity: widget.entity,
              tab: engagementTabs[index],
            ),
          ),
        ),
      ],
    );
  }
}

({IconData icon, Color tint}) _tabStyle(
  KlectColors colors,
  SocialEngagementTab tab,
) => switch (tab) {
  SocialEngagementTab.like => (
    icon: Icons.favorite_rounded,
    tint: colors.actionLike,
  ),
  SocialEngagementTab.repost => (
    icon: Icons.repeat_rounded,
    tint: colors.actionRepost,
  ),
  SocialEngagementTab.quote => (
    icon: Icons.format_quote_rounded,
    tint: colors.actionComment,
  ),
};

/// Likes · Reposts · Quotes with one indicator that follows the finger.
///
/// No filled boxes: the labels brighten as the pager approaches them and a
/// single capsule glides underneath, morphing between the tabs' action
/// colours.
class _EngagementRail extends StatelessWidget {
  const _EngagementRail({
    required this.page,
    required this.summary,
    required this.selectedIndex,
    required this.onSelected,
  });

  final ValueListenable<double> page;
  final EngagementSummary summary;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _height = Space.s12;
  static const double _indicatorHeight = Space.s1;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: Strokes.thin),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / engagementTabs.length;
          return ValueListenableBuilder<double>(
            valueListenable: page,
            builder: (context, value, _) {
              final position = value.clamp(
                0.0,
                (engagementTabs.length - 1).toDouble(),
              );
              final lower = position.floor();
              final upper = position.ceil();
              final tint = Color.lerp(
                _tabStyle(colors, engagementTabs[lower]).tint,
                _tabStyle(colors, engagementTabs[upper]).tint,
                position - lower,
              )!;
              final geometry = engagementIndicatorGeometry(
                page: position,
                slotWidth: slot,
                length: engagementTabs.length,
              );
              return Stack(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      for (final (index, tab) in engagementTabs.indexed)
                        SizedBox(
                          width: slot,
                          height: _height,
                          child: _RailTab(
                            tab: tab,
                            count: engagementTabCount(summary, tab),
                            selected: index == selectedIndex,
                            progress: (1 - (position - index).abs()).clamp(
                              0.0,
                              1.0,
                            ),
                            onTap: () => onSelected(index),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    left: geometry.left,
                    bottom: 0,
                    width: geometry.width,
                    height: _indicatorHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(Radii.full),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.tab,
    required this.count,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final SocialEngagementTab tab;
  final int count;
  final bool selected;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final label = Color.lerp(
      colors.textTertiary,
      colors.textPrimary,
      progress,
    )!;
    final number = Color.lerp(
      colors.textTertiary,
      colors.textSecondary,
      progress,
    )!;
    return Semantics(
      button: true,
      selected: selected,
      label: '${tab.label}, $count',
      excludeSemantics: true,
      child: KPressable(
        enforceMinTapTarget: false,
        onTap: onTap,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  tab.label,
                  maxLines: 1,
                  style: context.kt.label.copyWith(color: label),
                ),
                const SizedBox(width: Space.s15),
                KRollingCount(
                  value: count,
                  style: context.kt.count.copyWith(color: number),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab's list of accounts.
class _EngagementPage extends ConsumerStatefulWidget {
  const _EngagementPage({required this.entity, required this.tab});

  final EntityRef entity;
  final SocialEngagementTab tab;

  @override
  ConsumerState<_EngagementPage> createState() => _EngagementPageState();
}

class _EngagementPageState extends ConsumerState<_EngagementPage> {
  /// Rows that already played their entrance, so scrolling back past them or
  /// a background refresh never replays it.
  final Set<String> _revealed = <String>{};

  EngagementQuery get _query => (entity: widget.entity, tab: widget.tab);

  EngagementController get _notifier =>
      ref.read(engagementProvider(_query).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(engagementProvider(_query));
    final (String phase, Widget child) = switch (state) {
      EngagementState(loading: true, items: []) => (
        'loading',
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Space.s5,
            vertical: Space.s3,
          ),
          child: KSkeletonList(rows: 7, showMedia: false),
        ),
      ),
      EngagementState(unavailable: true) => (
        'unavailable',
        _scrollableMessage(
          const KEmptyState(
            title: 'Activity unavailable',
            message: 'This content is no longer visible to you.',
            icon: Icons.visibility_off_outlined,
            compact: true,
          ),
        ),
      ),
      EngagementState(error: final KlectError error, items: []) => (
        'error',
        _scrollableMessage(
          KErrorState(error: error, compact: true, onRetry: _notifier.refresh),
        ),
      ),
      EngagementState(items: []) => ('empty', _scrollableMessage(_empty())),
      _ => ('list', _list(state)),
    };

    return AnimatedSwitcher(
      duration: KMotion.duration(context, KDurations.medium),
      switchInCurve: KMotion.curve(context, KCurves.emphasized),
      switchOutCurve: KMotion.curve(context, KCurves.accelerate),
      child: KeyedSubtree(key: ValueKey<String>(phase), child: child),
    );
  }

  Widget _refreshable(Widget scrollable) => RefreshIndicator(
    onRefresh: _notifier.refresh,
    color: context.kc.accentDefault,
    backgroundColor: context.kc.surface2,
    displacement: Space.s8,
    child: scrollable,
  );

  Widget _scrollableMessage(Widget message) => _refreshable(
    ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: Space.s8),
      children: <Widget>[message],
    ),
  );

  Widget _empty() {
    final style = _tabStyle(context.kc, widget.tab);
    return KEmptyState(
      title: switch (widget.tab) {
        SocialEngagementTab.like => 'No likes yet',
        SocialEngagementTab.repost => 'No reposts yet',
        SocialEngagementTab.quote => 'No quotes yet',
      },
      message: switch (widget.tab) {
        SocialEngagementTab.like => 'Accounts that like this will appear here.',
        SocialEngagementTab.repost =>
          'Accounts that repost this will appear here.',
        SocialEngagementTab.quote =>
          'Accounts that quote this will appear here.',
      },
      icon: style.icon,
      compact: true,
    );
  }

  Widget _list(EngagementState state) {
    final items = state.items;
    return _refreshable(
      ListView.builder(
        key: PageStorageKey<String>(
          'engagement:${widget.entity.key}:${widget.tab.wire}',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: Space.s2, bottom: Space.s6),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) return _footer(state);
          final item = items[index];
          final key = engagementItemKey(item);
          final animate = _revealed.add(key);
          final actor = engagementActor(item);
          final profile = actor.profile;
          final row = profile == null
              ? const SizedBox.shrink()
              : _ActorRow(
                  profile: profile,
                  actedAt: actor.actedAt,
                  tab: widget.tab,
                );
          return KReveal(
            key: ValueKey<String>(key),
            animate: animate,
            delay: KMotion.staggerDelay(index, grid: false),
            child: row,
          );
        },
      ),
    );
  }

  Widget _footer(EngagementState state) {
    final error = state.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s3,
          Space.s5,
          Space.s3,
        ),
        child: KInlineError(
          message: error.message,
          onRetry: _notifier.loadMore,
        ),
      );
    }
    if (!state.hasMore) return const SizedBox(height: Space.s4);
    // The footer is built once it scrolls within the cache extent, which is
    // exactly when the next page should start — no button to hunt for.
    if (!state.loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_notifier.loadMore());
      });
    }
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s4),
      child: Center(
        child: SizedBox.square(
          dimension: Space.s5,
          child: CircularProgressIndicator(
            strokeWidth: Strokes.thick,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// One account behind a like, a repost or a quote.
class _ActorRow extends ConsumerWidget {
  const _ActorRow({required this.profile, required this.tab, this.actedAt});

  final Profile profile;
  final DateTime? actedAt;
  final SocialEngagementTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final isSelf = ref.watch(currentUserIdProvider) == profile.id;
    final style = _tabStyle(colors, tab);
    final actedAt = this.actedAt;
    final when = actedAt == null
        ? null
        : timeago.format(actedAt, locale: 'en_short');

    return KPressable(
      onTap: profile.username.isEmpty
          ? null
          : () => context.push(KlectLinks.profilePath(profile.username)),
      onLongPress: () => UserActions.showOverflow(context, profile: profile),
      enforceMinTapTarget: false,
      semanticLabel: [
        profile.name,
        profile.handle,
        if (actedAt != null) timeago.format(actedAt),
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s25,
        ),
        child: Row(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrlOf(api, profile.avatarPath),
                  name: profile.name,
                  size: Space.s12,
                ),
                Positioned(
                  right: -Space.s05,
                  bottom: -Space.s05,
                  child: Container(
                    padding: const EdgeInsets.all(Space.s05),
                    decoration: BoxDecoration(
                      color: colors.surface1,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: Space.s5,
                      height: Space.s5,
                      decoration: BoxDecoration(
                        color: style.tint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        style.icon,
                        size: Space.s3,
                        color: colors.textOnAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          profile.name,
                          style: context.kt.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (profile.isVerified) ...<Widget>[
                        const SizedBox(width: Space.s1),
                        Icon(
                          Icons.verified_rounded,
                          size: Space.s4,
                          color: colors.accentDefault,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    when == null ? profile.handle : '${profile.handle} · $when',
                    style: context.kt.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!isSelf) ...<Widget>[
              const SizedBox(width: Space.s3),
              FollowButton(
                userId: profile.id,
                displayName: profile.name,
                avatarPath: profile.avatarPath,
                followerCount: profile.followerCount,
                size: KButtonSize.small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
