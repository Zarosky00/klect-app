import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/klect_api.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../surf/surf.dart';
import '../data/pulse_entry_view.dart';
import 'entity_attachment_card.dart';
import 'pulse_target_card.dart';

/// One row of the Pulse stream.
///
/// Four shapes, one card: an original post (now with up to four of its own
/// photos), a bare repost ("kenji reposted"), a quote with commentary, and
/// any of those carrying the server-embedded target — a quoted-post card or
/// an entity card, with a tombstone when the target is gone.
///
/// **Pulse rows are not Surf tiles.** A plain tap opens the post's thread
/// (`/post/:id`) — there is no double-tap immersive and no hero flight,
/// because a stream row's destination is the discussion, not the photograph.
/// The long-press peek stays: like/save/repost/share/report is one gesture
/// away everywhere.
///
/// The action bar underneath is the *same* bar the Closeup uses, wired to the
/// same optimistic engine — a like here and a like there are the same like.
class PulseCard extends ConsumerWidget {
  /// Creates a Pulse card.
  const PulseCard({required this.item, super.key});

  /// The normalised row.
  final PulseItem item;

  /// Whose name and avatar head the card.
  Profile? get _presenter => switch (item.kind) {
    PulseKind.quote => item.reposter ?? item.author,
    _ => item.author ?? item.reposter,
  };

  /// The "X reposted" line, shown only for a bare repost — a quote already
  /// reads as the quoter's own post.
  Profile? get _reposterHeader =>
      item.kind == PulseKind.repost ? item.reposter : null;

  /// A bare repost of a post renders the post's content **inline** — byline,
  /// body and photo — instead of boxing the same author twice.
  PulseTarget? get _inlinePost {
    final target = item.target;
    if (item.kind != PulseKind.repost) return null;
    if (target == null || target.type != EntityType.post) return null;
    return target;
  }

