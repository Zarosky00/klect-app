import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../chat/widgets/messages_action.dart';
import '../shell/root_shell.dart';
import 'data/pulse_feed_controller.dart';
import 'data/pulse_filters.dart';
import 'widgets/pulse_card.dart';
import 'widgets/pulse_composer.dart';
import 'widgets/pulse_filter_drawer.dart';

/// **Pulse** — the X half of Klect.
///
/// Two streams under one segmented header: **For you** (ranked discovery,
/// `pulse_feed(p_mode => 'foryou')`) and **Following** (chronological). Each
/// tab keeps its own controller, cursor and scroll position, both paged on
/// `min(sort_at)` so new arrivals never shuffle what you are reading. Every
/// row carries the same action bar, the same optimistic engine and the same
/// gesture contract as a Surf tile.
class PulseScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PulseScreen({super.key});

  @override
  ConsumerState<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends ConsumerState<PulseScreen> {
  final Map<PulseMode, ScrollController> _scrolls =
      <PulseMode, ScrollController>{
        for (final mode in PulseMode.values) mode: ScrollController(),
      };

  /// Whether the filter drawer is unfolded under the tabs.
  bool _filtersOpen = false;
  late final ValueNotifier<double> _pageProgress;

  @override
  void initState() {
    super.initState();
    _pageProgress = ValueNotifier<double>(
      ref.read(pulseModeProvider).index.toDouble(),
    );
  }

  PulseMode get _mode => ref.read(pulseModeProvider);

  @override
  void dispose() {
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    _pageProgress.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification, PulseMode mode) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.hasContentDimensions &&
        metrics.maxScrollExtent - metrics.pixels < metrics.viewportDimension) {
      unawaited(ref.read(pulseFeedProvider(mode).notifier).loadMore());
    }
    return false;
  }

  Future<void> _refresh([PulseMode? requestedMode]) async {
    final mode = requestedMode ?? _mode;
    await ref.read(pulseFeedProvider(mode).notifier).refresh();
    if (!mounted) return;
    final scroll = _scrolls[mode]!;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void _selectMode(PulseMode mode) {
    _pageProgress.value = mode.index.toDouble();
    if (mode == _mode) return;
    ref.read(pulseModeProvider.notifier).select(mode);
  }

  Future<void> _compose() async {
    final entry = await PulseComposer.show(context);
    if (entry == null || !mounted) return;
    // The composer prepends into the Following stream — show it landing.
    ref.read(pulseModeProvider.notifier).select(PulseMode.following);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scroll = _scrolls[PulseMode.following]!;
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(pulseModeProvider);
    final feeds = <PulseMode, PulseFeedState>{
      for (final candidate in PulseMode.values)
        candidate: ref.watch(pulseFeedProvider(candidate)),
    };
    final filters = ref.watch(pulseFiltersProvider);
    // The matched-collector set only loads once the toggle is first used.
    final tasteIds = filters.sharedTaste
        ? ref.watch(matchedCollectorIdsProvider).value
        : null;

    ref.listen<RootTabReselectEvent?>(rootTabReselectProvider, (_, event) {
      if (event?.index != 1) return;
      final scroll = _scrolls[mode]!;
      if (!scroll.hasClients) return;
      unawaited(
        scroll.animateTo(
          0,
          duration: KMotion.duration(context, KDurations.medium),
          curve: KMotion.curve(context, KCurves.emphasized),
        ),
      );
    });

    return KScaffold(
      onRefresh: _refresh,
      appBar: KFixedAppBar(
        title: 'Pulse',
        actions: <Widget>[
          KIconButton(
            icon: Icons.search_rounded,
            semanticLabel: 'Search',
            onPressed: () => context.push(Routes.search),
          ),
          const MessagesAction(),
        ],
      ),
      floatingActionButton: _ComposeButton(
        onPressed: () => unawaited(_compose()),
      ),
      body: Column(
        children: <Widget>[
          ValueListenableBuilder<double>(
            valueListenable: _pageProgress,
            builder: (context, page, _) => _PulseTabs(
              selected: mode,
              pageProgress: page,
              onSelect: _selectMode,
              filtersOpen: _filtersOpen,
              filtersActive: filters.isActive,
              onToggleFilters: () =>
                  setState(() => _filtersOpen = !_filtersOpen),
            ),
          ),
          _PulsePrompt(onPressed: () => unawaited(_compose())),
          AnimatedSize(
            duration: KMotion.duration(context, KDurations.medium),
            curve: KMotion.curve(context, KCurves.emphasized),
            alignment: Alignment.topCenter,
            child: _filtersOpen
                ? const PulseFilterDrawer()
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: KTabPager(
              tabs: <KTabPagerTab>[
                for (final candidate in PulseMode.values)
                  KTabPagerTab(id: candidate.wire, label: candidate.label),
              ],
              selectedIndex: mode.index,
              onSelected: (index) => _selectMode(PulseMode.values[index]),
              onPageProgress: (page) => _pageProgress.value = page,
              showRail: false,
              builder: (context, index) => _page(
                context,
                PulseMode.values[index],
                feeds[PulseMode.values[index]]!,
                filters,
                tasteIds,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(
    BuildContext context,
    PulseMode mode,
    PulseFeedState feed,
    PulseFilters filters,
    Set<String>? tasteIds,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) => _onScroll(notification, mode),
      child: CustomScrollView(
        key: PageStorageKey<String>('pulse-${mode.wire}'),
        controller: _scrolls[mode],
        slivers: <Widget>[
          ..._body(feed, mode, filters, tasteIds),
          const SliverToBoxAdapter(child: SizedBox(height: Space.s16)),
        ],
      ),
    );
  }

  List<Widget> _body(
    PulseFeedState feed,
    PulseMode mode,
    PulseFilters filters,
    Set<String>? tasteIds,
  ) {
    if (feed.items.isEmpty && feed.loading) {
      return const <Widget>[SliverToBoxAdapter(child: KSkeletonList(rows: 4))];
    }
    if (feed.items.isEmpty && feed.error != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: KErrorState(
            error: feed.error,
            onRetry: () =>
                unawaited(ref.read(pulseFeedProvider(mode).notifier).retry()),
          ),
        ),
      ];
    }
    if (feed.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: mode == PulseMode.foryou
              ? KEmptyState(
                  title: 'Nothing to rank yet',
                  message:
                      'For-you learns from what you like, save and '
                      'collect. Surf a little and this feed starts thinking.',
                  icon: Icons.auto_awesome_outlined,
                  actionLabel: 'Go surf',
                  onAction: () => context.go('/surf'),
                  secondaryActionLabel: 'Share something of yours',
                  onSecondaryAction: () => unawaited(_compose()),
                )
              : KEmptyState(
                  title: 'Your Pulse is quiet',
                  message:
                      'Follow a few collectors and everything they add, '
                      'repost and say lands here.',
                  icon: Icons.bolt_outlined,
                  actionLabel: 'Find collectors like you',
                  onAction: () => context.push(Routes.matches),
                  secondaryActionLabel: 'Share something of yours',
                  onSecondaryAction: () => unawaited(_compose()),
                ),
        ),
      ];
    }

    // Type / Time / shared-taste are client-side filters over the fetched
    // pages — the stream keeps paging normally underneath them.
    final visible = filters.apply(feed.items, tasteIds);
    if (visible.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: KEmptyState(
            title: 'Nothing matches those filters',
            message:
                'Loosen the Type or Time filters — or keep scrolling: '
                'older pages load underneath and may match.',
            icon: Icons.filter_alt_off_outlined,
            actionLabel: 'Clear filters',
            onAction: ref.read(pulseFiltersProvider.notifier).clear,
          ),
        ),
      ];
    }

    return <Widget>[
      SliverList.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          final card = PulseCard(key: ValueKey<String>(item.key), item: item);
          if (item.key == feed.freshKey) {
            // The post the user just composed slides in from above.
            return _ComposedEntrance(child: card);
          }
          return _Entrance(index: index, child: card);
        },
      ),
      SliverToBoxAdapter(child: _footer(feed, mode)),
    ];
  }

  Widget _footer(PulseFeedState feed, PulseMode mode) {
    final error = feed.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: KInlineError(
          message: error.message,
          onRetry: () =>
              unawaited(ref.read(pulseFeedProvider(mode).notifier).retry()),
        ),
      );
    }
    if (feed.loadingMore) {
      return const KSkeletonList(rows: 2);
    }
    if (!feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Center(
          child: Text(
            'That is everything for now',
            style: context.kt.caption.copyWith(color: context.kc.textTertiary),
          ),
        ),
      );
    }
    return const SizedBox(height: Space.s6);
  }
}

