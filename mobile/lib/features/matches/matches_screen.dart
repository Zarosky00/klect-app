import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../profile/fill_viewport.dart';
import '../profile/follow_button.dart';
import '../profile/profile_queries.dart';
import '../profile/user_actions.dart';
import 'match_ring.dart';

/// Collectors ranked by taste overlap.
///
/// `get_matches` recomputes server-side on call and caches for six hours, so
/// pull-to-refresh is a real recompute rather than a cache read.
final matchesProvider = FutureProvider.autoDispose<List<MatchModel>>(
  (ref) => ref.watch(klectApiProvider).getMatches(),
  name: 'matches',
);

/// "Collectors like you".
///
/// The score is a ring on the four-stop match ramp, backed by a word — colour
/// is never the only signal — and evidenced by the tags you actually share
/// plus three of their shelves you can open right now.
class MatchesScreen extends ConsumerWidget {
  /// Creates the screen.
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchesProvider);
    final me = ref.watch(myProfileProvider).value;
    final optedOut = me != null && !me.showSimilarity;

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Collectors like you', showBack: true),
      onRefresh: () async => ref.invalidate(matchesProvider),
      body: optedOut
          ? FillViewport(
              child: KEmptyState(
                title: 'Taste matching is off',
                message: 'You turned similarity off in Privacy, so we do not '
                    'compare your shelves with anyone else.',
                icon: Icons.visibility_off_outlined,
                actionLabel: 'Open privacy settings',
                onAction: () => context.push('/settings/privacy'),
              ),
            )
          : matches.when(
              loading: () => const FillViewport(
                child: KSkeletonList(rows: 4),
              ),
              error: (error, _) => FillViewport(
                child: KErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(matchesProvider),
                ),
              ),
              data: (people) => people.isEmpty
                  ? FillViewport(
                      child: KEmptyState(
                        title: 'No matches yet',
                        message: 'Matching runs on the tags your collections '
                            'carry. Add a few things and collectors with the '
                            'same taste will surface here.',
                        icon: Icons.auto_awesome_outlined,
                        actionLabel: 'Go surfing',
                        onAction: () => context.go('/surf'),
                        secondaryActionLabel: 'Start a collection',
                        onSecondaryAction: () =>
                            context.push('/create/collection'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s5,
                        Space.s4,
                        Space.s5,
                        Space.s20,
                      ),
                      itemCount: people.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: Space.s3),
                      itemBuilder: (context, index) =>
                          MatchCard(match: people[index]),
                    ),
            ),
    );
  }
}

/// One collector, with the evidence behind the score.
class MatchCard extends ConsumerWidget {
  /// Creates a match card.
  const MatchCard({required this.match, super.key});

  /// The ranked collector.
  final MatchModel match;

  /// How many shared tags show before the overflow chip.
  static const int visibleTags = 4;

  /// How many of their shelves are previewed.
  static const int previewShelves = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final person = match.profile;
    final tint = MatchScale.colorFor(colors, match.percent);

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MatchRing(
                percent: match.percent,
                child: KAvatar(
                  imageUrl: avatarUrlOf(api, person.avatarPath),
                  name: person.name,
                  size: Space.s12,
                  isVerified: person.isVerified,
                  onTap: () =>
                      context.push(KlectLinks.profilePath(person.username)),
                ),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      person.name,
                      style: context.kt.title3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      person.handle,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                    const SizedBox(height: Space.s15),
                    Row(
                      children: <Widget>[
                        Text(
                          '${match.percent}%',
                          style: context.kt.count.copyWith(color: tint),
                        ),
                        const SizedBox(width: Space.s15),
                        Flexible(
                          child: Text(
                            MatchScale.labelFor(match.percent),
                            style: context.kt.caption.copyWith(color: tint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              KIconButton(
                icon: Icons.more_horiz_rounded,
                semanticLabel: 'More options for ${person.handle}',
                onPressed: () =>
                    UserActions.showOverflow(context, profile: person),
              ),
            ],
          ),
          if (match.sharedTags.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: <Widget>[
                for (final tag in match.sharedTags.take(visibleTags))
                  KChip(
                    label: '#$tag',
                    dense: true,
                    tint: tint,
                    selected: true,
                    onTap: () => context.push('/search?q=$tag'),
                  ),
                if (match.sharedTags.length > visibleTags)
                  KChip(
                    label: '+${match.sharedTags.length - visibleTags}',
                    dense: true,
                  ),
              ],
            ),
          ],
          _ShelfPreview(userId: person.id),
          const SizedBox(height: Space.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: FollowButton(
                  userId: person.id,
                  followerCount: person.followerCount,
                  expand: true,
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: KButton(
                  label: 'Message',
                  icon: Icons.forum_outlined,
                  variant: KButtonVariant.secondary,
                  expand: true,
                  onPressed: () =>
                      UserActions.message(context, ref, person.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShelfPreview extends ConsumerWidget {
  const _ShelfPreview({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(klectApiProvider);
    final collections = ref.watch(profileCollectionsProvider(userId)).value;
    if (collections == null || collections.isEmpty) {
      return const SizedBox.shrink();
    }

    final preview = collections.take(MatchCard.previewShelves).toList();
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Row(
        children: <Widget>[
          for (var index = 0; index < MatchCard.previewShelves; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? Space.s0 : Space.s2,
                ),
                child: index < preview.length
                    ? _ShelfThumb(collection: preview[index], api: api)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShelfThumb extends StatelessWidget {
  const _ShelfThumb({required this.collection, required this.api});

  final CollectionModel collection;
  final KlectApi api;

  @override
  Widget build(BuildContext context) => KPressable(
        onTap: () => context.push(
          KlectLinks.closeupPath(EntityType.collection, collection.id),
        ),
        enforceMinTapTarget: false,
        semanticLabel: '${collection.name}, ${collection.itemCount} items',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KBlurhashImage(
              url: api.publicUrl(collection.coverPath),
              blurhash: collection.coverBlurhash,
              aspectRatio: Aspect.cover,
              borderRadius: BorderRadius.circular(Radii.md),
              semanticLabel: collection.name,
            ),
            const SizedBox(height: Space.s1),
            Text(
              collection.name,
              style: context.kt.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}
