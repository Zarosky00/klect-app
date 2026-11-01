import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Two streams under one glass header: **For you** (ranked discovery,
/// `pulse_feed(p_mode => 'foryou')`) and **Following** (chronological). Each
/// tab keeps its own controller, cursor and scroll position, both paged on
/// `min(sort_at)` so new arrivals never shuffle what you are reading.
///
/// The header floats over the stream and tucks itself away while you read
/// downwards, returning the moment you scroll back up — the stream gets the
/// whole screen. Filters live in a bottom sheet, with the active ones shown
/// as removable chips at the top of the stream.
class PulseScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PulseScreen({super.key});

  @override
  ConsumerState<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends ConsumerState<PulseScreen>
    with SingleTickerProviderStateMixin {
  final Map<PulseMode, ScrollController> _scrolls =
      <PulseMode, ScrollController>{
        for (final mode in PulseMode.values) mode: ScrollController(),
      };

  /// Row keys that already played their entrance, per stream — a row
  /// animates in once, never again when it scrolls back into view.
  final Map<PulseMode, Set<String>> _entered = <PulseMode, Set<String>>{
    for (final mode in PulseMode.values) mode: <String>{},
  };

  late final ValueNotifier<double> _pageProgress;

  /// 0 = header fully shown, 1 = header tucked away above the stream.
  late final AnimationController _chrome;

  @override
  void initState() {
    super.initState();
    _pageProgress = ValueNotifier<double>(
      ref.read(pulseModeProvider).index.toDouble(),
    );
    _chrome = AnimationController(vsync: this, value: 0);
  }

  PulseMode get _mode => ref.read(pulseModeProvider);

  @override
  void dispose() {
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    _chrome.dispose();
    _pageProgress.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────── header motion ──

  /// Follows the finger: every pixel scrolled down tucks the header by a
  /// pixel, every pixel back up returns it. Near the top it can never hide
  /// further than the content has moved, so nothing ever opens a gap.
  void _driveChrome(ScrollUpdateNotification notification) {
    if (KMotion.reduced(context)) return;
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return;
    final pixels = notification.metrics.pixels;
    final ceiling = (pixels / _PulseHeader.height).clamp(0.0, 1.0);
    final next = (_chrome.value + delta / _PulseHeader.height).clamp(
      0.0,
      ceiling,
    );
    if (next == _chrome.value) return;
    if (_chrome.isAnimating) _chrome.stop();
    _chrome.value = next;
  }

  /// When the scroll comes to rest, the header snaps fully in or fully out.
  void _settleChrome(double pixels) {
    final value = _chrome.value;
    if (value == 0 || value == 1) return;
    final target = value > 0.5 && pixels >= _PulseHeader.height ? 1.0 : 0.0;
    unawaited(
      _chrome.animateTo(
        target,
        duration: KMotion.duration(context, KDurations.base),
        curve: KMotion.curve(context, KCurves.emphasized),
      ),
    );
  }

  void _showChrome() {
    if (_chrome.value == 0) return;
    unawaited(
      _chrome.animateTo(
        0,
        duration: KMotion.duration(context, KDurations.medium),
        curve: KMotion.curve(context, KCurves.emphasized),
      ),
    );
  }

  bool _onScroll(ScrollNotification notification, PulseMode mode) {
    // Depth 0 is this page's own list; anything deeper is a nested
    // horizontal scroller (the filter chips) and is not ours to follow.
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      if (metrics.hasContentDimensions &&
          metrics.maxScrollExtent - metrics.pixels <
              metrics.viewportDimension) {
        unawaited(ref.read(pulseFeedProvider(mode).notifier).loadMore());
      }
    }

    if (mode != _mode) return false;
    if (notification is ScrollUpdateNotification) {
      _driveChrome(notification);
    } else if (notification is ScrollEndNotification) {
      _settleChrome(metrics.pixels);
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────── actions ──

  Future<void> _refresh(PulseMode mode) async {
    _entered[mode]!.clear();
    await ref.read(pulseFeedProvider(mode).notifier).refresh();
    if (!mounted) return;
    final scroll = _scrolls[mode]!;
    if (scroll.hasClients) scroll.jumpTo(0);
    _showChrome();
  }

  void _selectMode(PulseMode mode) {
    _pageProgress.value = mode.index.toDouble();
    _showChrome();
    if (mode == _mode) return;
    ref.read(pulseModeProvider.notifier).select(mode);
  }

  Future<void> _compose() async {
    final entry = await PulseComposer.show(context);
    if (entry == null || !mounted) return;
    // The composer prepends into the Following stream — show it landing.
    ref.read(pulseModeProvider.notifier).select(PulseMode.following);
    _showChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scroll = _scrolls[PulseMode.following]!;
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void _openFilters() =>
      unawaited(PulseFilterSheet.show(context, mode: _mode));

  // ───────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
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
      _showChrome();
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: colors.isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: colors.isDark ? Brightness.dark : Brightness.light,
      ),
      child: KScaffold(
        floatingActionButton: _ComposeButton(
          onPressed: () => unawaited(_compose()),
        ),
        body: Stack(
          children: <Widget>[
            Positioned.fill(
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _PulseHeader(
                hide: _chrome,
                pageProgress: _pageProgress,
                selected: mode,
                onSelect: _selectMode,
                activeFilters: filters.activeCount,
                onFilters: _openFilters,
                onSearch: () => unawaited(context.push(Routes.search)),
              ),
            ),
          ],
        ),
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
    final colors = context.kc;
    return RefreshIndicator(
      onRefresh: () => _refresh(mode),
      edgeOffset: _PulseHeader.height,
      color: colors.accentDefault,
      backgroundColor: colors.surface2,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _onScroll(notification, mode),
        child: CustomScrollView(
          key: PageStorageKey<String>('pulse-${mode.wire}'),
          controller: _scrolls[mode],
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            // The glass header floats over this space.
            const SliverToBoxAdapter(
              child: SizedBox(height: _PulseHeader.height),
            ),
            SliverToBoxAdapter(
              child: _PulsePrompt(onPressed: () => unawaited(_compose())),
            ),
            SliverToBoxAdapter(child: _ActiveFilterBar(filters: filters)),
            ..._body(feed, mode, filters, tasteIds),
            // Clears the compose button at the very end of the stream.
            const SliverToBoxAdapter(child: SizedBox(height: Space.s24)),
          ],
        ),
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
                'Loosen the type or time filters — or keep scrolling: '
                'older pages load underneath and may match.',
            icon: Icons.filter_alt_off_outlined,
            actionLabel: 'Clear filters',
            onAction: ref.read(pulseFiltersProvider.notifier).clear,
          ),
        ),
      ];
    }

    final entered = _entered[mode]!;
    return <Widget>[
      SliverList.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          final card = PulseCard(item: item);
          if (item.key == feed.freshKey) {
            // The post the user just composed slides in from above.
            entered.add(item.key);
            return _ComposedEntrance(
              key: ValueKey<String>(item.key),
              child: card,
            );
          }
          // Only the first screenful of a fresh load staggers in; rows met
          // later while scrolling appear instantly, as they should.
          final fresh = entered.add(item.key);
          return _Entrance(
            key: ValueKey<String>(item.key),
            index: index,
            animate: fresh && index <= Stagger.max,
            child: card,
          );
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: Space.s6,
              child: Divider(
                height: Strokes.hairline,
                color: context.kc.borderDefault,
              ),
            ),
            const SizedBox(width: Space.s3),
            Text(
              'You are all caught up',
              style: context.kt.caption.copyWith(
                color: context.kc.textTertiary,
              ),
            ),
            const SizedBox(width: Space.s3),
            SizedBox(
              width: Space.s6,
              child: Divider(
                height: Strokes.hairline,
                color: context.kc.borderDefault,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: Space.s6);
  }
}