  /// Where a plain tap lands.
  ///
  ///  * a post/quote row (or a bare repost **of a post**) → its thread;
  ///  * a repost of a comment → the discussion the comment lives under;
  ///  * a repost of a collection/shelf/thing → that entity's closeup.
  String? get _destination {
    final postId = item.postId;
    if (postId != null && postId.isNotEmpty) {
      return KlectLinks.postThreadPath(postId);
    }
    final inline = _inlinePost;
    if (inline != null && !inline.unavailable && inline.id.isNotEmpty) {
      return KlectLinks.postThreadPath(inline.id);
    }
    final entity = item.entity;
    if (entity.type == EntityType.comment) {
      final target = item.target;
      final parentType = target?.parentType;
      final parentId = target?.parentId;
      if (parentType == EntityType.post && parentId != null) {
        return KlectLinks.postThreadPath(parentId);
      }
      if (parentType != null && parentId != null) {
        return KlectLinks.closeupPath(parentType, parentId);
      }
      return null;
    }
    return KlectLinks.closeupPath(entity.type, entity.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final presenter = _presenter;
    final reposter = _reposterHeader;
    final inlinePost = _inlinePost;
    final target = inlinePost == null ? item.target : null;
    final body = inlinePost == null
        ? item.text
        : (inlinePost.unavailable ? null : inlinePost.body);
    final actionEntity = item.entity;
    final firstMedia = item.media.isEmpty ? null : item.media.first;
    final quotePreview = actionEntity.type == EntityType.post
        ? inlinePost ??
              PulseTarget(
                id: actionEntity.id,
                type: EntityType.post,
                body: body,
                coverPath: firstMedia?.storagePath,
                coverBlurhash: firstMedia?.blurhash,
                coverWidth: firstMedia?.width,
                coverHeight: firstMedia?.height,
                createdAt: item.sortAt,
                author: presenter,
              )
        : (item.target?.id == actionEntity.id ? item.target : null);
    final quoteMedia =
        actionEntity.type == EntityType.post && inlinePost == null
        ? item.media
        : const <ItemMedia>[];
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(presenter?.avatarPath, bucket: StorageBucket.avatars);
    final destination = _destination;

    return KGestureRegion(
      semanticLabel: body ?? presenter?.name,
      onTap: destination == null ? null : () => context.push(destination),
      onLongPress: () => unawaited(
        KPeekMenu.show(
          context,
          entity: item.entity,
          title: body ?? presenter?.name,
          subtitle: presenter?.handle,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s4,
          Space.s4,
          Space.s3,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (reposter != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: Space.s12,
                  bottom: Space.s2,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.repeat_rounded,
                      size: Space.s4,
                      color: colors.actionRepost,
                    ),
                    const SizedBox(width: Space.s15),
                    Flexible(
                      child: Text(
                        '${reposter.name} reposted',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.micro.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrl,
                  name: presenter?.name,
                  size: Space.s10,
                  isVerified: presenter?.isVerified ?? false,
                  onTap: presenter == null || presenter.username.isEmpty
                      ? null
                      : () => context.push(
                          KlectLinks.profilePath(presenter.username),
                        ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Byline(presenter: presenter, at: item.sortAt),
                      if (body != null && body.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Space.s1),
                        Text(body, style: text.body),
                      ],
                      if (item.media.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Space.s3),
                        // Bounded in the stream: a tall photo previews inside
                        // the row instead of masquerading as a masonry tile.
                        PostMediaGrid(
                          media: item.media,
                          maxHeight: PostMediaGrid.streamMaxHeight,
                        ),
                      ],
                      if (inlinePost != null) ...<Widget>[
                        if (inlinePost.unavailable) ...<Widget>[
                          const SizedBox(height: Space.s3),
                          PulseTargetCard(target: inlinePost),
                        ] else if (inlinePost.coverPath != null) ...<Widget>[
                          const SizedBox(height: Space.s3),
                          _InlinePostCover(target: inlinePost),
                        ],
                      ],
                      if (target != null) ...<Widget>[
                        const SizedBox(height: Space.s3),
                        PulseTargetCard(target: target),
                      ] else if (inlinePost == null &&
                          item.attachment != null) ...<Widget>[
                        // Legacy fallback: an envelope without an embedded
                        // target still gets a client-resolved entity card.
                        const SizedBox(height: Space.s3),
                        EntityAttachmentCard(entity: item.attachment!),
                      ],
                      const SizedBox(height: Space.s2),
                      KActionBar(
                        entity: actionEntity,
                        seed: item.seed,
                        compact: true,
                        alignment: MainAxisAlignment.start,
                        shareTitle: body ?? presenter?.name,
                        quotePreview: quotePreview,
                        quoteMedia: quoteMedia,
                        onComment: destination == null
                            ? null
                            : () => context.push(destination),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo of a bare-reposted post, rendered inline (unboxed) and bounded
/// like every other stream photo.
class _InlinePostCover extends ConsumerWidget {
  const _InlinePostCover({required this.target});

  final PulseTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(klectApiProvider).publicUrl(target.coverPath);
    return LayoutBuilder(
      builder: (context, constraints) => KBlurhashImage(
        url: url,
        blurhash: target.coverBlurhash,
        aspectRatio: PostMediaGrid.boundedAspect(
          target.coverAspect ?? Aspect.cover,
          constraints.maxWidth,
          PostMediaGrid.streamMaxHeight,
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
        semanticLabel: target.body ?? 'Post photo',
      ),
    );
  }
}

/// X's media grid: one photo full-width at its own ratio, two side by side,
/// three as one tall + two stacked, four as a 2×2 — all inside one rounded
/// clip, every box reserved before a byte arrives.
///
/// Pass [maxHeight] to bound a single photo's height — the Pulse stream does,
/// so a portrait shot reads as an inline preview instead of a masonry tile.
/// The thread screen leaves it null and shows the photo at its own ratio.
class PostMediaGrid extends ConsumerWidget {
  /// Creates the grid.
  const PostMediaGrid({required this.media, super.key, this.maxHeight});

  /// The post's photos, in position order (at most four render).
  final List<ItemMedia> media;

  /// Height ceiling for the single-photo layout. Null = unbounded.
  final double? maxHeight;

  /// The stream's single-photo ceiling — composed from the 4pt grid
  /// (`Space.s24 × 4`), matching web's bounded inline preview.
  static const double streamMaxHeight = Space.s24 * 4;

  /// Gap between grid cells.
  static const double _gap = Space.s05;

  /// The aspect ratio that renders [intrinsic] inside [width] without
  /// exceeding [maxHeight]: the intrinsic ratio (clamped to the grid band)
  /// widened until the resulting height fits the ceiling.
  static double boundedAspect(
    double intrinsic,
    double width,
    double? maxHeight,
  ) {
    final clamped = intrinsic.clamp(Aspect.gridMin, Aspect.gridMax).toDouble();
    if (maxHeight == null || maxHeight <= 0 || width <= 0) return clamped;
    final floor = width / maxHeight;
    return clamped < floor ? floor : clamped;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (media.isEmpty) return const SizedBox.shrink();
    final api = ref.watch(klectApiProvider);
    final shots = media.take(4).toList(growable: false);

    Widget image(ItemMedia m, {double? aspectRatio}) => KBlurhashImage(
      url: api.publicUrl(m.storagePath),
      blurhash: m.blurhash,
      aspectRatio: aspectRatio,
      borderRadius: BorderRadius.zero,
      semanticLabel: m.altText ?? 'Post photo',
    );

    if (shots.length == 1) {
      final m = shots.first;
      final intrinsic = (m.width != null && m.height != null && m.height! > 0)
          ? m.width! / m.height!
          : Aspect.cover;
      return LayoutBuilder(
        builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: image(
            m,
            aspectRatio: boundedAspect(
              intrinsic,
              constraints.maxWidth,
              maxHeight,
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
      borderRadius: BorderRadius.circular(Radii.lg),
      child: AspectRatio(aspectRatio: Aspect.gridMax, child: grid),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({required this.presenter, required this.at});

  final Profile? presenter;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final when = at;

    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            presenter?.name ?? 'Someone',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyStrong,
          ),
        ),
        if (presenter != null && presenter!.username.isNotEmpty) ...<Widget>[
          const SizedBox(width: Space.s1),
          Flexible(
            child: Text(
              presenter!.handle,
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
