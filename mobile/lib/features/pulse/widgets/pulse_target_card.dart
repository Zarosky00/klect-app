import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import 'pulse_card.dart' show PostMediaGrid;
import 'pulse_media_peek.dart';

/// Renders the 0018 envelope's server-embedded `target` block: the quoted
/// post, or the shared collection / shelf / thing, or the tombstone when the
/// target is no longer visible to the viewer.
///
/// The same widget serves three surfaces — the Pulse stream (embedded
/// payload), the post closeup and the composer preview (payload built
/// client-side by [pulseTargetProvider]).
///
/// Gestures, when [interactive]:
///  * a quoted post opens its thread; a reposted comment opens its parent
///    discussion — plain tap only;
///  * a collection / shelf / thing opens its **Surf closeup** on tap and the
///    immersive viewer on double tap;
///  * only the photos peek on long press — holding the text does nothing.
class PulseTargetCard extends ConsumerWidget {
  /// Creates a target card.
  const PulseTargetCard({
    required this.target,
    super.key,
    this.interactive = true,
    this.media = const <ItemMedia>[],
  });

  /// The embedded payload.
  final PulseTarget target;

  /// Whether the card carries its gestures. Turn off inside the composer,
  /// where a tap must not navigate away from a draft.
  final bool interactive;

  /// Complete original post media when a caller has it.
  final List<ItemMedia> media;

  /// Height of the entity cover thumbnail.
  static const double thumb = Space.s20;

  /// Height ceiling for a single embedded photo, so an attachment previews
  /// inside its row instead of taking over the screen.
  static const double mediaMaxHeight = Space.s24 * 2.5;

