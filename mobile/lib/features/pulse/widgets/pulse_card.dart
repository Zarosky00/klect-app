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
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          presenter?.avatarPath,
          bucket: StorageBucket.avatars,
        );

    return KEntityGestureCard(
      entity: item.entity,
      title: body ?? presenter?.name,
      subtitle: presenter?.handle,
      pressFeedback: false,
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
                        style: text.micro
                            .copyWith(color: colors.textSecondary),
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
                      : () => context
                          .push(KlectLinks.profilePath(presenter.username)),
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
                        PostMediaGrid(media: item.media),
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
                        entity: item.entity,
                        seed: item.seed,
                        compact: true,
                        alignment: MainAxisAlignment.start,
                        shareTitle: body ?? presenter?.name,
                        onComment: () => context.push(
                          KlectLinks.closeupPath(
                            item.entity.type,
                            item.entity.id,
                          ),
                        ),
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

/// The photo of a bare-reposted post, rendered inline (unboxed).
class _InlinePostCover extends ConsumerWidget {
  const _InlinePostCover({required this.target});

  final PulseTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(klectApiProvider).publicUrl(target.coverPath);
    return KBlurhashImage(
      url: url,
      blurhash: target.coverBlurhash,
      aspectRatio: (target.coverAspect ?? Aspect.cover)
          .clamp(Aspect.gridMin, Aspect.gridMax),
      borderRadius: BorderRadius.circular(Radii.lg),
      semanticLabel: target.body ?? 'Post photo',
    );
  }
}

/// X's media grid: one photo full-width at its own ratio, two side by side,
/// three as one tall + two stacked, four as a 2×2 — all inside one rounded
/// clip, every box reserved before a byte arrives.
class PostMediaGrid extends ConsumerWidget {
  /// Creates the grid.
  const PostMediaGrid({required this.media, super.key});

  /// The post's photos, in position order (at most four render).
  final List<ItemMedia> media;

  /// Gap between grid cells.
  static const double _gap = Space.s05;

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
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: image(
          m,
          aspectRatio: intrinsic.clamp(Aspect.gridMin, Aspect.gridMax),
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
