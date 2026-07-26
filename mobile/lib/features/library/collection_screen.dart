import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../create/media/upload_journal.dart';
import '../create/widgets/entity_visual.dart';
import 'library_actions.dart';
import 'library_providers.dart';
import 'widgets/edit_shelf_sheets.dart';
import 'widgets/library_cards.dart';
import 'widgets/library_chrome.dart';
import 'widgets/quick_actions_sheet.dart';
import 'widgets/reorder_sheet.dart';

/// A shelf: its groups on a rail, everything on it in a grid.
///
/// This is the middle level of the hierarchy and the busiest management
/// surface — but every owner-only affordance is gated on
/// `closeup.viewer.is_owner`, so a visitor sees a clean gallery and nothing
/// they cannot use.
class CollectionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CollectionScreen({required this.collectionId, super.key});

  /// Route parameter.
  final String collectionId;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  EntityRef get _entity => EntityRef.collection(widget.collectionId);

  @override
  void initState() {
    super.initState();
    // Reconcile anything an interrupted upload left behind before the user can
    // look at a shelf it would have polluted.
    ref.read(mediaRecoveryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
    });
  }

  Future<void> _refresh() async {
    ref.refreshLibrary(collectionId: widget.collectionId);
    await ref.read(collectionDetailProvider(widget.collectionId).future);
  }

  Future<void> _edit(CollectionModel collection) async {
    final saved = await EditCollectionSheet.show(context, collection: collection);
    if (!saved || !mounted) return;
    ref.refreshLibrary(collectionId: widget.collectionId);
    KToast.success(context, 'Shelf updated.');
  }

  Future<void> _delete(CollectionModel collection) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete ${collection.name}?',
      message: 'Its ${plural(collection.subcollectionCount, 'group')} and '
          '${plural(collection.itemCount, 'item')} go with it, along with '
          'every like, save and comment they carry. This cannot be undone.',
      confirmLabel: 'Delete shelf',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(libraryActionsProvider).deleteCollection(collection.id);
      if (!mounted) return;
      ref.refreshLibrary(collectionId: widget.collectionId);
      KToast.success(context, '${collection.name} deleted.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/create');
      }
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _reorderGroups(CollectionDetail detail) async {
    final api = ref.read(klectApiProvider);
    final order = await ReorderSheet.show(
      context,
      title: 'Order the groups',
      entries: <ReorderEntry>[
        for (final group in detail.subcollections)
          ReorderEntry(
            id: group.id,
            label: group.name,
            subtitle: plural(group.itemCount, 'item'),
            imageUrl: api.publicUrl(group.coverPath),
            blurhash: group.coverBlurhash,
          ),
      ],
    );
    if (order == null || !mounted) return;
    await _persistOrder(
      () => ref.read(libraryActionsProvider).reorderSubcollections(order),
      'Group order saved.',
    );
  }

  Future<void> _reorderItems(CollectionDetail detail) async {
    final api = ref.read(klectApiProvider);
    final order = await ReorderSheet.show(
      context,
      title: 'Order the items',
      entries: <ReorderEntry>[
        for (final item in detail.items)
          ReorderEntry(
            id: item.id,
            label: item.title,
            subtitle: item.brand,
            imageUrl: api.publicUrl(item.coverPath),
            blurhash: item.coverBlurhash,
          ),
      ],
    );
    if (order == null || !mounted) return;
    await _persistOrder(
      () => ref.read(libraryActionsProvider).reorderItems(order),
      'Item order saved.',
    );
  }

  Future<void> _persistOrder(
    Future<void> Function() write,
    String message,
  ) async {
    try {
      await write();
      if (!mounted) return;
      ref.refreshLibrary(collectionId: widget.collectionId);
      KToast.success(context, message);
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  List<QuickOwnerAction> _ownerActions(CollectionDetail detail) =>
      <QuickOwnerAction>[
        QuickOwnerAction(
          icon: Icons.edit_rounded,
          label: 'Edit shelf',
          onSelected: () => unawaited(_edit(detail.collection)),
        ),
        QuickOwnerAction(
          icon: Icons.create_new_folder_rounded,
          label: 'New group',
          onSelected: () => context.push(
            '/create/subcollection?collection=${widget.collectionId}',
          ),
        ),
        QuickOwnerAction(
          icon: Icons.add_photo_alternate_rounded,
          label: 'New item',
          onSelected: () => context.push(
            '/create/item?collection=${widget.collectionId}',
          ),
        ),
        if (detail.subcollections.length > 1)
          QuickOwnerAction(
            icon: Icons.swap_vert_rounded,
            label: 'Reorder groups',
            onSelected: () => unawaited(_reorderGroups(detail)),
          ),
        if (detail.items.length > 1)
          QuickOwnerAction(
            icon: Icons.sort_rounded,
            label: 'Reorder items',
            onSelected: () => unawaited(_reorderItems(detail)),
          ),
        QuickOwnerAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete shelf',
          destructive: true,
          onSelected: () => unawaited(_delete(detail.collection)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(collectionDetailProvider(widget.collectionId));

    return KScaffold(
      onRefresh: _refresh,
      body: detail.when(
        loading: () => const CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: _HeaderSkeleton()),
            SliverPadding(
              padding: EdgeInsets.all(Space.s4),
              sliver: SliverToBoxAdapter(child: KSkeletonGrid(tiles: 6)),
            ),
          ],
        ),
        error: (error, _) => KErrorState(
          error: error,
          onRetry: () =>
              ref.invalidate(collectionDetailProvider(widget.collectionId)),
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(CollectionDetail detail) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final collection = detail.collection;
    final accent = EntityVisual.accent(context, collection.accentColor);
    final owner = detail.closeup.owner;

    return CustomScrollView(
      slivers: <Widget>[
        KAppBar(
          title: collection.name,
          subtitle: owner.handle,
          expandedHeight: Space.s24 * 2,
          leading: KIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Back',
            color: colors.textPrimary,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/surf'),
          ),
          actions: <Widget>[
            if (detail.isOwner)
              KIconButton(
                icon: Icons.more_horiz_rounded,
                semanticLabel: 'Manage shelf',
                color: colors.textPrimary,
                onPressed: () => OwnerMenuSheet.show(
                  context,
                  title: collection.name,
                  actions: _ownerActions(detail),
                ),
              )
            else
              KIconButton(
                icon: Icons.flag_outlined,
                semanticLabel: 'Report shelf',
                color: colors.textPrimary,
                onPressed: () => KReportSheet.showForEntity(
                  context,
                  type: EntityType.collection,
                  entityId: collection.id,
                  subjectLabel: collection.name,
                ),
              ),
          ],
          background: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (collection.coverPath != null)
                KBlurhashImage(
                  url: api.publicUrl(collection.coverPath),
                  blurhash: collection.coverBlurhash,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.zero,
                  heroTag: LibraryHero.cover(
                    EntityType.collection,
                    collection.id,
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        accent.withValues(alpha: Opacities.ghost),
                        colors.bgBase,
                      ],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      colors.bgBase.withValues(alpha: 0),
                      colors.bgBase,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s3,
              Space.s4,
              Space.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: LibraryBreadcrumb(
                        steps: <BreadcrumbStep>[
                          BreadcrumbStep(
                            label: owner.name,
                            onTap: () =>
                                context.push<void>('/u/${owner.username}'),
                          ),
                        ],
                        current: collection.name,
                      ),
                    ),
                    VisibilityBadge(visibility: collection.visibility),
                  ],
                ),
                if ((collection.description ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.s3),
                  Text(
                    collection.description!,
                    style: context.kt.body
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
                if (detail.closeup.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.s3),
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s2,
                    children: <Widget>[
                      for (final tag in detail.closeup.tags)
                        KChip(
                          label: '#$tag',
                          dense: true,
                          onTap: () => context.push('/search?q=$tag'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.s4),
                KActionBar(
                  entity: detail.entity,
                  seed: InteractionState.fromCloseup(detail.closeup),
                  live: true,
                  showViews: true,
                  shareTitle: collection.name,
                ),
              ],
            ),
          ),
        ),
        _GroupsRail(
          detail: detail,
          onNewGroup: () => context.push(
            '/create/subcollection?collection=${widget.collectionId}',
          ),
        ),
        if (detail.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: detail.isOwner
                ? KEmptyState(
                    title: 'Nothing on this shelf yet',
                    message: detail.subcollections.isEmpty
                        ? 'Shelves hold groups, and groups hold things. Make '
                            'the first group, then start adding.'
                        : 'You have somewhere to put things. Add the first one.',
                    icon: Icons.inventory_2_rounded,
                    actionLabel: detail.subcollections.isEmpty
                        ? 'New group'
                        : 'Add an item',
                    onAction: () => context.push(
                      detail.subcollections.isEmpty
                          ? '/create/subcollection?collection='
                              '${widget.collectionId}'
                          : '/create/item?collection=${widget.collectionId}',
                    ),
                    secondaryActionLabel:
                        detail.subcollections.isEmpty ? null : 'New group',
                    onSecondaryAction: detail.subcollections.isEmpty
                        ? null
                        : () => context.push(
                              '/create/subcollection?collection='
                              '${widget.collectionId}',
                            ),
                  )
                : const KEmptyState(
                    title: 'Nothing here yet',
                    message: 'This shelf has not been filled in.',
                    icon: Icons.inventory_2_rounded,
                  ),
          )
        else ...<Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s4,
                Space.s4,
                Space.s2,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Everything on this shelf',
                      style: context.kt.title3,
                    ),
                  ),
                  Text(
                    plural(detail.items.length, 'item'),
                    style: context.kt.count
                        .copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              0,
              Space.s4,
              Space.s16,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: LibraryGrid.itemExtent,
                crossAxisSpacing: Layout.masonryGutter,
                mainAxisSpacing: Layout.masonryGutter,
                childAspectRatio: LibraryGrid.ratioFor(LibraryGrid.itemExtent),
              ),
              itemCount: detail.items.length,
              itemBuilder: (context, index) => ItemTile(
                item: detail.items[index],
                isOwner: detail.isOwner,
                ownerActions: detail.isOwner
                    ? <QuickOwnerAction>[
                        QuickOwnerAction(
                          icon: Icons.open_in_new_rounded,
                          label: 'Open item',
                          onSelected: () =>
                              context.push('/i/${detail.items[index].id}'),
                        ),
                      ]
                    : const <QuickOwnerAction>[],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GroupsRail extends ConsumerWidget {
  const _GroupsRail({required this.detail, required this.onNewGroup});

  final CollectionDetail detail;
  final VoidCallback onNewGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (detail.subcollections.isEmpty && !detail.isOwner) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final colors = context.kc;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s4,
              Space.s4,
              Space.s2,
            ),
            child: Row(
              children: <Widget>[
                Expanded(child: Text('Groups', style: context.kt.title3)),
                Text(
                  plural(detail.subcollections.length, 'group'),
                  style: context.kt.count.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          SizedBox(
            height: Space.s24 + Space.s8 + Space.s12,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              children: <Widget>[
                for (final group in detail.subcollections) ...<Widget>[
                  SubcollectionCard(
                    subcollection: group,
                    isOwner: detail.isOwner,
                  ),
                  const SizedBox(width: Space.s3),
                ],
                if (detail.isOwner)
                  _NewGroupTile(onTap: onNewGroup),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewGroupTile extends StatelessWidget {
  const _NewGroupTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    const size = Space.s24 + Space.s8;
    return KPressable(
      onTap: onTap,
      semanticLabel: 'New group',
      enforceMinTapTarget: false,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: colors.borderDefault,
                  width: Strokes.thin,
                ),
              ),
              child: Icon(
                Icons.create_new_folder_rounded,
                size: Space.s7,
                color: colors.accentDefault,
              ),
            ),
            const SizedBox(height: Space.s15),
            Text('New group', style: context.kt.label),
          ],
        ),
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) => const KShimmer(
        child: Padding(
          padding: EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              KSkeleton(height: Space.s24),
              SizedBox(height: Space.s4),
              KSkeleton.text(width: Space.s24 * 2),
              SizedBox(height: Space.s2),
              KSkeleton.text(width: Space.s20),
            ],
          ),
        ),
      );
}
