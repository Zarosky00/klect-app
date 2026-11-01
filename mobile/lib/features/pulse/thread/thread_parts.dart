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

/// Pieces shared by the two Pulse discussion pages — the post thread
/// (`/post/:id`) and the repost page (`/repost/:type/:id`) — so a quote and
/// a repost open into the same reading layout.

/// "9:41 PM · 31 Oct 2026" — the full timestamp under a thread's content.
String formatThreadTimestamp(DateTime at) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = at.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $meridiem · '
      '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Avatar · name · @handle · follow, with the optional "X reposted" line
/// above it.
class ThreadAuthorHeader extends ConsumerWidget {
  /// Creates the header.
  const ThreadAuthorHeader({
    required this.author,
    required this.showFollow,
    super.key,
    this.reposter,
  });

  /// Who made the thing being discussed.
  final Profile? author;

  /// Who put it in the viewer's Pulse, when that is somebody else.
  final Profile? reposter;

  /// Whether the follow control renders (hidden on the viewer's own content).
  final bool showFollow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final author = this.author;
    final reposter = this.reposter;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (reposter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
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
        Row(
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrl,
              name: author?.name,
              size: Space.s12,
              isVerified: author?.isVerified ?? false,
              onTap: author == null || author.username.isEmpty
                  ? null
                  : () => context.push(KlectLinks.profilePath(author.username)),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    author?.name ?? 'Someone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyStrong,
                  ),
                  if (author != null && author.username.isNotEmpty)
                    Text(
                      author.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.caption.copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
            if (showFollow && author != null) ...<Widget>[
              const SizedBox(width: Space.s2),
              FollowButton(
                userId: author.id,
                displayName: author.name,
                avatarPath: author.avatarPath,
                followerCount: author.followerCount,
                size: KButtonSize.small,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The X stats line: bold counts, quiet labels, live off the optimistic
/// engine — likes · reposts · saves · views.
class ThreadStatsRow extends ConsumerWidget {
  /// Creates the stats row for [entity].
  const ThreadStatsRow({required this.entity, super.key});

  /// Whose counters to show.
  final EntityRef entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(interactionProvider(entity));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s3),
      child: Wrap(
        spacing: Space.s4,
        runSpacing: Space.s1,
        children: <Widget>[
          _Stat(count: state.likeCount, label: 'Likes'),
          _Stat(count: state.repostCount, label: 'Reposts'),
          _Stat(count: state.saveCount, label: 'Saves'),
          _Stat(count: state.viewCount, label: 'Views'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(formatCount(count), style: context.kt.count),
        const SizedBox(width: Space.s1),
        Text(
          label,
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
