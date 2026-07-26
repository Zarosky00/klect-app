import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'data/closeup_providers.dart';
import 'widgets/closeup_sections.dart';
import 'widgets/comment_thread.dart';
import 'widgets/entity_gesture_card.dart';
import 'widgets/masonry_grid.dart';
import 'widgets/peek_menu.dart';
import 'widgets/surf_tile.dart';

/// **Closeup** — the single-tap destination, driven by `get_closeup`.
///
/// The photo fills the top of the screen and a sheet rides over it from 55% to
/// full. Dragging the sheet's header down past a threshold (or flinging it)
/// slides the sheet away to reveal the whole photograph and then pops the
/// route, which is what flies the shared-element hero back onto the Surf tile
/// it came from.
///
/// One class serves all four levels — item, subcollection, collection and post
/// — because the symmetry is the product: every level gets the same action
/// bar, the same live counts and the same comment thread.
class CloseupScreen extends ConsumerStatefulWidget {
  /// Creates the closeup for one entity.
  const CloseupScreen({
    required this.entityType,
    required this.entityId,
    super.key,
  });

  /// Which level this is.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  @override
  ConsumerState<CloseupScreen> createState() => _CloseupScreenState();
}

class _CloseupScreenState extends ConsumerState<CloseupScreen>
    with SingleTickerProviderStateMixin {
  /// Sheet at rest: 55% of the screen, per `docs/DESIGN_SYSTEM.md` §5.
  static const double _restExtent = 0.55;

  /// Sheet fully open.
  static const double _fullExtent = 1;

  /// How far below its rest position the sheet must travel before releasing
  /// dismisses instead of springing back. A gesture threshold, not a design
  /// value.
  static const double _dismissFraction = 0.16;

  /// Downward fling speed (logical px/s) that dismisses regardless of travel.
  static const double _flingVelocity = 700;

  final DraggableScrollableController _sheet = DraggableScrollableController();
  final PageController _cover = PageController();
  final FocusNode _composerFocus = FocusNode();
  final GlobalKey _commentsAnchor = GlobalKey();

  late final AnimationController _dismiss =
      AnimationController.unbounded(vsync: this);

  int _mediaIndex = 0;
  bool _closing = false;

  EntityRef get _entity => EntityRef(widget.entityType, widget.entityId);

  @override
  void initState() {
    super.initState();
    // `record_view` is deduped per viewer per day server-side, so firing it on
    // every open is both correct and cheap.
    unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
  }

  @override
  void dispose() {
    _dismiss.dispose();
    _composerFocus.dispose();
    _cover.dispose();
    _sheet.dispose();
    super.dispose();
  }

  double get _screenHeight => MediaQuery.sizeOf(context).height;

  void _onHeaderDrag(DragUpdateDetails details) {
    final height = _screenHeight;
    if (height <= 0) return;

    if (_dismiss.value > 0) {
      final next = _dismiss.value + details.delta.dy;
      _dismiss.value = next < 0 ? 0 : next;
      return;
    }

    final size = _sheet.isAttached ? _sheet.size : _restExtent;
    final next = size - details.delta.dy / height;
    if (next < _restExtent) {
      if (_sheet.isAttached) _sheet.jumpTo(_restExtent);
      _dismiss.value = (_restExtent - next) * height;
    } else if (_sheet.isAttached) {
      _sheet.jumpTo(next.clamp(_restExtent, _fullExtent));
    }
  }

  void _onHeaderDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final height = _screenHeight;

    if (_dismiss.value > height * _dismissFraction ||
        (_dismiss.value > 0 && velocity > _flingVelocity)) {
      _close();
      return;
    }

    if (_dismiss.value > 0) {
      // Velocity carry: the spring inherits the finger's speed instead of
      // starting from rest, so a flick that does not quite dismiss still feels
      // like one continuous movement.
      _dismiss.animateWith(
        SpringSimulation(
          KMotion.spring(Springs.sheet),
          _dismiss.value,
          0,
          velocity,
        ),
      );
      return;
    }

    if (!_sheet.isAttached) return;
    final size = _sheet.size;
    final target = velocity < -_flingVelocity
        ? _fullExtent
        : velocity > _flingVelocity
            ? _restExtent
            : (size > (_restExtent + _fullExtent) / 2
                ? _fullExtent
                : _restExtent);
    unawaited(
      _sheet.animateTo(
        target,
        duration: KMotion.duration(context, KDurations.medium),
        curve: KMotion.curve(context, KCurves.emphasized),
      ),
    );
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/surf');
    }
  }

  void _openImmersive(int index) {
    context.push(
      '${KlectLinks.immersivePath(widget.entityType, widget.entityId)}?i=$index',
    );
  }

  void _openComments() {
    if (_sheet.isAttached) {
      unawaited(
        _sheet.animateTo(
          _fullExtent,
          duration: KMotion.duration(context, KDurations.medium),
          curve: KMotion.curve(context, KCurves.emphasized),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _commentsAnchor.currentContext;
      if (anchor != null) {
        unawaited(
          Scrollable.ensureVisible(
            anchor,
            duration: KMotion.duration(context, KDurations.medium),
            curve: KMotion.curve(context, KCurves.emphasized),
          ),
        );
      }
      _composerFocus.requestFocus();
    });
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(
        text: KlectLinks.urlFor(widget.entityType, widget.entityId),
      ),
    );
    if (!mounted) return;
    KToast.success(context, 'Link copied');
  }

  Future<void> _block(Closeup closeup) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Block ${closeup.owner.handle}?',
      message: 'You will stop seeing each other entirely — content, messages '
          'and notifications.',
      confirmLabel: 'Block',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(klectApiProvider).blockUser(closeup.owner.id);
      if (!mounted) return;
      KToast.success(context, 'Blocked ${closeup.owner.handle}');
      _close();
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _showOverflow(Closeup closeup) => KSheet.show<void>(
        context: context,
        title: closeup.title.isEmpty ? 'Options' : closeup.title,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _OverflowAction(
              icon: Icons.link_rounded,
              label: 'Copy link',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_copyLink());
              },
            ),
            _OverflowAction(
              icon: Icons.fullscreen_rounded,
              label: 'Open fullscreen',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openImmersive(_mediaIndex);
              },
            ),
            _OverflowAction(
              icon: Icons.flag_outlined,
              label: 'Report',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  KReportSheet.showForEntity(
                    context,
                    type: widget.entityType,
                    entityId: widget.entityId,
                    subjectLabel: closeup.title,
                  ),
                );
              },
            ),
            if (!closeup.viewer.isOwner && closeup.owner.id.isNotEmpty)
              _OverflowAction(
                icon: Icons.block_rounded,
                label: 'Block ${closeup.owner.handle}',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_block(closeup));
                },
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final entity = _entity;
    final async = ref.watch(closeupProvider(entity));

    ref.listen<AsyncValue<Closeup>>(closeupProvider(entity), (previous, next) {
      final data = next.value;
      if (data == null) return;
      // Beat any controller the Surf grid already created, so the sheet shows
      // the authoritative counts instead of the feed row's older snapshot.
      ref.read(interactionProvider(entity).notifier).hydrateFromCloseup(data);
    });

    final closeup = async.value;
    return KScaffold(
      safeTop: false,
      safeBottom: false,
      backgroundColor: context.kc.bgSunken,
      body: closeup != null
          ? _content(closeup)
          : async.hasError
              ? KErrorState(
                  error: async.error,
                  onRetry: () => ref.invalidate(closeupProvider(entity)),
                )
              : const _CloseupSkeleton(),
    );
  }

  Widget _content(Closeup closeup) {
    final media = immersiveMediaOf(closeup);
    final topInset = MediaQuery.paddingOf(context).top;
    final colors = context.kc;

    return LayoutBuilder(
      builder: (context, constraints) {
        final coverHeight =
            constraints.maxHeight * (1 - _restExtent) + Radii.s2xl;
        return Stack(
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: coverHeight,
              child: _CoverPager(
                entity: _entity,
                media: media,
                controller: _cover,
                title: closeup.title,
                onIndexChanged: (index) => setState(() => _mediaIndex = index),
                onOpen: _openImmersive,
              ),
            ),
            Positioned.fill(
              child: DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: _restExtent,
                minChildSize: _restExtent,
                maxChildSize: _fullExtent,
                snap: true,
                // The sheet's rest position *is* its minimum, so the framework
                // must not read "collapsed" as "dismiss" — dismissal is the
                // header drag, which tracks the finger and carries velocity.
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) => AnimatedBuilder(
                  animation: _dismiss,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _dismiss.value),
                    child: child,
                  ),
                  child: _SheetSurface(
                    header: _header(closeup),
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: _slivers(closeup),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset + Space.s2,
              left: Space.s4,
              right: Space.s4,
              child: Row(
                children: <Widget>[
                  KIconButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: 'Back',
                    color: colors.textPrimary,
                    background: colors.surfaceGlass,
                    onPressed: _close,
                  ),
                  const Spacer(),
                  KIconButton(
                    icon: Icons.more_horiz_rounded,
                    semanticLabel: 'More options',
                    color: colors.textPrimary,
                    background: colors.surfaceGlass,
                    onPressed: () => unawaited(_showOverflow(closeup)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(Closeup closeup) {
    final colors = context.kc;
    final text = context.kt;
    final subtitle = switch (closeup.entityType) {
      EntityType.item => closeup.item?.brand,
      EntityType.subcollection =>
        '${formatCount(closeup.subcollection?.itemCount ?? 0)} things',
      EntityType.collection =>
        '${formatCount(closeup.collection?.subcollectionCount ?? 0)} shelves · '
            '${formatCount(closeup.collection?.itemCount ?? 0)} things',
      _ => null,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onHeaderDrag,
      onVerticalDragEnd: _onHeaderDragEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: Space.s25, bottom: Space.s2),
            child: Center(
              child: Container(
                width: Space.s10,
                height: Space.s1,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s0,
              Space.s5,
              Space.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CloseupBreadcrumbRow(breadcrumb: closeup.breadcrumb),
                const SizedBox(height: Space.s1),
                Text(
                  closeup.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.display3,
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
        ],
      ),
    );
  }

  List<Widget> _slivers(Closeup closeup) {
    final entity = _entity;
    final description = closeup.description;
    final item = closeup.item;

    return <Widget>[
      _box(
        KActionBar(
          entity: entity,
          seed: InteractionState.fromCloseup(closeup),
          live: true,
          showViews: true,
          shareTitle: closeup.title,
          onComment: _openComments,
        ),
        top: Space.s4,
      ),
      if (description != null && description.isNotEmpty)
        _box(Text(description, style: context.kt.body)),
      if (item != null) _box(CloseupMetadata(item: item)),
      if (closeup.tags.isNotEmpty) _box(CloseupTags(tags: closeup.tags)),
      _box(CloseupOwnerRow(closeup: closeup), top: Space.s5),
      ..._children(closeup),
      _box(
        CloseupSectionHeader(key: _commentsAnchor, title: 'Comments'),
        top: Space.s6,
      ),
      _box(CommentThread(entity: entity, focusNode: _composerFocus)),
      SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.viewInsetsOf(context).bottom + Space.s16,
        ),
      ),
    ];
  }

  List<Widget> _children(Closeup closeup) {
    switch (closeup.entityType) {
      case EntityType.item:
        if (closeup.siblings.isEmpty) return const <Widget>[];
        return <Widget>[
          _box(
            const CloseupSectionHeader(title: 'More on this shelf'),
            top: Space.s6,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: CloseupItemStrip(items: closeup.siblings),
            ),
          ),
        ];
      case EntityType.subcollection:
        if (closeup.items.isEmpty) return const <Widget>[];
        return <Widget>[
          _box(const CloseupSectionHeader(title: 'Things'), top: Space.s6),
          _itemsGrid(closeup.items),
        ];
      case EntityType.collection:
        return <Widget>[
          if (closeup.subcollections.isNotEmpty) ...<Widget>[
            _box(const CloseupSectionHeader(title: 'Shelves'), top: Space.s6),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.s3),
                child: CloseupSubcollectionRail(
                  subcollections: closeup.subcollections,
                ),
              ),
            ),
          ],
          if (closeup.items.isNotEmpty) ...<Widget>[
            _box(const CloseupSectionHeader(title: 'Things'), top: Space.s6),
            _itemsGrid(closeup.items),
          ],
        ];
      case EntityType.post:
      case EntityType.comment:
        return const <Widget>[];
    }
  }

  Widget _itemsGrid(List<CloseupItemRef> items) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s3,
          Space.s5,
          Space.s0,
        ),
        sliver: KMasonryGrid(
          aspects: <double>[
            for (final item in items)
              (item.aspect ?? Aspect.cover)
                  .clamp(Aspect.gridMin, Aspect.gridMax),
          ],
          itemBuilder: (context, index) =>
              index < items.length ? _ChildItemTile(item: items[index]) : null,
        ),
      );

  Widget _box(Widget child, {double top = Space.s3}) => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(Space.s5, top, Space.s5, Space.s0),
          child: child,
        ),
      );
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    const shape = BorderRadius.vertical(top: Radius.circular(Radii.s2xl));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: shape,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
        boxShadow: KlectTheme.shadow(Elevation.high),
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[header, Expanded(child: child)],
        ),
      ),
    );
  }
}

