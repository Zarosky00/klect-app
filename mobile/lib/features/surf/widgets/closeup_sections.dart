import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../profile/follow_button.dart';
import 'entity_gesture_card.dart';

/// `Anime · JJK` — the trail above whatever the closeup is showing.
///
/// Every crumb navigates, because the hierarchy is the product: you should be
/// able to walk up from a single figurine to the shelf it lives on.
class CloseupBreadcrumbRow extends StatelessWidget {
  /// Creates a breadcrumb row.
  const CloseupBreadcrumbRow({required this.breadcrumb, super.key});

  /// The trail, or null when this closeup *is* the root.
  final CloseupBreadcrumb? breadcrumb;

  @override
  Widget build(BuildContext context) {
    final trail = breadcrumb;
    final crumbs = <({EntityType type, EntityRefLite target})>[
      if (trail?.collection != null)
        (type: EntityType.collection, target: trail!.collection!),
      if (trail?.subcollection != null)
        (type: EntityType.subcollection, target: trail!.subcollection!),
    ];
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final colors = context.kc;
    final text = context.kt;

    return Row(
      children: <Widget>[
        for (var index = 0; index < crumbs.length; index++) ...<Widget>[
          if (index > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s1),
              child: Icon(
                Icons.chevron_right_rounded,
                size: Space.s4,
                color: colors.textTertiary,
              ),
            ),
          Flexible(
            child: KPressable(
              enforceMinTapTarget: false,
              semanticLabel: 'Open ${crumbs[index].target.name}',
              onTap: () => context.push(
                KlectLinks.closeupPath(
                  crumbs[index].type,
                  crumbs[index].target.id,
                ),
              ),
              child: Text(
                crumbs[index].target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.micro.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Owner avatar, name and the follow button, with the target's follower count
/// kept correct everywhere it appears by the shared follow controller.
class CloseupOwnerRow extends ConsumerStatefulWidget {
  /// Creates an owner row.
  const CloseupOwnerRow({required this.closeup, super.key});

  /// The closeup whose owner this is.
  final Closeup closeup;

  @override
  ConsumerState<CloseupOwnerRow> createState() => _CloseupOwnerRowState();
}

class _CloseupOwnerRowState extends ConsumerState<CloseupOwnerRow> {
  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void didUpdateWidget(CloseupOwnerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.closeup.owner.id != widget.closeup.owner.id ||
        oldWidget.closeup.viewer.follows != widget.closeup.viewer.follows) {
      _hydrate();
    }
  }

  void _hydrate() {
    final owner = widget.closeup.owner;
    if (owner.id.isEmpty) return;
    ref
        .read(followProvider(owner.id).notifier)
        .hydrate(
          following: widget.closeup.viewer.follows,
          followerCount: owner.followerCount,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final owner = widget.closeup.owner;
    final follow = ref.watch(followProvider(owner.id));
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(owner.avatarPath, bucket: StorageBucket.avatars);

    void openProfile() {
      if (owner.username.isEmpty) return;
      context.push(KlectLinks.profilePath(owner.username));
    }

    return Row(
      children: <Widget>[
        KAvatar(
          imageUrl: avatarUrl,
          name: owner.name,
          size: Space.s10,
          isVerified: owner.isVerified,
          onTap: openProfile,
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: KPressable(
            onTap: openProfile,
            enforceMinTapTarget: false,
            semanticLabel: 'Open ${owner.name}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyStrong,
                ),
                Text(
                  '${owner.handle} · ${formatCount(follow.followerCount)} '
                  'followers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        if (!widget.closeup.viewer.isOwner) ...<Widget>[
          const SizedBox(width: Space.s3),
          FollowButton(
            userId: owner.id,
            displayName: owner.name,
            avatarPath: owner.avatarPath,
            followerCount: owner.followerCount,
            initiallyFollowing: widget.closeup.viewer.follows,
            size: KButtonSize.small,
          ),
        ],
      ],
    );
  }
}

/// Brand · model · year · condition · rarity · acquisition · price.
///
/// Only the fields that are actually set are rendered — an empty metadata
/// grid full of em dashes is worse than no grid.
class CloseupMetadata extends StatelessWidget {
  /// Creates the metadata block for an item.
  const CloseupMetadata({required this.item, super.key});

  /// The item body from `get_closeup`.
  final ItemModel item;

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  List<({String label, String value})> _fields() {
    final price = item.purchasePrice;
    final acquired = item.acquisitionDate;
    return <({String label, String value})>[
      if (item.brand != null) (label: 'Brand', value: item.brand!),
      if (item.model != null) (label: 'Model', value: item.model!),
      if (item.year != null) (label: 'Year', value: '${item.year}'),
      if (item.condition != null) (label: 'Condition', value: item.condition!),
      if (item.rarity != null) (label: 'Rarity', value: item.rarity!),
      if (acquired != null)
        (
          label: 'Acquired',
          value:
              '${acquired.year}-${_two(acquired.month)}-'
              '${_two(acquired.day)}',
        ),
      if (item.acquisitionPlace != null)
        (label: 'From', value: item.acquisitionPlace!),
      if (price != null)
        (
          label: 'Paid',
          value: '${item.currency ?? ''} ${price.toStringAsFixed(2)}'.trim(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields();
    if (fields.isEmpty) return const SizedBox.shrink();
    final colors = context.kc;
    final text = context.kt;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s4,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.hairline),
      ),
      child: Wrap(
        spacing: Space.s6,
        runSpacing: Space.s4,
        children: <Widget>[
          for (final field in fields)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: Space.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    field.label.toUpperCase(),
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: Space.s05),
                  Text(field.value, style: text.bodyStrong),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tag chips. Tapping one searches for it.
class CloseupTags extends StatelessWidget {
  /// Creates a tag row.
  const CloseupTags({required this.tags, super.key});

  /// Tag slugs from `get_closeup`.
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.s2,
      runSpacing: Space.s2,
      children: <Widget>[
        for (final tag in tags)
          KChip(
            label: '#$tag',
            dense: true,
            onTap: () => context.push('/search?q=${Uri.encodeComponent(tag)}'),
          ),
      ],
    );
  }
}

/// A horizontal strip of item cards — siblings of an item, or the children of
/// a shelf. Every card carries the full gesture contract.
class CloseupItemStrip extends ConsumerWidget {
  /// Creates a strip.
  const CloseupItemStrip({required this.items, super.key});

  /// The items to show.
  final List<CloseupItemRef> items;

  /// Strip height. Cards take their width from their own aspect ratio, so a
  /// portrait and a landscape cover sit on the same baseline.
  static const double height = Space.s24 + Space.s12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final api = ref.watch(klectApiProvider);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: Space.s2),
        itemBuilder: (context, index) {
          final item = items[index];
          final aspect = (item.aspect ?? Aspect.cover).clamp(
            Aspect.gridMin,
            Aspect.gridMax,
          );
          final url = api.publicUrl(item.coverPath);
          return SizedBox(
            width: height * aspect,
            child: KEntityGestureCard(
              entity: EntityRef.item(item.id),
              title: item.title,
              imageUrl: url,
              blurhash: item.coverBlurhash,
              aspectRatio: aspect,
              child: KBlurhashImage(
                url: url,
                blurhash: item.coverBlurhash,
                semanticLabel: item.title,
                borderRadius: BorderRadius.circular(Radii.md),
                memCacheWidth: (height * aspect * devicePixelRatio).round(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The subcollections rail on a collection closeup: the middle level of the
/// hierarchy, rendered as its own row of shelves.
class CloseupSubcollectionRail extends ConsumerWidget {
  /// Creates the rail.
  const CloseupSubcollectionRail({required this.subcollections, super.key});

  /// Child subcollections from `get_closeup`.
  final List<CloseupSubcollectionRef> subcollections;

  /// Card edge length.
  static const double tile = Space.s24 + Space.s8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (subcollections.isEmpty) return const SizedBox.shrink();
    final api = ref.watch(klectApiProvider);
    final colors = context.kc;
    final text = context.kt;

    return SizedBox(
      height: tile + Space.s12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
        itemCount: subcollections.length,
        separatorBuilder: (context, index) => const SizedBox(width: Space.s3),
        itemBuilder: (context, index) {
          final sub = subcollections[index];
          final url = api.publicUrl(sub.coverPath);
          return SizedBox(
            width: tile,
            child: KEntityGestureCard(
              entity: EntityRef.subcollection(sub.id),
              title: sub.name,
              subtitle: '${sub.itemCount} things',
              imageUrl: url,
              blurhash: sub.coverBlurhash,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  KBlurhashImage(
                    url: url,
                    blurhash: sub.coverBlurhash,
                    aspectRatio: Aspect.cover,
                    semanticLabel: sub.name,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  const SizedBox(height: Space.s15),
                  Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.label,
                  ),
                  Text(
                    '${formatCount(sub.itemCount)} things',
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A quiet section heading inside the closeup sheet.
class CloseupSectionHeader extends StatelessWidget {
  /// Creates a section heading.
  const CloseupSectionHeader({required this.title, super.key, this.trailing});

  /// The heading.
  final String title;

  /// Optional trailing control or count.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title.toUpperCase(),
          style: context.kt.micro.copyWith(color: context.kc.textTertiary),
        ),
      ),
      ?trailing,
    ],
  );
}