  /// A comment target deep-links to the discussion it lives under —
  /// `parent_type`/`parent_id` arrived with the 0021 comment branch.
  String? get _commentDestination {
    final parentType = target.parentType;
    final parentId = target.parentId;
    if (parentType == null || parentId == null) return null;
    if (parentType == EntityType.post) {
      return KlectLinks.postThreadPath(parentId);
    }
    return KlectLinks.closeupPath(parentType, parentId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (target.unavailable || target.type == null) {
      return const _TargetTombstone();
    }

    final resolvedMedia = media.isEmpty ? target.media : media;
    final type = target.type!;
    final card = switch (type) {
      EntityType.post => _QuotedPostBody(
        target: target,
        media: resolvedMedia,
        peekable: interactive,
      ),
      EntityType.comment => _CommentBody(target: target),
      _ => _EntityBody(target: target, peekable: interactive),
    };

    if (!interactive) return card;

    if (type == EntityType.post) {
      return KGestureRegion(
        semanticLabel: target.body ?? target.author?.name,
        onTap: () => context.push(KlectLinks.postThreadPath(target.id)),
        child: card,
      );
    }
    if (type == EntityType.comment) {
      final destination = _commentDestination;
      return KGestureRegion(
        semanticLabel: target.body ?? target.author?.name,
        onTap: destination == null ? null : () => context.push(destination),
        child: card,
      );
    }

    return PulseSurfCard(
      entity: EntityRef(type, target.id),
      semanticLabel: target.title ?? target.body ?? target.author?.name,
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
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderDefault, width: Strokes.hairline),
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
                style: context.kt.callout.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact author line: small avatar · name · @handle · time.
class _MiniByline extends ConsumerWidget {
  const _MiniByline({required this.author, this.at});

  final Profile? author;
  final DateTime? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final author = this.author;
    final when = at;
    final avatarUrl = author?.avatarPath == null
        ? null
        : ref
              .watch(klectApiProvider)
              .publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);
    return Row(
      children: <Widget>[
        KAvatar(
          imageUrl: avatarUrl,
          name: author?.name,
          size: Space.s5,
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
              style: text.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
        if (when != null) ...<Widget>[
          const SizedBox(width: Space.s1),
          Text(
            '· ${timeago.format(when, locale: 'en_short')}',
            style: text.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// A single cover photo bounded to [maxHeight], with the long-press peek.
class _BoundedCover extends ConsumerWidget {
  const _BoundedCover({
    required this.path,
    required this.maxHeight,
    required this.radius,
    this.blurhash,
    this.aspect,
    this.semanticLabel,
    this.peek,
  });

  final String path;
  final String? blurhash;
  final double? aspect;
  final double maxHeight;
  final BorderRadius radius;
  final String? semanticLabel;
  final PulsePeekTarget? peek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(klectApiProvider).publicUrl(path);
    return LayoutBuilder(
      builder: (context, constraints) => PulsePeekableMedia(
        peek: peek,
        imageUrl: url,
        blurhash: blurhash,
        aspectRatio: aspect,
        child: KBlurhashImage(
          url: url,
          blurhash: blurhash,
          aspectRatio: PostMediaGrid.boundedAspect(
            aspect ?? Aspect.cover,
            constraints.maxWidth,
            maxHeight,
          ),
          borderRadius: radius,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

/// A quoted post: author byline, body, photos — X's quote card.
class _QuotedPostBody extends StatelessWidget {
  const _QuotedPostBody({
    required this.target,
    required this.media,
    required this.peekable,
  });

  final PulseTarget target;
  final List<ItemMedia> media;
  final bool peekable;

  @override
  Widget build(BuildContext context) {
    final text = context.kt;
    final body = target.body;
    final coverPath = target.coverPath;
    final peek = peekable
        ? PulsePeekTarget(
            entity: EntityRef.post(target.id),
            title: body ?? target.author?.name,
            subtitle: target.author?.handle,
          )
        : null;

    return _TargetShell(
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _MiniByline(author: target.author, at: target.createdAt),
            if (body != null && body.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.s2),
              Text(
                body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.callout,
              ),
            ],
            if (media.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.s3),
              _QuotedMediaGrid(
                media: media,
                peek: peek,
                radius: BorderRadius.circular(Radii.md),
              ),
            ] else if (coverPath != null) ...<Widget>[
              const SizedBox(height: Space.s3),
              _BoundedCover(
                path: coverPath,
                blurhash: target.coverBlurhash,
                aspect: target.coverAspect,
                maxHeight: PulseTargetCard.mediaMaxHeight,
                radius: BorderRadius.circular(Radii.md),
                semanticLabel: body ?? 'Post photo',
                peek: peek,
              ),
            ],
            if (target.attachedTarget case final attached?) ...<Widget>[
              const SizedBox(height: Space.s3),
              PulseTargetCard(target: attached, interactive: false),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuotedMediaGrid extends ConsumerWidget {
  const _QuotedMediaGrid({
    required this.media,
    required this.radius,
    this.peek,
  });

  final List<ItemMedia> media;
  final BorderRadius radius;
  final PulsePeekTarget? peek;

  static const double _gap = Space.s05;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(klectApiProvider);
    final shots = media.take(4).toList(growable: false);

    Widget image(ItemMedia item, {double? aspectRatio}) {
      final url = api.publicUrl(item.storagePath);
      return PulsePeekableMedia(
        peek: peek,
        imageUrl: url,
        blurhash: item.blurhash,
        aspectRatio: _aspectOf(item),
        child: KBlurhashImage(
          url: url,
          blurhash: item.blurhash,
          aspectRatio: aspectRatio,
          borderRadius: BorderRadius.zero,
          semanticLabel: item.altText ?? 'Photo',
        ),
      );
    }

    if (shots.length == 1) {
      final item = shots.first;
      return LayoutBuilder(
        builder: (context, constraints) => ClipRRect(
          borderRadius: radius,
          child: image(
            item,
            aspectRatio: PostMediaGrid.boundedAspect(
              _aspectOf(item) ?? Aspect.cover,
              constraints.maxWidth,
              PulseTargetCard.mediaMaxHeight,
            ),
          ),
        ),
      );
    }

    final grid = switch (shots.length) {
      2 => Row(
        children: <Widget>[
          Expanded(child: image(shots[0])),
          const SizedBox(width: _gap),
          Expanded(child: image(shots[1])),
        ],
      ),
      3 => Row(
        children: <Widget>[
          Expanded(child: image(shots[0])),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              children: <Widget>[
                Expanded(child: image(shots[1])),
                const SizedBox(height: _gap),
                Expanded(child: image(shots[2])),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: image(shots[0])),
                const SizedBox(width: _gap),
                Expanded(child: image(shots[1])),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: image(shots[2])),
                const SizedBox(width: _gap),
                Expanded(child: image(shots[3])),
              ],
            ),
          ),
        ],
      ),
    };

    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(aspectRatio: Aspect.gridMax, child: grid),
    );
  }

  static double? _aspectOf(ItemMedia item) {
    final width = item.width;
    final height = item.height;
    if (width == null || height == null || height <= 0) return null;
    return width / height;
  }
}

/// A reposted comment: author byline, the comment's own words, and a hint at
/// the discussion it came from. Before 0021 this fell through to the entity
/// card and rendered an empty title — now the body *is* the card.
class _CommentBody extends StatelessWidget {
  const _CommentBody({required this.target});

  final PulseTarget target;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
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
                Icon(
                  Icons.mode_comment_outlined,
                  size: Space.s3,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: Space.s1),
                Text(
                  'COMMENT',
                  style: text.micro.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            _MiniByline(author: target.author, at: target.createdAt),
            if (body != null && body.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.s2),
              Text(
                body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.callout,
              ),
            ],
            if (target.parentId != null) ...<Widget>[
              const SizedBox(height: Space.s2),
              Text(
                'From a discussion — tap to open it',
                style: text.micro.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shared collection / shelf / thing — photos edge to edge on top, then
/// the type, title, description and owner. The whole card is the way into
/// the entity's Surf closeup.
class _EntityBody extends StatelessWidget {
  const _EntityBody({required this.target, required this.peekable});

  final PulseTarget target;
  final bool peekable;

  IconData get _icon => switch (target.type) {
    EntityType.collection => Icons.collections_bookmark_outlined,
    EntityType.subcollection => Icons.layers_outlined,
    EntityType.item => Icons.photo_library_outlined,
    _ => Icons.mode_comment_outlined,
  };

  String get _typeLabel => switch (target.type) {
    EntityType.collection => 'Collection',
    EntityType.subcollection => 'Shelf',
    EntityType.item => 'Thing',
    _ => 'Comment',
  };

  String get _childLabel => switch (target.type) {
    EntityType.item => target.childCount == 1 ? 'photo' : 'photos',
    _ => target.childCount == 1 ? 'thing' : 'things',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final author = target.author;
    final coverPath = target.coverPath;
    final subtitle = target.subtitle;
    final peek = peekable && target.type != null
        ? PulsePeekTarget(
            entity: EntityRef(target.type!, target.id),
            title: target.title ?? _typeLabel,
            subtitle: author?.handle,
          )
        : null;

    return _TargetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (target.media.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey<String>('pulse-target-media-grid'),
              child: _QuotedMediaGrid(
                media: target.media,
                peek: peek,
                radius: BorderRadius.zero,
              ),
            )
          else if (coverPath != null)
            _BoundedCover(
              path: coverPath,
              blurhash: target.coverBlurhash,
              aspect: target.coverAspect,
              maxHeight: PulseTargetCard.mediaMaxHeight,
              radius: BorderRadius.zero,
              semanticLabel: target.title ?? _typeLabel,
              peek: peek,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s3,
              Space.s3,
              Space.s3,
              Space.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (target.childCount > 0) ...<Widget>[
                      Text(
                        '  ·  ',
                        style: text.micro.copyWith(color: colors.textTertiary),
                      ),
                      Text(
                        '${formatCount(target.childCount)} $_childLabel',
                        style: text.micro.copyWith(color: colors.textTertiary),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.north_east_rounded,
                      size: Space.s4,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: Space.s15),
                Text(
                  target.title ?? _typeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyStrong,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.s05),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (author != null) ...<Widget>[
                  const SizedBox(height: Space.s25),
                  _MiniByline(author: author),
                ],
              ],
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
final pulseTargetProvider = FutureProvider.autoDispose
    .family<PulseTarget, EntityRef>((ref, entity) async {
      final api = ref.watch(klectApiProvider);

      PulseTarget unavailable() =>
          PulseTarget(id: entity.id, type: entity.type, unavailable: true);

      switch (entity.type) {
        case EntityType.post:
          final post = await api.fetchPost(entity.id);
          if (post == null) return unavailable();
          final media = await api.fetchPostMedia(entity.id);
          final cover = media.isEmpty ? null : media.first;
          final attached = post.entityType == null || post.entityId == null
              ? null
              : await _loadAttachedTarget(
                  api,
                  EntityRef(post.entityType!, post.entityId!),
                );
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
            quoteCount: post.quoteCount,
            createdAt: post.createdAt,
            author: post.author,
            media: media,
            attachedTarget: attached,
          );

        case EntityType.item:
          final item = await api.fetchItem(entity.id);
          if (item == null) return unavailable();
          final itemOwner = item.userId == null
              ? null
              : await api.fetchProfile(item.userId!);
          final media = await api.fetchItemMedia(item.id);
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
            quoteCount: item.quoteCount,
            createdAt: item.createdAt,
            author: itemOwner,
            media: media,
          );

        case EntityType.subcollection:
          final sub = await api.fetchSubcollection(entity.id);
          if (sub == null) return unavailable();
          final subOwner = sub.userId == null
              ? null
              : await api.fetchProfile(sub.userId!);
          return PulseTarget(
            id: sub.id,
            type: EntityType.subcollection,
            title: sub.name,
            subtitle: sub.description,
            coverPath: sub.coverPath,
            coverBlurhash: sub.coverBlurhash,
            childCount: sub.itemCount,
            likeCount: sub.likeCount,
            quoteCount: sub.quoteCount,
            createdAt: sub.createdAt,
            author: subOwner,
          );

        case EntityType.collection:
          final collection = await api.fetchCollection(entity.id);
          if (collection == null) return unavailable();
          final collectionOwner = collection.userId == null
              ? null
              : await api.fetchProfile(collection.userId!);
          return PulseTarget(
            id: collection.id,
            type: EntityType.collection,
            title: collection.name,
            subtitle: collection.description,
            coverPath: collection.coverPath,
            coverBlurhash: collection.coverBlurhash,
            childCount: collection.itemCount,
            likeCount: collection.likeCount,
            quoteCount: collection.quoteCount,
            createdAt: collection.createdAt,
            author: collectionOwner,
          );

        case EntityType.comment:
          return unavailable();
      }
    }, name: 'pulseTarget');

Future<PulseTarget?> _loadAttachedTarget(KlectApi api, EntityRef entity) async {
  switch (entity.type) {
    case EntityType.item:
      final item = await api.fetchItem(entity.id);
      if (item == null) return null;
      final owner = item.userId == null
          ? null
          : await api.fetchProfile(item.userId!);
      final media = await api.fetchItemMedia(item.id);
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
        quoteCount: item.quoteCount,
        createdAt: item.createdAt,
        author: owner,
        media: media,
      );
    case EntityType.subcollection:
      final sub = await api.fetchSubcollection(entity.id);
      if (sub == null) return null;
      final owner = sub.userId == null
          ? null
          : await api.fetchProfile(sub.userId!);
      return PulseTarget(
        id: sub.id,
        type: EntityType.subcollection,
        title: sub.name,
        subtitle: sub.description,
        coverPath: sub.coverPath,
        coverBlurhash: sub.coverBlurhash,
        childCount: sub.itemCount,
        likeCount: sub.likeCount,
        quoteCount: sub.quoteCount,
        createdAt: sub.createdAt,
        author: owner,
      );
    case EntityType.collection:
      final collection = await api.fetchCollection(entity.id);
      if (collection == null) return null;
      final owner = collection.userId == null
          ? null
          : await api.fetchProfile(collection.userId!);
      return PulseTarget(
        id: collection.id,
        type: EntityType.collection,
        title: collection.name,
        subtitle: collection.description,
        coverPath: collection.coverPath,
        coverBlurhash: collection.coverBlurhash,
        childCount: collection.itemCount,
        likeCount: collection.likeCount,
        quoteCount: collection.quoteCount,
        createdAt: collection.createdAt,
        author: owner,
      );
    case EntityType.post || EntityType.comment:
      return null;
  }
}
