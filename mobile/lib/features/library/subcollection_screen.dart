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
import 'library_actions.dart';
import 'library_providers.dart';
import 'widgets/edit_shelf_sheets.dart';
import 'widgets/library_cards.dart';
import 'widgets/library_chrome.dart';
import 'widgets/quick_actions_sheet.dart';
import 'widgets/reorder_sheet.dart';

/// A group inside a shelf: the items it holds, in the owner's order.
class SubcollectionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SubcollectionScreen({required this.subcollectionId, super.key});

  /// Route parameter.
  final String subcollectionId;

  @override
  ConsumerState<SubcollectionScreen> createState() =>
      _SubcollectionScreenState();
}

class _SubcollectionScreenState extends ConsumerState<SubcollectionScreen> {
  EntityRef get _entity => EntityRef.subcollection(widget.subcollectionId);

  @override
  void initState() {
    super.initState();
    ref.read(mediaRecoveryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
    });
  }

  Future<void> _refresh() async {
    ref.refreshLibrary(subcollectionId: widget.subcollectionId);
    await ref.read(subcollectionDetailProvider(widget.subcollectionId).future);
  }

  Future<void> _edit(SubcollectionDetail detail) async {
    final saved = await EditSubcollectionSheet.show(
      context,
      subcollection: detail.subcollection,
      parentName: detail.parent?.name,
    );
    if (!saved || !mounted) return;
    ref.refreshLibrary(
      collectionId: detail.parent?.id,
      subcollectionId: widget.subcollectionId,
    );
    KToast.success(context, 'Group updated.');
  }

  Future<void> _delete(SubcollectionDetail detail) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete ${detail.subcollection.name}?',
      message: 'The ${plural(detail.subcollection.itemCount, 'item')} inside '
          'go with it. This cannot be undone.',
      confirmLabel: 'Delete group',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(libraryActionsProvider)
          .deleteSubcollection(widget.subcollectionId);
      if (!mounted) return;
      ref.refreshLibrary(
        collectionId: detail.parent?.id,
        subcollectionId: widget.subcollectionId,
      );
      KToast.success(context, 'Group deleted.');
      final parentId = detail.parent?.id;
      if (context.canPop()) {
        context.pop();
      } else if (parentId != null) {
        context.go('/c/$parentId');
      } else {
        context.go('/create');
      }
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  Future<void> _reorderItems(SubcollectionDetail detail) async {
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
    try {
      await ref.read(libraryActionsProvider).reorderItems(order);
      if (!mounted) return;
      ref.refreshLibrary(
        collectionId: detail.parent?.id,
        subcollectionId: widget.subcollectionId,
      );
      KToast.success(context, 'Item order saved.');
    } on KlectError catch (error) {
      if (!mounted) return;
      KToast.error(context, error.message);
    }
  }

  List<QuickOwnerAction> _ownerActions(SubcollectionDetail detail) {
    final collectionId = detail.parent?.id ?? detail.subcollection.collectionId;
    return <QuickOwnerAction>[
      QuickOwnerAction(
        icon: Icons.edit_rounded,
        label: 'Edit group',
        onSelected: () => unawaited(_edit(detail)),
      ),
      if (collectionId != null)
        QuickOwnerAction(
          icon: Icons.add_photo_alternate_rounded,
          label: 'Add an item here',
          onSelected: () => context.push<void>(
            '/create/item?collection=$collectionId'
            '&subcollection=${widget.subcollectionId}',
          ),
        ),
      if (detail.items.length > 1)
        QuickOwnerAction(
          icon: Icons.sort_rounded,
          label: 'Reorder items',
          onSelected: () => unawaited(_reorderItems(detail)),
        ),
      QuickOwnerAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete group',
        destructive: true,
        onSelected: () => unawaited(_delete(detail)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final detail =
        ref.watch(subcollectionDetailProvider(widget.subcollectionId));

    return KScaffold(
      onRefresh: _refresh,
      body: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.s4),
          child: KShimmer(child: KSkeletonGrid(tiles: 6)),
        ),
        error: (error, _) => KErrorState(
          error: error,
          onRetry: () => ref
              .invalidate(subcollectionDetailProvider(widget.subcollectionId)),
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(SubcollectionDetail detail) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final group = detail.subcollection;
    final parent = detail.parent;
    final collectionId = parent?.id ?? group.collectionId;

    return CustomScrollView(
      slivers: <Widget>[
        KAppBar(
          title: group.name,
          subtitle: parent?.name,
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
                semanticLabel: 'Manage group',
                color: colors.textPrimary,
                onPressed: () => OwnerMenuSheet.show(
                  context,
                  title: group.name,
                  actions: _ownerActions(detail),
                ),
              )
            else
              KIconButton(
                icon: Icons.flag_outlined,
                semanticLabel: 'Report group',
                color: colors.textPrimary,
                onPressed: () => KReportSheet.showForEntity(
                  context,
                  type: EntityType.subcollection,
                  entityId: group.id,
                  subjectLabel: group.name,
                ),
              ),
          ],
          background: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (group.coverPath != null)
                KBlurhashImage(
                  url: api.publicUrl(group.coverPath),
                  blurhash: group.coverBlurhash,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.zero,
                  heroTag:
                      LibraryHero.cover(EntityType.subcollection, group.id),
                )
              else
                ColoredBox(color: colors.surface1),
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
                          if (parent != null)
                            BreadcrumbStep(
                              label: parent.name,
                              onTap: () => context.push<void>('/c/${parent.id}'),
                            ),
                        ],
                        current: group.name,
                      ),
                    ),
                    VisibilityBadge(visibility: group.visibility),
                  ],
                ),
                if ((group.description ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.s3),
                  Text(
                    group.description!,
                    style:
                        context.kt.body.copyWith(color: colors.textSecondary),
                  ),
                ],
                const SizedBox(height: Space.s4),
                KActionBar(
                  entity: detail.entity,
                  seed: InteractionState.fromCloseup(detail.closeup),
                  live: true,
                  showViews: true,
                  shareTitle: group.name,
                ),
              ],
            ),
          ),
        ),
        if (detail.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: detail.isOwner
                ? KEmptyState(
                    title: 'This group is empty',
                    message:
                        'Photograph the first thing and it lands right here.',
                    icon: Icons.add_a_photo_rounded,
                    actionLabel: 'Add an item',
                    onAction: collectionId == null
                        ? null
                        : () => context.push<void>(
                              '/create/item?collection=$collectionId'
                              '&subcollection=${widget.subcollectionId}',
                            ),
                  )
                : const KEmptyState(
                    title: 'Nothing here yet',
                    message: 'This group has not been filled in.',
                    icon: Icons.inventory_2_rounded,
                  ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
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
              ),
            ),
          ),
      ],
    );
  }
}
