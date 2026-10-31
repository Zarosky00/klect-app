import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// Opens [author]'s profile (`/u/:username`), or returns null when there is
/// no profile to open (missing author, empty username, deleted comment).
VoidCallback? commentAuthorProfileTap(
  BuildContext context,
  Profile? author, {
  bool tombstone = false,
}) {
  if (tombstone || author == null || author.username.isEmpty) return null;
  return () => context.push(KlectLinks.profilePath(author.username));
}

/// The avatar at the head of a comment row, tappable through to the
/// commenter's profile.
///
/// The avatar itself stays at [size], but the tap area also covers the gap
/// to the comment body and a strip under the avatar, so the target is close
/// to the 44pt floor without shifting the row's layout. The gap is part of
/// this widget — do not add another one after it.
class CommentAuthorAvatar extends ConsumerWidget {
  /// Creates the avatar for [author].
  const CommentAuthorAvatar({
    required this.author,
    super.key,
    this.tombstone = false,
    this.size = Space.s8,
    this.gap = Space.s3,
  });

  /// Who wrote the comment.
  final Profile? author;

  /// A deleted comment shows a blank, inert avatar.
  final bool tombstone;

  /// Avatar diameter.
  final double size;

  /// Space between the avatar and the comment body, included in the hit area.
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = tombstone ? null : author;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(profile?.avatarPath, bucket: StorageBucket.avatars);
    final onTap = commentAuthorProfileTap(
      context,
      author,
      tombstone: tombstone,
    );

    final avatar = Padding(
      padding: EdgeInsets.only(right: gap, bottom: Space.s2),
      child: KAvatar(
        imageUrl: profile == null ? null : avatarUrl,
        name: profile?.name,
        size: size,
        isVerified: profile?.isVerified ?? false,
      ),
    );
    if (onTap == null) return avatar;
    return KPressable(
      key: const ValueKey<String>('comment-author-avatar'),
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Open ${profile!.name}’s profile',
      child: avatar,
    );
  }
}

/// The commenter's name, tappable through to their profile.
class CommentAuthorName extends StatelessWidget {
  /// Creates the name label.
  const CommentAuthorName({
    required this.author,
    super.key,
    this.tombstone = false,
  });

  /// Who wrote the comment.
  final Profile? author;

  /// A deleted comment reads "Deleted" and is inert.
  final bool tombstone;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      tombstone ? 'Deleted' : author?.name ?? 'Someone',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.kt.label,
    );
    final onTap = commentAuthorProfileTap(
      context,
      author,
      tombstone: tombstone,
    );
    if (onTap == null) return label;
    return KPressable(
      key: const ValueKey<String>('comment-author-name'),
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Open ${author!.name}’s profile',
      child: label,
    );
  }
}
