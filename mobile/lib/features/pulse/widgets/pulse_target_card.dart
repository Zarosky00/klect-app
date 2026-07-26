import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../surf/surf.dart';

/// Renders the 0018 envelope's server-embedded `target` block: the quoted
/// post, or the shared collection / shelf / thing, or the tombstone when the
/// target is no longer visible to the viewer.
///
/// The same widget serves three surfaces — the Pulse stream (embedded
/// payload), the post closeup and the composer preview (payload built
/// client-side by [pulseTargetProvider]).
class PulseTargetCard extends ConsumerWidget {
  /// Creates a target card.
  const PulseTargetCard({
    required this.target,
    super.key,
    this.interactive = true,
  });

  /// The embedded payload.
  final PulseTarget target;

  /// Whether the card carries the full gesture contract. Turn off inside the
  /// composer, where a tap must not navigate away from a draft.
  final bool interactive;

  /// Height of the entity cover thumbnail.
  static const double thumb = Space.s20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (target.unavailable || target.type == null) {
      return const _TargetTombstone();
    }

    final card = target.type == EntityType.post
        ? _QuotedPostBody(target: target)
        : _EntityBody(target: target);

    if (!interactive) return card;

    final entity = EntityRef(target.type!, target.id);
    return KEntityGestureCard(
      entity: entity,
      title: target.title ?? target.body ?? target.author?.name,
      subtitle: target.author?.handle,
      imageUrl: ref.watch(klectApiProvider).publicUrl(target.coverPath),
      blurhash: target.coverBlurhash,
      aspectRatio: target.coverAspect,
      pressFeedback: false,
      child: card,
    );
  }
}

