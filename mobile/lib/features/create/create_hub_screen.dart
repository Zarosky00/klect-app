import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../library/library_providers.dart';
import '../library/widgets/collections_grid.dart';
import '../library/widgets/library_chrome.dart';
import '../library/widgets/quick_actions_sheet.dart';
import 'create_providers.dart';
import 'media/upload_journal.dart';

/// The Create tab — and the Library's front door.
///
/// Two jobs in one screen, because they are the same job: the three create
/// actions sit at the top (tab → action → form is **two** taps, one inside the
/// budget the brief allows), and the user's own shelves sit underneath so
/// "add to the thing I was just working on" is equally short.
class CreateHubScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateHubScreen({super.key});

  @override
  ConsumerState<CreateHubScreen> createState() => _CreateHubScreenState();
}

class _CreateHubScreenState extends ConsumerState<CreateHubScreen> {
  @override
  void initState() {
    super.initState();
    // First Library/Create surface to mount reconciles anything an interrupted
    // upload left behind.
    ref.read(mediaRecoveryProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(myCollectionsProvider);
    await ref.read(myCollectionsProvider.future);
  }

  String _itemRoute(List<CollectionModel> shelves) {
    final defaults = ref.read(createDefaultsProvider);
    final remembered = defaults.collectionId;
    final exists = shelves.any((shelf) => shelf.id == remembered);
    if (!exists) return '/create/item';
    final subcollection = defaults.subcollectionId;
    return subcollection == null
        ? '/create/item?collection=$remembered'
        : '/create/item?collection=$remembered&subcollection=$subcollection';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final collections = ref.watch(myCollectionsProvider);
    final shelves = collections.value ?? const <CollectionModel>[];

    return KScaffold(
      onRefresh: _refresh,
      body: CustomScrollView(
        slivers: <Widget>[
          const KAppBar(
            title: 'Create',
            subtitle: 'Shelf, group, thing.',
            expandedHeight: Space.s24,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s4,
              Space.s2,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                _CreateAction(
                  icon: Icons.add_a_photo_rounded,
                  title: 'New item',
                  subtitle: 'Photograph a thing and file it away.',
                  emphasised: true,
                  onTap: () => context.push<void>(_itemRoute(shelves)),
                ),
                const SizedBox(height: Space.s2),
                _CreateAction(
                  icon: Icons.create_new_folder_rounded,
                  title: 'New group',
                  subtitle: 'A theme inside one of your shelves.',
                  onTap: () => context.push<void>('/create/subcollection'),
                ),
                const SizedBox(height: Space.s2),
                _CreateAction(
                  icon: Icons.collections_bookmark_rounded,
                  title: 'New shelf',
                  subtitle: 'A whole new thing you collect.',
                  onTap: () => context.push<void>('/create/collection'),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s6,
                Space.s4,
                Space.s3,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Your shelves', style: context.kt.title3),
                  ),
                  if (shelves.isNotEmpty)
                    Text(
                      plural(shelves.length, 'shelf', 'shelves'),
                      style:
                          context.kt.count.copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
          ),
          ...collections.when(
            loading: () => <Widget>[
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: Space.s4),
                sliver: SliverToBoxAdapter(child: KSkeletonGrid(tiles: 4)),
              ),
            ],
            error: (error, _) => <Widget>[
              SliverToBoxAdapter(
                child: KErrorState(
                  error: error,
                  compact: true,
                  onRetry: () => ref.invalidate(myCollectionsProvider),
                ),
              ),
            ],
            data: (rows) => rows.isEmpty
                ? <Widget>[
                    SliverToBoxAdapter(
                      child: KEmptyState(
                        title: 'Your library starts here',
                        message: 'A shelf is a whole thing you collect — Anime, '
                            'Sneakers, Cameras. Inside it, groups. Inside those, '
                            'the things themselves.',
                        icon: Icons.auto_awesome_rounded,
                        actionLabel: 'Make your first shelf',
                        onAction: () =>
                            context.push<void>('/create/collection'),
                      ),
                    ),
                  ]
                : <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s4,
                        0,
                        Space.s4,
                        Space.s16,
                      ),
                      sliver: CollectionsSliverGrid(
                        collections: rows,
                        isOwner: true,
                        ownerActionsFor: (shelf) => <QuickOwnerAction>[
                          QuickOwnerAction(
                            icon: Icons.add_photo_alternate_rounded,
                            label: 'Add an item here',
                            onSelected: () => context.push<void>(
                              '/create/item?collection=${shelf.id}',
                            ),
                          ),
                          QuickOwnerAction(
                            icon: Icons.create_new_folder_rounded,
                            label: 'New group here',
                            onSelected: () => context.push<void>(
                              '/create/subcollection?collection=${shelf.id}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _CreateAction extends StatelessWidget {
  const _CreateAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      semanticLabel: title,
      enforceMinTapTarget: false,
      child: Container(
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: emphasised ? colors.accentSubtle : colors.surface1,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: emphasised ? colors.accentDefault : colors.borderSubtle,
            width: emphasised ? Strokes.thick : Strokes.thin,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: Space.s12,
              height: Space.s12,
              decoration: BoxDecoration(
                color: emphasised ? colors.accentDefault : colors.surface3,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(
                icon,
                size: Space.s6,
                color:
                    emphasised ? colors.textOnAccent : colors.textSecondary,
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title, style: context.kt.title3),
                  const SizedBox(height: Space.sPx),
                  Text(
                    subtitle,
                    style: context.kt.caption
                        .copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: Space.s5,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
