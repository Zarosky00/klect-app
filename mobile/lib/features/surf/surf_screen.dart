import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../chat/widgets/messages_action.dart';
import 'data/surf_feed_controller.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/surf_tile.dart';

/// **Surf** — the Pinterest grid, and the front door of the product.
///
/// Everything here exists to keep a fling at 60fps+ through hundreds of tiles:
///
///  * every tile's box is reserved from the feed's intrinsic `width`/`height`
///    before the photo loads, so the grid can never reflow;
///  * `KMasonryGrid` is a real sliver, so children build lazily and get free
///    repaint boundaries;
///  * images are decoded at the column width, so memory stays flat;
///  * the quiet chrome is driven by a `ValueListenable`, so a scroll rebuilds
///    the overlay and not the grid;
///  * nothing in `build()` does work — the aspect list is precomputed by the
///    controller when the page arrives.
class SurfScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SurfScreen({super.key});

  @override
  ConsumerState<SurfScreen> createState() => _SurfScreenState();
}

class _SurfScreenState extends ConsumerState<SurfScreen> {
  /// How many viewports of tiles to keep built ahead of the fling. Not a
  /// design value — a memory/jank trade-off.
  static const double _cacheViewports = 1.5;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _revealed = ValueNotifier<bool>(true);

  Timer? _idleTimer;
  DateTime _pageStamp = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _idleTimer?.cancel();
    _revealed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  SurfFilter get _filter => ref.read(surfFilterProvider);

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _idleTimer?.cancel();
      _revealed.value = false;
    } else if (notification is ScrollEndNotification) {
      _idleTimer?.cancel();
      _idleTimer = Timer(KDurations.medium, () {
        if (mounted) _revealed.value = true;
      });
    }

    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.hasContentDimensions &&
          metrics.maxScrollExtent - metrics.pixels <
              metrics.viewportDimension) {
        unawaited(ref.read(surfFeedProvider(_filter).notifier).loadMore());
      }
    }
    return false;
  }

  Future<void> _refresh() async {
    await ref.read(surfFeedProvider(_filter).notifier).refresh();
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _revealed.value = true;
  }

  void _selectFilter(SurfFilter filter) {
    if (filter == _filter) return;
    ref.read(surfFilterProvider.notifier).select(filter);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _revealed.value = true;
  }

  /// `-1` means "do not animate": either the tile belongs to an older page, or
  /// it is being built long after that page landed (i.e. mid-fling).
  int _staggerFor(int index, int anchor) {
    if (DateTime.now().difference(_pageStamp) > KDurations.deliberate) {
      return -1;
    }
    if (index < anchor) return -1;
    return index - anchor;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(surfFilterProvider);
    final feed = ref.watch(surfFeedProvider(filter));

    ref.listen<SurfFeedState>(surfFeedProvider(filter), (previous, next) {
      if (next.cards.length != (previous?.cards.length ?? 0)) {
        _pageStamp = DateTime.now();
      }
    });

    final media = MediaQuery.of(context);
    final columns = Layout.masonryColumns(media.size.width);
    const gutter = Layout.masonryGutter;
    final columnWidth =
        (media.size.width - gutter * (columns + 1)) / columns;
    final decodeWidth = (columnWidth * media.devicePixelRatio).round();

    return KScaffold(
      onRefresh: _refresh,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          controller: _scroll,
          scrollCacheExtent:
              const ScrollCacheExtent.viewport(_cacheViewports),
          slivers: <Widget>[
            KAppBar(
              title: 'Surf',
              subtitle: 'Collections, shelves and things',
              // Room for the serif title to collapse into the toolbar with the
              // filter row pinned underneath it.
              expandedHeight: Space.s24 + Space.s12,
              actions: <Widget>[
                KIconButton(
                  icon: Icons.auto_awesome_outlined,
                  semanticLabel: 'Collectors like you',
                  onPressed: () => context.push(Routes.matches),
                ),
                KIconButton(
                  icon: Icons.search_rounded,
                  semanticLabel: 'Search',
                  onPressed: () => context.push(Routes.search),
                ),
                const MessagesAction(),
              ],
              bottom: _FilterBar(
                selected: filter,
                onSelect: _selectFilter,
              ),
            ),
            ..._bodySlivers(context, feed, columns, decodeWidth),
            // The shell's tab bar floats over the body (`extendBody`), so the
            // last row of tiles needs to clear it.
            const SliverToBoxAdapter(
              child: SizedBox(height: Layout.bottomBarHeight + Space.s8),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _bodySlivers(
    BuildContext context,
    SurfFeedState feed,
    int columns,
    int decodeWidth,
  ) {
    if (feed.cards.isEmpty && feed.loading) {
      return const <Widget>[
        SliverToBoxAdapter(child: KSkeletonGrid(tiles: 10)),
      ];
    }
    if (feed.cards.isEmpty && feed.error != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: KErrorState(
            error: feed.error,
            onRetry: () =>
                unawaited(ref.read(surfFeedProvider(feed.filter).notifier).retry()),
          ),
        ),
      ];
    }
    if (feed.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyState(context, feed.filter),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.all(Layout.masonryGutter),
        sliver: KMasonryGrid(
          aspects: feed.aspects,
          columns: columns,
          itemBuilder: (context, index) {
            if (index >= feed.cards.length) return null;
            final card = feed.cards[index];
            return SurfTile(
              key: ValueKey<String>(card.key),
              card: card,
              revealed: _revealed,
              decodeWidth: decodeWidth,
              staggerIndex: _staggerFor(index, feed.pageAnchor),
            );
          },
        ),
      ),
      SliverToBoxAdapter(child: _footer(feed)),
    ];
  }

  Widget _emptyState(BuildContext context, SurfFilter filter) => switch (filter) {
        SurfFilter.following => KEmptyState(
            title: 'Nothing from your circle yet',
            message: 'Follow a few collectors and their shelves will surface '
                'here first.',
            icon: Icons.people_outline_rounded,
            actionLabel: 'Find collectors like you',
            onAction: () => context.push(Routes.matches),
            secondaryActionLabel: 'Browse everything',
            onSecondaryAction: () => _selectFilter(SurfFilter.all),
          ),
        SurfFilter.items => KEmptyState(
            title: 'No things yet',
            message: 'Add your first item and the grid fills itself.',
            icon: Icons.inventory_2_outlined,
            actionLabel: 'Add an item',
            onAction: () => context.push('/create/item'),
          ),
        SurfFilter.collections => KEmptyState(
            title: 'No shelves yet',
            message: 'Start a collection and give your things a home.',
            icon: Icons.collections_bookmark_outlined,
            actionLabel: 'Start a collection',
            onAction: () => context.push('/create/collection'),
          ),
        SurfFilter.all => KEmptyState(
            title: 'The grid is empty',
            message: 'Nothing is public yet. Be the first — start a '
                'collection and put something on it.',
            icon: Icons.grid_view_rounded,
            actionLabel: 'Start a collection',
            onAction: () => context.push('/create/collection'),
          ),
      };

  Widget _footer(SurfFeedState feed) {
    final error = feed.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: KInlineError(
          message: error.message,
          onRetry: () =>
              unawaited(ref.read(surfFeedProvider(feed.filter).notifier).retry()),
        ),
      );
    }
    if (feed.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: Layout.masonryGutter),
        child: KSkeletonGrid(tiles: 4),
      );
    }
    if (!feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s8),
        child: Center(
          child: Text(
            'You have reached the end of the shelf',
            style: context.kt.caption.copyWith(color: context.kc.textTertiary),
          ),
        ),
      );
    }
    return const SizedBox(height: Space.s6);
  }
}

class _FilterBar extends StatelessWidget implements PreferredSizeWidget {
  const _FilterBar({required this.selected, required this.onSelect});

  final SurfFilter selected;
  final void Function(SurfFilter) onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(Space.s12);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: Space.s12,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s2,
          ),
          children: <Widget>[
            for (final filter in SurfFilter.values) ...<Widget>[
              KChip(
                label: filter.label,
                selected: filter == selected,
                onTap: () => onSelect(filter),
              ),
              const SizedBox(width: Space.s2),
            ],
          ],
        ),
      );
}