/// The bordered shell every target shape shares.
class _TargetShell extends StatelessWidget {
  const _TargetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: colors.borderSubtle,
          width: Strokes.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// "This content is unavailable" — a repost of vanished or hidden content
/// renders as a tombstone, never as an empty card.
class _TargetTombstone extends StatelessWidget {
  const _TargetTombstone();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return _TargetShell(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.visibility_off_outlined,
              size: Space.s5,
              color: colors.textTertiary,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'This content is unavailable',
                style:
                    context.kt.callout.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quoted post: author byline, body, first photo — X's quote card.
class _QuotedPostBody extends ConsumerWidget {
  const _QuotedPostBody({required this.target});

  final PulseTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final author = target.author;
    final api = ref.watch(klectApiProvider);
    final avatarUrl =
        api.publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);
    final coverUrl = api.publicUrl(target.coverPath);
    final when = target.createdAt;
    final body = target.body;

    return _TargetShell(
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrl,
                  name: author?.name,
                  size: Space.s6,
                  isVerified: author?.isVerified ?? false,
                ),
                const SizedBox(width: Space.s2),
                Flexible(
                  child: Text(
                    author?.name ?? 'Someone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.label,
                  ),
                ),
                if (author != null && author.username.isNotEmpty) ...<Widget>[
                  const SizedBox(width: Space.s1),
                  Flexible(
                    child: Text(
                      author.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.micro.copyWith(color: colors.textTertiary),
                    ),
                  ),
                ],
                if (when != null) ...<Widget>[
                  const SizedBox(width: Space.s1),
                  Text(
                    '· ${timeago.format(when, locale: 'en_short')}',
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
                ],
              ],
            ),
            if (body != null && body.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.s2),
              Text(
                body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.body,
              ),
            ],
            if (target.coverPath != null) ...<Widget>[
              const SizedBox(height: Space.s3),
              KBlurhashImage(
                url: coverUrl,
                blurhash: target.coverBlurhash,
                aspectRatio: (target.coverAspect ?? Aspect.cover)
                    .clamp(Aspect.gridMin, Aspect.gridMax),
                borderRadius: BorderRadius.circular(Radii.md),
                semanticLabel: body ?? 'Post photo',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shared collection / shelf / thing: cover, type label, title, counts.
class _EntityBody extends ConsumerWidget {
  const _EntityBody({required this.target});

  final PulseTarget target;

  IconData get _icon => switch (target.type) {
        EntityType.collection => Icons.collections_bookmark_rounded,
        EntityType.subcollection => Icons.layers_rounded,
        EntityType.item => Icons.photo_library_rounded,
        _ => Icons.mode_comment_rounded,
      };

  String get _typeLabel => switch (target.type) {
        EntityType.collection => 'Collection',
        EntityType.subcollection => 'Shelf',
        EntityType.item => 'Thing',
        _ => 'Comment',
      };

  String get _childLabel => switch (target.type) {
        EntityType.item => 'photos',
        _ => 'things',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final url = ref.watch(klectApiProvider).publicUrl(target.coverPath);

    return _TargetShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: PulseTargetCard.thumb,
            height: PulseTargetCard.thumb,
            child: KBlurhashImage(
              url: url,
              blurhash: target.coverBlurhash,
              semanticLabel: target.title ?? _typeLabel,
              borderRadius: BorderRadius.zero,
              memCacheWidth: (PulseTargetCard.thumb *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(_icon, size: Space.s3, color: colors.textTertiary),
                      const SizedBox(width: Space.s1),
                      Text(
                        _typeLabel.toUpperCase(),
                        style: text.micro.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    target.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyStrong,
                  ),
                  if (target.subtitle != null &&
                      target.subtitle!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.s05),
                    Text(
                      target.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                  if (target.childCount > 0) ...<Widget>[
                    const SizedBox(height: Space.s1),
                    Text(
                      '${formatCount(target.childCount)} $_childLabel',
                      style: text.micro.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads a [PulseTarget] for [entity] and renders it — the client-side path
/// for surfaces that have no embedded envelope (post closeup, composer).
class PulseTargetLoader extends ConsumerWidget {
  /// Creates a loader.
  const PulseTargetLoader({
    required this.entity,
    super.key,
    this.interactive = true,
  });

  /// What to preview.
  final EntityRef entity;

  /// Passed through to [PulseTargetCard].
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pulseTargetProvider(entity));
    final target = async.value;
    if (target == null) {
      if (async.hasError) return const _TargetTombstone();
      return const KShimmer(
        child: KSkeleton(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
          height: PulseTargetCard.thumb,
        ),
      );
    }
    return PulseTargetCard(target: target, interactive: interactive);
  }
}

/// Builds a [PulseTarget] client-side, in one cheap read per entity — the
/// same payload `pulse_target_payload` embeds server-side, for surfaces that
/// only hold an [EntityRef].
final pulseTargetProvider =
    FutureProvider.autoDispose.family<PulseTarget, EntityRef>(
  (ref, entity) async {
    final api = ref.watch(klectApiProvider);

    PulseTarget unavailable() =>
        PulseTarget(id: entity.id, type: entity.type, unavailable: true);

    switch (entity.type) {
      case EntityType.post:
        final post = await api.fetchPost(entity.id);
        if (post == null) return unavailable();
        final media = await api.fetchPostMedia(entity.id);
        final cover = media.isEmpty ? null : media.first;
        return PulseTarget(
          id: post.id,
          type: EntityType.post,
          body: post.body,
          kind: post.kind.wire,
          coverPath: cover?.storagePath,
          coverBlurhash: cover?.blurhash,
          coverWidth: cover?.width,
          coverHeight: cover?.height,
          childCount: post.replyCount,
          likeCount: post.likeCount,
          createdAt: post.createdAt,
          author: post.author,
        );

      case EntityType.item:
        final item = await api.fetchItem(entity.id);
        if (item == null) return unavailable();
        return PulseTarget(
          id: item.id,
          type: EntityType.item,
          title: item.title,
          subtitle: item.brand ?? item.description,
          coverPath: item.coverPath,
          coverBlurhash: item.coverBlurhash,
          coverWidth: item.coverWidth,
          coverHeight: item.coverHeight,
          childCount: item.mediaCount,
          likeCount: item.likeCount,
          createdAt: item.createdAt,
        );

      case EntityType.subcollection:
        final sub = await api.fetchSubcollection(entity.id);
        if (sub == null) return unavailable();
        return PulseTarget(
          id: sub.id,
          type: EntityType.subcollection,
          title: sub.name,
          subtitle: sub.description,
          coverPath: sub.coverPath,
          coverBlurhash: sub.coverBlurhash,
          childCount: sub.itemCount,
          likeCount: sub.likeCount,
          createdAt: sub.createdAt,
        );

      case EntityType.collection:
        final collection = await api.fetchCollection(entity.id);
        if (collection == null) return unavailable();
        return PulseTarget(
          id: collection.id,
          type: EntityType.collection,
          title: collection.name,
          subtitle: collection.description,
          coverPath: collection.coverPath,
          coverBlurhash: collection.coverBlurhash,
          childCount: collection.itemCount,
          likeCount: collection.likeCount,
          createdAt: collection.createdAt,
        );

      case EntityType.comment:
        return unavailable();
    }
  },
  name: 'pulseTarget',
);