class _CoverPager extends ConsumerWidget {
  const _CoverPager({
    required this.entity,
    required this.media,
    required this.controller,
    required this.title,
    required this.onIndexChanged,
    required this.onOpen,
  });

  final EntityRef entity;
  final List<ImmersiveMedia> media;
  final PageController controller;
  final String title;
  final ValueChanged<int> onIndexChanged;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(klectApiProvider);
    final colors = context.kc;
    final pages = media.isEmpty ? 1 : media.length;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        PageView.builder(
          controller: controller,
          itemCount: pages,
          onPageChanged: onIndexChanged,
          itemBuilder: (context, index) {
            final photo = media.isEmpty ? null : media[index];
            final url = api.publicUrl(photo?.path);
            return KPressable(
              enforceMinTapTarget: false,
              semanticLabel: 'Open $title fullscreen',
              onTap: () => onOpen(index),
              onLongPress: () => unawaited(
                KPeekMenu.show(
                  context,
                  entity: entity,
                  title: title,
                  imageUrl: url,
                  blurhash: photo?.blurhash,
                  aspectRatio: photo?.aspect,
                ),
              ),
              child: KBlurhashImage(
                url: url,
                blurhash: photo?.blurhash,
                semanticLabel: photo?.altText ?? title,
                borderRadius: BorderRadius.zero,
                heroTag: index == 0
                    ? surfCoverHeroTag(entity.type, entity.id)
                    : null,
              ),
            );
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: Space.s24,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    colors.surfaceScrim,
                    colors.surfaceScrim.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (pages > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: Radii.s2xl + Space.s3,
            child: IgnorePointer(
              child: _PageDots(controller: controller, count: pages),
            ),
          ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.page != null
            ? controller.page!.round()
            : controller.initialPage;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (var index = 0; index < count; index++)
              Container(
                width: index == page ? Space.s4 : Space.s15,
                height: Space.s15,
                margin: const EdgeInsets.symmetric(horizontal: Space.s05),
                decoration: BoxDecoration(
                  color:
                      index == page ? colors.accentDefault : colors.textTertiary,
                  borderRadius: BorderRadius.circular(Radii.full),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChildItemTile extends ConsumerWidget {
  const _ChildItemTile({required this.item});

  final CloseupItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(klectApiProvider).publicUrl(item.coverPath);
    final colors = context.kc;
    return KEntityGestureCard(
      entity: EntityRef.item(item.id),
      title: item.title,
      imageUrl: url,
      blurhash: item.coverBlurhash,
      aspectRatio: item.aspect,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          KBlurhashImage(
            url: url,
            blurhash: item.coverBlurhash,
            semanticLabel: item.title,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          Positioned(
            left: Space.s2,
            right: Space.s2,
            bottom: Space.s2,
            child: IgnorePointer(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.kt.micro.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverflowAction extends StatelessWidget {
  const _OverflowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = destructive ? colors.semanticDanger : colors.textPrimary;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Icon(icon, size: Space.s5, color: tint),
            const SizedBox(width: Space.s3),
            Text(label, style: context.kt.body.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}

class _CloseupSkeleton extends StatelessWidget {
  const _CloseupSkeleton();

  @override
  Widget build(BuildContext context) => const KShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: KSkeleton(borderRadius: BorderRadius.zero)),
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(Space.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    KSkeleton.text(width: Space.s20),
                    SizedBox(height: Space.s3),
                    KSkeleton(height: Space.s8),
                    SizedBox(height: Space.s5),
                    KSkeleton.text(),
                    SizedBox(height: Space.s2),
                    KSkeleton.text(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
