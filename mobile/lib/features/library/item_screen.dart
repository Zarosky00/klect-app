import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../create/media/upload_journal.dart';
import 'library_actions.dart';
import 'library_providers.dart';
import 'widgets/add_photos_sheet.dart';
import 'widgets/edit_item_sheet.dart';
import 'widgets/library_chrome.dart';
import 'widgets/quick_actions_sheet.dart';
import 'widgets/reorder_sheet.dart';

/// A thing, with all of its photos and everything known about it.
///
/// The bottom of the hierarchy, and the only level that carries `item_media` —
/// so this is where "set as cover", "reorder photos" and "add photos" live.
class ItemScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ItemScreen({required this.itemId, super.key});

  /// Route parameter.
  final String itemId;

  @override
  ConsumerState<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends ConsumerState<ItemScreen> {
  final PageController _pager = PageController();
  int _photoIndex = 0;

  EntityRef get _entity => EntityRef.item(widget.itemId);

  @override
  void initState() {
    super.initState();
    ref.read(mediaRecoveryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.refreshLibrary(itemId: widget.itemId);
    await ref.read(itemDetailProvider(widget.itemId).future);
  }

  void _refreshAround(ItemDetail detail) => ref.refreshLibrary(
        itemId: widget.itemId,
        collectionId: detail.closeup.breadcrumb?.collection?.id ??
            detail.item.collectionId,
        subcollectionId: detail.closeup.breadcrumb?.subcollection?.id ??
            detail.item.subcollectionId,
      );

  Future<void> _edit(ItemDetail detail) async {
    final saved = await EditItemSheet.show(
      context,
      item: detail.item,
      parentName: detail.closeup.breadcrumb?.subcollection?.name,
    );
    if (!saved || !mounted) return;
    _refreshAround(detail);
    KToast.success(context, 'Item updated.');
  }

  Future<void> _addPhotos(ItemDetail detail) async {
    final added = await AddPhotosSheet.show(
      context,
      itemId: widget.itemId,
      existingCount: detail.media.length,
    );
    if (added == 0 || !mounted) return;
    _refreshAround(detail);
    KToast.success(context, '$added photo${added == 1 ? '' : 's'} added.');
  }

  Future<void> _reorderPhotos(ItemDetail detail) async {
    final api = ref.read(klectApiProvider);
    final order = await ReorderSheet.show(
      context,
      title: 'Order the photos',
      hint: 'The first photo becomes the cover everywhere.',
      entries: <ReorderEntry>[
        for (var i = 0; i < detail.media.length; i++)
          ReorderEntry(
            id: detail.media[i].id,
            label: detail.media[i].altText ?? 'Photo ${i + 1}',
            subtitle: '${detail.media[i].width} × ${detail.media[i].height}',
            imageUrl: api.publicUrl(detail.media[i].storagePath),
            blurhash: detail.media[i].blurhash,
          ),
      ],
    );
    if (order == null || !mounted) return;
    final byId = <String, ItemMedia>{
      for (final media in detail.media) media.id: media,
    };
    try {
      await ref.read(libraryActionsProvider).reorderMedia(
            itemId: widget.itemId,
            ordered: <ItemMedia>[
              for (final id in order)
                if (byId.containsKey(id)) byId[id]!,
            ],
          );
      if (!mounted) return;
      _refreshAround(detail);
      KToast.success(context, 'Photo order saved.');
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _setCover(ItemDetail detail, String mediaId) async {
    try {
      await ref.read(libraryActionsProvider).setItemCover(
            itemId: widget.itemId,
            media: detail.media,
            mediaId: mediaId,
          );
      if (!mounted) return;
      _refreshAround(detail);
      KToast.success(context, 'Cover updated.');
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _move(ItemDetail detail) async {
    final collectionId =
        detail.closeup.breadcrumb?.collection?.id ?? detail.item.collectionId;
    final subcollectionId = detail.closeup.breadcrumb?.subcollection?.id ??
        detail.item.subcollectionId;
    if (collectionId == null || subcollectionId == null) return;

    final target = await MoveItemSheet.show(
      context,
      currentCollectionId: collectionId,
      currentSubcollectionId: subcollectionId,
    );
    if (target == null || !mounted) return;

    try {
      final result = await ref.read(libraryActionsProvider).moveItem(
            itemId: widget.itemId,
            fromSubcollectionId: subcollectionId,
            toSubcollectionId: target.subcollectionId,
            toCollectionId: target.collectionId,
          );
      if (!mounted) return;
      ref
        ..refreshLibrary(
          itemId: widget.itemId,
          collectionId: collectionId,
          subcollectionId: subcollectionId,
        )
        ..refreshLibrary(
          collectionId: target.collectionId,
          subcollectionId: target.subcollectionId,
        );
      KToast.show(
        context,
        result.summary,
        kind: KToastKind.success,
        icon: Icons.drive_file_move_rounded,
      );
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _delete(ItemDetail detail) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete ${detail.item.title}?',
      message: 'Its ${plural(detail.media.length, 'photo')} and every like, '
          'save and comment go with it. This cannot be undone.',
      confirmLabel: 'Delete item',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(libraryActionsProvider).deleteItem(widget.itemId);
      if (!mounted) return;
      _refreshAround(detail);
      KToast.success(context, 'Item deleted.');
      final subcollectionId = detail.closeup.breadcrumb?.subcollection?.id;
      if (context.canPop()) {
        context.pop();
      } else if (subcollectionId != null) {
        context.go('/s/$subcollectionId');
      } else {
        context.go('/create');
      }
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _toggleFavourite(ItemDetail detail) async {
    try {
      await ref
          .read(libraryActionsProvider)
          .editItem(widget.itemId, isFavorite: !detail.item.isFavorite);
      if (!mounted) return;
      _refreshAround(detail);
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  List<QuickOwnerAction> _ownerActions(ItemDetail detail) => <QuickOwnerAction>[
        QuickOwnerAction(
          icon: Icons.edit_rounded,
          label: 'Edit details',
          onSelected: () => unawaited(_edit(detail)),
        ),
        QuickOwnerAction(
          icon: Icons.add_a_photo_rounded,
          label: 'Add photos',
          onSelected: () => unawaited(_addPhotos(detail)),
        ),
        if (detail.media.length > 1)
          QuickOwnerAction(
            icon: Icons.burst_mode_rounded,
            label: 'Reorder photos',
            onSelected: () => unawaited(_reorderPhotos(detail)),
          ),
        if (detail.media.length > 1 && _photoIndex < detail.media.length)
          QuickOwnerAction(
            icon: Icons.image_rounded,
            label: 'Make photo ${_photoIndex + 1} the cover',
            onSelected: () =>
                unawaited(_setCover(detail, detail.media[_photoIndex].id)),
          ),
        QuickOwnerAction(
          icon: Icons.drive_file_move_rounded,
          label: 'Move to another group',
          onSelected: () => unawaited(_move(detail)),
        ),
        QuickOwnerAction(
          icon: detail.item.isFavorite
              ? Icons.star_rounded
              : Icons.star_border_rounded,
          label: detail.item.isFavorite
              ? 'Remove from favourites'
              : 'Mark as a favourite',
          onSelected: () => unawaited(_toggleFavourite(detail)),
        ),
        QuickOwnerAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete item',
          destructive: true,
          onSelected: () => unawaited(_delete(detail)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(itemDetailProvider(widget.itemId));

    return KScaffold(
      safeTop: false,
      onRefresh: _refresh,
      body: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.s4),
          child: KShimmer(child: KSkeletonList(rows: 3)),
        ),
        error: (error, _) => KErrorState(
          error: error,
          onRetry: () => ref.invalidate(itemDetailProvider(widget.itemId)),
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(ItemDetail detail) {
    final colors = context.kc;
    final item = detail.item;
    final breadcrumb = detail.closeup.breadcrumb;

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _PhotoPager(
            media: detail.media,
            item: item,
            controller: _pager,
            index: _photoIndex,
            onIndexChanged: (index) => setState(() => _photoIndex = index),
            onOpenImmersive: (index) => context.push<void>(
              '${KlectLinks.immersivePath(EntityType.item, item.id)}?i=$index',
            ),
            onPeek: () => QuickActionsSheet.show(
              context,
              entity: detail.entity,
              title: item.title,
              isOwner: detail.isOwner,
              seed: InteractionState.fromCloseup(detail.closeup),
              ownerActions: detail.isOwner
                  ? _ownerActions(detail)
                  : const <QuickOwnerAction>[],
            ),
            onBack: () =>
                context.canPop() ? context.pop() : context.go('/surf'),
            onOverflow: detail.isOwner
                ? () => OwnerMenuSheet.show(
                      context,
                      title: item.title,
                      actions: _ownerActions(detail),
                    )
                : () => KReportSheet.showForEntity(
                      context,
                      type: EntityType.item,
                      entityId: item.id,
                      subjectLabel: item.title,
                    ),
            overflowIcon:
                detail.isOwner ? Icons.more_horiz_rounded : Icons.flag_outlined,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Space.s4,
            Space.s4,
            Space.s4,
            Space.s16,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              LibraryBreadcrumb(
                steps: <BreadcrumbStep>[
                  if (breadcrumb?.collection != null)
                    BreadcrumbStep(
                      label: breadcrumb!.collection!.name,
                      onTap: () =>
                          context.push<void>('/c/${breadcrumb.collection!.id}'),
                    ),
                  if (breadcrumb?.subcollection != null)
                    BreadcrumbStep(
                      label: breadcrumb!.subcollection!.name,
                      onTap: () => context
                          .push<void>('/s/${breadcrumb.subcollection!.id}'),
                    ),
                ],
              ),
              const SizedBox(height: Space.s2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(item.title, style: context.kt.display3)),
                  if (item.isFavorite)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: Icon(
                        Icons.star_rounded,
                        size: Space.s5,
                        color: colors.accentDefault,
                      ),
                    ),
                  VisibilityBadge(visibility: item.visibility),
                ],
              ),
              if (_subtitle(item).isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.s1),
                Text(
                  _subtitle(item),
                  style:
                      context.kt.callout.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: Space.s4),
              KActionBar(
                entity: detail.entity,
                seed: InteractionState.fromCloseup(detail.closeup),
                live: true,
                showViews: true,
                shareTitle: item.title,
              ),
              if ((item.description ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.s5),
                Text(
                  item.description!,
                  style: context.kt.body.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: Space.s5),
              _SpecTable(item: item, mediaCount: detail.media.length),
              if (detail.closeup.tags.isNotEmpty || _tagsOf(item).isNotEmpty)
                ...<Widget>[
                  const SizedBox(height: Space.s5),
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s2,
                    children: <Widget>[
                      for (final tag in <String>{
                        ...detail.closeup.tags,
                        ..._tagsOf(item),
                      })
                        KChip(
                          label: '#$tag',
                          dense: true,
                          onTap: () => context.push<void>('/search?q=$tag'),
                        ),
                    ],
                  ),
                ],
              if (detail.isOwner) ...<Widget>[
                const SizedBox(height: Space.s6),
                _OwnerToolbar(
                  onEdit: () => unawaited(_edit(detail)),
                  onAddPhotos: () => unawaited(_addPhotos(detail)),
                  onMove: () => unawaited(_move(detail)),
                ),
              ],
              if (detail.closeup.siblings.isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.s8),
                Text(
                  breadcrumb?.subcollection == null
                      ? 'More like this'
                      : 'More in ${breadcrumb!.subcollection!.name}',
                  style: context.kt.title3,
                ),
                const SizedBox(height: Space.s3),
                _SiblingsRail(
                  siblings: detail.closeup.siblings,
                  currentId: item.id,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _subtitle(ItemModel item) => <String>[
        if ((item.brand ?? '').isNotEmpty) item.brand!,
        if ((item.model ?? '').isNotEmpty) item.model!,
        if (item.year != null) '${item.year}',
      ].join(' · ');

  static List<String> _tagsOf(ItemModel item) =>
      asStringList(item.attributes['tags']);
}

class _PhotoPager extends ConsumerWidget {
  const _PhotoPager({
    required this.media,
    required this.item,
    required this.controller,
    required this.index,
    required this.onIndexChanged,
    required this.onOpenImmersive,
    required this.onPeek,
    required this.onBack,
    required this.onOverflow,
    required this.overflowIcon,
  });

  final List<ItemMedia> media;
  final ItemModel item;
  final PageController controller;
  final int index;
  final ValueChanged<int> onIndexChanged;
  final ValueChanged<int> onOpenImmersive;
  final VoidCallback onPeek;
  final VoidCallback onBack;
  final VoidCallback onOverflow;
  final IconData overflowIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final safeIndex = media.isEmpty ? 0 : index.clamp(0, media.length - 1);
    final ratio = (media.isEmpty
            ? item.coverAspect ?? Aspect.cover
            : media[safeIndex].aspect ?? Aspect.cover)
        .clamp(Aspect.gridMin, Aspect.gridMax);

    return Stack(
      children: <Widget>[
        AnimatedContainer(
          duration: KMotion.duration(context, KDurations.base),
          curve: KCurves.standard,
          height: MediaQuery.sizeOf(context).width / ratio,
          color: colors.bgSunken,
          child: media.isEmpty
              ? KBlurhashImage(
                  url: api.publicUrl(item.coverPath),
                  blurhash: item.coverBlurhash,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.zero,
                  heroTag: LibraryHero.cover(EntityType.item, item.id),
                  semanticLabel: item.title,
                )
              : PageView.builder(
                  controller: controller,
                  itemCount: media.length,
                  onPageChanged: onIndexChanged,
                  itemBuilder: (context, page) {
                    final photo = media[page];
                    final label = photo.altText ??
                        'Photo ${page + 1} of ${media.length}';
                    return KGestureRegion(
                      semanticLabel: label,
                      onTap: () => onOpenImmersive(page),
                      onDoubleTap: () => onOpenImmersive(page),
                      onLongPress: onPeek,
                      child: KBlurhashImage(
                        url: api.publicUrl(photo.storagePath),
                        blurhash: photo.blurhash,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.zero,
                        heroTag: page == 0
                            ? LibraryHero.cover(EntityType.item, item.id)
                            : null,
                        semanticLabel: label,
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          left: Space.s2,
          right: Space.s2,
          top: MediaQuery.paddingOf(context).top + Space.s1,
          child: Row(
            children: <Widget>[
              KIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                color: colors.textPrimary,
                background: colors.surfaceScrim,
                onPressed: onBack,
              ),
              const Spacer(),
              KIconButton(
                icon: overflowIcon,
                semanticLabel: 'More',
                color: colors.textPrimary,
                background: colors.surfaceScrim,
                onPressed: onOverflow,
              ),
            ],
          ),
        ),
        if (media.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.s3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < media.length; i++)
                  AnimatedContainer(
                    duration: KMotion.duration(context, KDurations.fast),
                    margin: const EdgeInsets.symmetric(horizontal: Space.sPx),
                    width: i == safeIndex ? Space.s4 : Space.s1,
                    height: Space.s1,
                    decoration: BoxDecoration(
                      color: i == safeIndex
                          ? colors.textPrimary
                          : colors.textPrimary
                              .withValues(alpha: Opacities.veil),
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.item, required this.mediaCount});

  final ItemModel item;
  final int mediaCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final rows = <(String, String)>[
      if ((item.brand ?? '').isNotEmpty) ('Maker', item.brand!),
      if ((item.model ?? '').isNotEmpty) ('Model', item.model!),
      if (item.year != null) ('Year', '${item.year}'),
      if ((item.condition ?? '').isNotEmpty) ('Condition', item.condition!),
      if ((item.rarity ?? '').isNotEmpty) ('Rarity', item.rarity!),
      if (item.acquisitionDate != null)
        ('Acquired', _date(item.acquisitionDate!)),
      if ((item.acquisitionPlace ?? '').isNotEmpty)
        ('From', item.acquisitionPlace!),
      if (item.purchasePrice != null)
        ('Paid', '${item.currency ?? ''} ${item.purchasePrice}'.trim()),
      ('Photos', plural(mediaCount, 'photo')),
      if (item.createdAt != null) ('Added', timeago.format(item.createdAt!)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Divider(color: colors.borderSubtle, height: Strokes.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s25),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: Space.s24,
                    child: Text(
                      rows[i].$1,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                  ),
                  Expanded(child: Text(rows[i].$2, style: context.kt.callout)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _OwnerToolbar extends StatelessWidget {
  const _OwnerToolbar({
    required this.onEdit,
    required this.onAddPhotos,
    required this.onMove,
  });

  final VoidCallback onEdit;
  final VoidCallback onAddPhotos;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: KButton(
              label: 'Edit',
              icon: Icons.edit_rounded,
              variant: KButtonVariant.secondary,
              expand: true,
              onPressed: onEdit,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: KButton(
              label: 'Photos',
              icon: Icons.add_a_photo_rounded,
              variant: KButtonVariant.secondary,
              expand: true,
              onPressed: onAddPhotos,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: KButton(
              label: 'Move',
              icon: Icons.drive_file_move_rounded,
              variant: KButtonVariant.secondary,
              expand: true,
              onPressed: onMove,
            ),
          ),
        ],
      );
}

class _SiblingsRail extends ConsumerWidget {
  const _SiblingsRail({required this.siblings, required this.currentId});

  final List<CloseupItemRef> siblings;
  final String currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(klectApiProvider);
    const size = Space.s24;

    return SizedBox(
      height: size + Space.s10,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: siblings.length,
        separatorBuilder: (context, _) => const SizedBox(width: Space.s2),
        itemBuilder: (context, index) {
          final sibling = siblings[index];
          final isCurrent = sibling.id == currentId;
          return SizedBox(
            width: size,
            child: KGestureRegion(
              semanticLabel: sibling.title,
              enabled: !isCurrent,
              onTap: () =>
                  LibraryNavigation.open(context, EntityType.item, sibling.id),
              onDoubleTap: () => LibraryNavigation.immersive(
                context,
                EntityType.item,
                sibling.id,
              ),
              child: Opacity(
                opacity: isCurrent ? Opacities.disabled : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    KBlurhashImage(
                      url: api.publicUrl(sibling.coverPath),
                      blurhash: sibling.coverBlurhash,
                      aspectRatio: Aspect.cover,
                      semanticLabel: sibling.title,
                    ),
                    const SizedBox(height: Space.s15),
                    Text(
                      sibling.title,
                      style: context.kt.micro
                          .copyWith(color: context.kc.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
