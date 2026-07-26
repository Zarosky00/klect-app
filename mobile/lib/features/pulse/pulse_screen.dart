import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../chat/widgets/messages_action.dart';
import 'data/pulse_feed_controller.dart';
import 'widgets/pulse_card.dart';
import 'widgets/pulse_composer.dart';

/// **Pulse** — the X half of Klect.
///
/// A chronological stream of what the people you follow are posting,
/// reposting and quoting, paged on the `created_at` cursor so new arrivals
/// never shuffle what you are reading. Every row carries the same action bar,
/// the same optimistic engine and the same gesture contract as a Surf tile.
class PulseScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PulseScreen({super.key});

  @override
  ConsumerState<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends ConsumerState<PulseScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.hasContentDimensions &&
        metrics.maxScrollExtent - metrics.pixels < metrics.viewportDimension) {
      unawaited(ref.read(pulseFeedProvider.notifier).loadMore());
    }
    return false;
  }

  Future<void> _refresh() async {
    await ref.read(pulseFeedProvider.notifier).refresh();
    if (!mounted) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _compose() async {
    final published = await PulseComposer.show(context);
    if (!published || !mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(pulseFeedProvider);

    return KScaffold(
      onRefresh: _refresh,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: Layout.bottomBarHeight),
        child: _ComposeButton(onPressed: () => unawaited(_compose())),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            KAppBar(
              title: 'Pulse',
              subtitle: 'From the collectors you follow',
              actions: <Widget>[
                KIconButton(
                  icon: Icons.search_rounded,
                  semanticLabel: 'Search',
                  onPressed: () => context.push(Routes.search),
                ),
                const MessagesAction(),
              ],
            ),
            ..._body(feed),
            const SliverToBoxAdapter(
              child: SizedBox(height: Layout.bottomBarHeight + Space.s16),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(PulseFeedState feed) {
    if (feed.items.isEmpty && feed.loading) {
      return const <Widget>[
        SliverToBoxAdapter(child: KSkeletonList(rows: 4)),
      ];
    }
    if (feed.items.isEmpty && feed.error != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: KErrorState(
            error: feed.error,
            onRetry: () => unawaited(ref.read(pulseFeedProvider.notifier).retry()),
          ),
        ),
      ];
    }
    if (feed.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: KEmptyState(
            title: 'Your Pulse is quiet',
            message: 'Follow a few collectors and everything they add, repost '
                'and say lands here.',
            icon: Icons.bolt_outlined,
            actionLabel: 'Find collectors like you',
            onAction: () => context.push(Routes.matches),
            secondaryActionLabel: 'Share something of yours',
            onSecondaryAction: () => unawaited(_compose()),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverList.builder(
        itemCount: feed.items.length,
        itemBuilder: (context, index) {
          final item = feed.items[index];
          return PulseCard(key: ValueKey<String>(item.key), item: item);
        },
      ),
      SliverToBoxAdapter(child: _footer(feed)),
    ];
  }

  Widget _footer(PulseFeedState feed) {
    final error = feed.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: KInlineError(
          message: error.message,
          onRetry: () =>
              unawaited(ref.read(pulseFeedProvider.notifier).retry()),
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
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s3,
        ),
        decoration: BoxDecoration(
          color: colors.accentDefault,
          borderRadius: BorderRadius.circular(Radii.full),
          boxShadow: KlectTheme.shadow(Elevation.mid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bolt_rounded,
              size: Space.s5,
              color: colors.textOnAccent,
            ),
            const SizedBox(width: Space.s2),
            Text(
              'Share',
              style: context.kt.bodyStrong.copyWith(color: colors.textOnAccent),
            ),
          ],
        ),
      ),
    );
  }
}
