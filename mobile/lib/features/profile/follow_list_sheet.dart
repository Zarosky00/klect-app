import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'person_row.dart';
import 'profile_queries.dart';

/// Followers and following, in a draggable sheet rather than a route — you are
/// looking *at* a profile, not leaving it.
abstract final class FollowListSheet {
  /// Fraction of the screen the sheet may take.
  static const double heightFraction = 0.8;

  /// Opens the follower or following list for [userId].
  static Future<void> show(
    BuildContext context, {
    required String userId,
    required bool followers,
    String? subjectName,
  }) =>
      KSheet.show<void>(
        context: context,
        title: followers ? 'Followers' : 'Following',
        maxHeightFraction: heightFraction,
        builder: (sheetContext) => _FollowListBody(
          userId: userId,
          followers: followers,
          subjectName: subjectName,
        ),
      );
}

class _FollowListBody extends ConsumerWidget {
  const _FollowListBody({
    required this.userId,
    required this.followers,
    required this.subjectName,
  });

  final String userId;
  final bool followers;
  final String? subjectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        followers ? followersProvider(userId) : followingProvider(userId);
    final people = ref.watch(provider);

    return people.when(
      loading: () => const SingleChildScrollView(
        child: KSkeletonList(rows: 6, showMedia: false),
      ),
      error: (error, _) => KErrorState(
        error: error,
        compact: true,
        onRetry: () => ref.invalidate(provider),
      ),
      data: (list) => list.isEmpty
          ? KEmptyState(
              title: followers ? 'No followers yet' : 'Following nobody yet',
              message: followers
                  ? '${subjectName ?? 'This collector'} is early. '
                      'Be the first.'
                  : 'Shelves worth watching are one search away.',
              compact: true,
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.s4),
              itemCount: list.length,
              itemBuilder: (context, index) => PersonRow(
                profile: list[index],
                dense: true,
              ),
            ),
    );
  }
}

/// A tappable `12 · Followers` block from the profile header.
class ProfileCountStat extends StatelessWidget {
  /// Creates a stat.
  const ProfileCountStat({
    required this.label,
    required this.value,
    super.key,
    this.onTap,
  });

  /// What is being counted.
  final String label;

  /// The trigger-maintained counter column. Never a `COUNT(*)`.
  final int value;

  /// Tap handler; null renders a plain, non-interactive stat.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        KRollingCount(
          value: value,
          // Title-sized, but borrowing the count step's tabular figures so the
          // number never changes width while it rolls.
          style: context.kt.title3
              .copyWith(fontFeatures: context.kt.count.fontFeatures),
        ),
        Text(
          label,
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );

    if (onTap == null) return content;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: '$value $label',
      child: content,
    );
  }
}
