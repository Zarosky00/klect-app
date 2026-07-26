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

/// One row of the Pulse stream.
///
/// Four shapes, one card: an original post, a bare repost ("kenji reposted"),
/// a quote repost with commentary, and any of those carrying an inline
/// collection / shelf / thing.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final presenter = _presenter;
    final reposter = _reposterHeader;
    final attachment = item.attachment;
    final body = item.text;
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
                      if (attachment != null) ...<Widget>[
                        const SizedBox(height: Space.s3),
                        EntityAttachmentCard(entity: attachment),
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