extension on PulseFilters {
  /// How many filter dimensions deviate from their defaults.
  int get activeCount =>
      (type != PulseTypeFilter.all ? 1 : 0) +
      (time != PulseTimeFilter.all ? 1 : 0) +
      (sharedTaste ? 1 : 0);
}

// ──────────────────────────────────────────────────────────────── header ──

/// The floating glass header: serif title and actions over a segmented
/// For you | Following switch whose thumb follows the pager's finger.
class _PulseHeader extends StatelessWidget {
  const _PulseHeader({
    required this.hide,
    required this.pageProgress,
    required this.selected,
    required this.onSelect,
    required this.activeFilters,
    required this.onFilters,
    required this.onSearch,
  });

  /// 0 = shown, 1 = tucked away.
  final Animation<double> hide;

  /// The pager's live fractional page.
  final ValueListenable<double> pageProgress;

  final PulseMode selected;
  final ValueChanged<PulseMode> onSelect;

  /// Number of filter dimensions in use — the badge on the tune button.
  final int activeFilters;
  final VoidCallback onFilters;
  final VoidCallback onSearch;

  static const double _titleHeight = Layout.topBarHeight;
  static const double _switchHeight = Space.s10;

  /// Total header height; the stream reserves exactly this much at its top.
  static const double height = _titleHeight + _switchHeight + Space.s3;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final fade = hide.drive(
      Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: const Interval(0, 0.7))),
    );

    final glass = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceGlass,
            border: Border(
              bottom: BorderSide(
                color: colors.borderSubtle,
                width: Strokes.hairline,
              ),
            ),
          ),
          child: SizedBox(
            height: height,
            child: FadeTransition(
              opacity: fade,
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: _titleHeight,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: Space.s4),
                        Text('Pulse', style: text.display3),
                        const Spacer(),
                        KIconButton(
                          icon: Icons.search_rounded,
                          semanticLabel: 'Search',
                          onPressed: onSearch,
                        ),
                        _FilterButton(
                          activeCount: activeFilters,
                          onPressed: onFilters,
                        ),
                        const MessagesAction(),
                        const SizedBox(width: Space.s2),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                    child: ValueListenableBuilder<double>(
                      valueListenable: pageProgress,
                      builder: (context, page, _) => _ModeSwitch(
                        page: page,
                        selected: selected,
                        onSelect: onSelect,
                        height: _switchHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: hide,
      child: glass,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -height * hide.value),
        child: child,
      ),
    );
  }
}

