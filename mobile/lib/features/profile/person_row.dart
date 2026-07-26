import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'follow_button.dart';
import 'profile_queries.dart';
import 'user_actions.dart';

/// One person, rendered the same way everywhere they appear.
///
/// Follower lists, search results, blocked and muted lists, match cards and
/// notifications all use this, so a collector looks like the same collector on
/// every surface — and the safety overflow is one long press away from all of
/// them.
class PersonRow extends ConsumerWidget {
  /// Creates a person row.
  const PersonRow({
    required this.profile,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showFollow = true,
    this.dense = false,
  });

  /// Who this row is about.
  final Profile profile;

  /// Overrides the `@handle` second line — e.g. "12 shared tags".
  final String? subtitle;

  /// Replaces the trailing follow button, e.g. with an "Unblock" control.
  final Widget? trailing;

  /// Overrides the default "open their profile" tap.
  final VoidCallback? onTap;

  /// Whether to render the follow button when no [trailing] is given.
  final bool showFollow;

  /// Tighter vertical rhythm, for use inside sheets.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final isSelf = ref.watch(currentUserIdProvider) == profile.id;

    return KPressable(
      onTap: onTap ??
          () => context.push(KlectLinks.profilePath(profile.username)),
      onLongPress: () => UserActions.showOverflow(context, profile: profile),
      enforceMinTapTarget: false,
      semanticLabel: '${profile.name}, ${profile.handle}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? Space.s2 : Space.s3),
        child: Row(
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrlOf(api, profile.avatarPath),
              name: profile.name,
              isVerified: profile.isVerified,
              size: dense ? Space.s10 : Space.s12,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    profile.name,
                    style: context.kt.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle ?? profile.handle,
                    style: context.kt.caption
                        .copyWith(color: colors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle == null && (profile.bio?.isNotEmpty ?? false))
                    Text(
                      profile.bio!,
                      style: context.kt.caption
                          .copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showFollow && !isSelf) ...<Widget>[
              const SizedBox(width: Space.s3),
              FollowButton(
                userId: profile.id,
                followerCount: profile.followerCount,
                size: KButtonSize.small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