/// The For-you ▸ Following segmented control, pinned under the serif title,
/// with the filter-drawer toggle on the trailing edge.
class _PulseTabs extends StatelessWidget implements PreferredSizeWidget {
  const _PulseTabs({
    required this.selected,
    required this.pageProgress,
    required this.onSelect,
    required this.filtersOpen,
    required this.filtersActive,
    required this.onToggleFilters,
  });

  final PulseMode selected;
  final double pageProgress;
  final void Function(PulseMode) onSelect;

  /// Whether the drawer is currently unfolded.
  final bool filtersOpen;

  /// Whether any filter deviates from the defaults — shows the accent dot.
  final bool filtersActive;

  /// Unfolds / folds the drawer.
  final VoidCallback onToggleFilters;

  @override
  Size get preferredSize => const Size.fromHeight(Space.s12);

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgBase,
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
      ),
      child: SizedBox(
        height: Space.s12,
        child: Row(
          children: <Widget>[
            for (final mode in PulseMode.values)
              Expanded(
                child: _PulseTab(
                  mode: mode,
                  selected:
                      mode == selected ||
                      (1 - (pageProgress - mode.index).abs()) >= 0.5,
                  selectionProgress: (1 - (pageProgress - mode.index).abs())
                      .clamp(0.0, 1.0),
                  onSelect: onSelect,
                ),
              ),
            SizedBox(
              width: Space.s12,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: <Widget>[
                  KIconButton(
                    icon: filtersOpen
                        ? Icons.tune_rounded
                        : Icons.tune_outlined,
                    semanticLabel: filtersOpen
                        ? 'Hide filters'
                        : 'Show filters',
                    color: filtersOpen || filtersActive
                        ? colors.accentDefault
                        : colors.textSecondary,
                    onPressed: onToggleFilters,
                  ),
                  if (filtersActive)
                    Positioned(
                      top: Space.s1,
                      right: Space.s1,
                      child: IgnorePointer(
                        child: Container(
                          width: Space.s2,
                          height: Space.s2,
                          decoration: BoxDecoration(
                            color: colors.accentDefault,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseTab extends StatelessWidget {
  const _PulseTab({
    required this.mode,
    required this.selected,
    required this.selectionProgress,
    required this.onSelect,
  });

  final PulseMode mode;
  final bool selected;
  final double selectionProgress;
  final void Function(PulseMode) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final foreground = Color.lerp(
      colors.textSecondary,
      colors.textPrimary,
      selectionProgress,
    )!;
    return KPressable(
      onTap: () => onSelect(mode),
      enforceMinTapTarget: false,
      semanticLabel: selected ? '${mode.label}, selected' : mode.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Center(
              child: Text(
                mode.label,
                style: context.kt.label.copyWith(color: foreground),
              ),
            ),
          ),
          AnimatedContainer(
            duration: KMotion.duration(context, KDurations.fast),
            curve: KMotion.curve(context, KCurves.emphasized),
            width: Space.s8 * selectionProgress,
            height: Strokes.thick,
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                colors.accentDefault,
                selectionProgress,
              ),
              borderRadius: BorderRadius.circular(Radii.full),
            ),
          ),
        ],
      ),
    );
  }
}

/// A visible entry into conversation so Pulse immediately reads as the place
/// to post, quote and talk â€” not just another gallery.
class _PulsePrompt extends ConsumerWidget {
  const _PulsePrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final profile = ref.watch(myProfileProvider).value;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(profile?.avatarPath, bucket: StorageBucket.avatars);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle,
            width: Strokes.hairline,
          ),
        ),
      ),
      child: KPressable(
        onTap: onPressed,
        enforceMinTapTarget: false,
        semanticLabel: 'Create a Pulse post',
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: <Widget>[
              KAvatar(imageUrl: avatarUrl, name: profile?.name, size: Space.s8),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  'What is happening on your shelves?',
                  style: context.kt.body.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: Space.s2),
              Icon(
                Icons.image_outlined,
                size: Space.s5,
                color: colors.accentDefault,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered fade + rise for stream rows, capped by [KMotion.staggerDelay] so
/// a long feed never feels slow further down. Same pattern as the inbox.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (KMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KDurations.base + KMotion.staggerDelay(index, grid: false),
      curve: Curves_.emphasized,
      builder: (context, t, inner) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * Space.s3),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

/// The just-composed post sliding down into the top of the stream.
class _ComposedEntrance extends StatelessWidget {
  const _ComposedEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (KMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KDurations.medium,
      curve: Curves_.emphasized,
      builder: (context, t, inner) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (t - 1) * Space.s8),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onPressed,
      semanticLabel: 'Share something to Pulse',
      enforceMinTapTarget: false,
      child: SizedBox.square(
        dimension: Space.s12,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentDefault,
            shape: BoxShape.circle,
            boxShadow: KlectTheme.shadow(Elevation.mid),
          ),
          child: Icon(
            Icons.edit_rounded,
            size: Space.s6,
            color: colors.textOnAccent,
          ),
        ),
      ),
    );
  }
}