/// The tune button, with a count badge while any filter is in use.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final active = activeCount > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        KIconButton(
          icon: Icons.tune_rounded,
          semanticLabel: active
              ? 'Filters, $activeCount active'
              : 'Filters',
          color: active ? colors.accentHover : colors.textPrimary,
          onPressed: onPressed,
        ),
        Positioned(
          right: Space.s15,
          top: Space.s2,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedScale(
                scale: active ? 1 : 0,
                duration: KMotion.duration(context, KDurations.medium),
                curve: KMotion.curve(context, KCurves.overshoot),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: Space.s4,
                    minHeight: Space.s4,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentDefault,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Text(
                    '${active ? activeCount : 1}',
                    style: context.kt.micro.copyWith(
                      color: colors.textOnAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// For you | Following as one pill. The thumb sits at the pager's live
/// fractional page, so it glides under the finger during a swipe.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.page,
    required this.selected,
    required this.onSelect,
    required this.height,
  });

  final double page;
  final PulseMode selected;
  final ValueChanged<PulseMode> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    const modes = PulseMode.values;
    return Container(
      height: height,
      padding: const EdgeInsets.all(Space.s05),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.borderSubtle, width: Strokes.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / modes.length;
          final position = page.clamp(0.0, (modes.length - 1).toDouble());
          return Stack(
            children: <Widget>[
              Positioned(
                left: slot * position,
                top: 0,
                bottom: 0,
                width: slot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface4,
                    borderRadius: BorderRadius.circular(Radii.full),
                    boxShadow: KlectTheme.shadow(Elevation.low),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (final mode in modes)
                    Expanded(
                      child: _ModeLabel(
                        mode: mode,
                        progress: (1 - (position - mode.index).abs()).clamp(
                          0.0,
                          1.0,
                        ),
                        selected: mode == selected,
                        onTap: () => onSelect(mode),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({
    required this.mode,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final PulseMode mode;
  final double progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final foreground = Color.lerp(
      colors.textTertiary,
      colors.textPrimary,
      progress,
    )!;
    return Semantics(
      selected: selected,
      child: KPressable(
        onTap: onTap,
        enforceMinTapTarget: false,
        semanticLabel: selected ? '${mode.label}, selected' : mode.label,
        child: Center(
          child: Text(
            mode.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.kt.label.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── stream chrome ──

/// A visible entry into conversation so Pulse immediately reads as the place
/// to post, quote and talk — not just another gallery. It scrolls away with
/// the stream instead of pinning itself to the top.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      child: KPressable(
        onTap: onPressed,
        enforceMinTapTarget: false,
        semanticLabel: 'Create a Pulse post',
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Space.s15,
            Space.s15,
            Space.s15,
            Space.s15,
          ),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              KAvatar(imageUrl: avatarUrl, name: profile?.name, size: Space.s8),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  'What is happening on your shelves?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.kt.callout.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: Space.s2),
              Container(
                width: Space.s8,
                height: Space.s8,
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: Space.s4,
                  color: colors.accentHover,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filters in use, as removable chips at the top of the stream.
class _ActiveFilterBar extends ConsumerWidget {
  const _ActiveFilterBar({required this.filters});

  final PulseFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final controller = ref.read(pulseFiltersProvider.notifier);
    final time = switch (filters.time) {
      PulseTimeFilter.today => 'Today',
      PulseTimeFilter.week => 'This week',
      PulseTimeFilter.month => 'This month',
      PulseTimeFilter.all => null,
    };

    final chips = <Widget>[
      if (filters.type != PulseTypeFilter.all)
        KChip(
          label: filters.type.label,
          selected: true,
          dense: true,
          onRemove: () => controller.setType(PulseTypeFilter.all),
        ),
      if (time != null)
        KChip(
          label: time,
          icon: Icons.schedule_rounded,
          selected: true,
          dense: true,
          onRemove: () => controller.setTime(PulseTimeFilter.all),
        ),
      if (filters.sharedTaste)
        KChip(
          label: 'Shared taste',
          icon: Icons.auto_awesome_rounded,
          selected: true,
          dense: true,
          onRemove: controller.toggleSharedTaste,
        ),
    ];

    return AnimatedSize(
      duration: KMotion.duration(context, KDurations.medium),
      curve: KMotion.curve(context, KCurves.emphasized),
      alignment: Alignment.topCenter,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                child: Row(
                  children: <Widget>[
                    for (final chip in chips) ...<Widget>[
                      chip,
                      const SizedBox(width: Space.s2),
                    ],
                    KPressable(
                      onTap: controller.clear,
                      enforceMinTapTarget: false,
                      semanticLabel: 'Clear all filters',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s2,
                          vertical: Space.s1,
                        ),
                        child: Text(
                          'Clear all',
                          style: context.kt.label.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Staggered fade + rise for the first screenful of a stream, capped by
/// [KMotion.staggerDelay] so the whole entrance stays inside the motion
/// ceiling. Decides once, when the row is created, so a row scrolling back
/// into view never replays it.
class _Entrance extends StatefulWidget {
  const _Entrance({
    required this.index,
    required this.animate,
    required this.child,
    super.key,
  });

  final int index;
  final bool animate;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final delay = KMotion.staggerDelay(widget.index, grid: false);
    final total = KDurations.base + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: KCurves.emphasized,
      ),
    );
    unawaited(controller.forward());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null || KMotion.reduced(context)) return widget.child;
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - progress.value) * Space.s4),
          child: child,
        ),
      ),
    );
  }
}

/// The just-composed post sliding down into the top of the stream.
class _ComposedEntrance extends StatelessWidget {
  const _ComposedEntrance({required this.child, super.key});

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
        dimension: Space.s14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentDefault,
            shape: BoxShape.circle,
            border: Border.all(color: colors.accentHover, width: Strokes.thin),
            boxShadow: <BoxShadow>[
              ...KlectTheme.shadow(Elevation.mid),
              ...KlectTheme.shadow(Elevation.glow),
            ],
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
