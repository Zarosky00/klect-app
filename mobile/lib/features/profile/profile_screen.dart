import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../pulse/widgets/pulse_card.dart';
import 'edit_profile_screen.dart';
import 'entity_tile.dart';
import 'fill_viewport.dart';
import 'follow_button.dart';
import 'follow_list_sheet.dart';
import 'profile_queries.dart';
import 'user_actions.dart';
import 'user_posts_controller.dart';

/// Which slice of a profile is on screen.
enum ProfileTab {
  /// The shelves this account owns.
  collections('Collections'),

  /// Posts, quotes and reposts — `user_posts` (0021).
  posts('Posts'),

  /// Every item, newest first.
  items('Items'),

  /// What the viewer has liked. Private — own profile only.
  likes('Likes'),

  /// What the viewer has saved. Private — own profile only.
  saves('Saves');

  const ProfileTab(this.label);

  /// Tab label.
  final String label;

  /// Whether only the account owner may see this tab.
  bool get isPrivate => this == ProfileTab.likes || this == ProfileTab.saves;
}

/// A collector's profile.
///
/// `/me` renders the signed-in account (no `username`); `/u/:username` renders
/// anybody. The header collapses a banner into a glass bar, the counts are
/// trigger-maintained columns (never a `COUNT(*)`), and the follow button
/// shares the same optimistic engine as every other follow control in the app.
class ProfileScreen extends ConsumerStatefulWidget {
  /// Creates the screen. A null [username] means "the signed-in account".
  const ProfileScreen({this.username, super.key});

  /// Route parameter — the handle to show, or null for `/me`.
  final String? username;

  /// Height of the expanded banner.
  static const double bannerHeight = Space.s24 + Space.s12;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  ProfileTab _tab = ProfileTab.collections;

  bool get _isMe => widget.username == null;

  AsyncValue<Profile?> _watchProfile() {
    if (_isMe) return ref.watch(myProfileProvider);
    return ref.watch(profileByUsernameProvider(widget.username!));
  }

  void _refreshProfile() {
    if (_isMe) {
      ref.invalidate(myProfileProvider);
    } else {
      ref.invalidate(profileByUsernameProvider(widget.username!));
    }
  }

  Future<void> _refresh(String userId) async {
    _refreshProfile();
    ref
      ..invalidate(profileCollectionsProvider(userId))
      ..invalidate(userPostsProvider(userId))
      ..invalidate(profileItemsProvider(userId))
      ..invalidate(profileTasteTagsProvider(userId))
      ..invalidate(profileLikesProvider(userId))
      ..invalidate(profileSavesProvider(userId))
      ..invalidate(myFollowingIdsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _watchProfile();

    return profile.when(
      loading: () => const KScaffold(
        appBar: KFixedAppBar(showBack: true),
        body: _ProfileSkeleton(),
      ),
      error: (error, _) => KScaffold(
        appBar: const KFixedAppBar(showBack: true),
        body: FillViewport(
          child: KErrorState(error: error, onRetry: _refreshProfile),
        ),
      ),
      data: (person) => person == null
          ? KScaffold(
              appBar: const KFixedAppBar(showBack: true),
              body: FillViewport(
                child: KEmptyState(
                  title: 'No such collector',
                  message: widget.username == null
                      ? 'Your profile is still being set up.'
                      : '@${widget.username} does not exist, or is no longer '
                            'visible to you.',
                  icon: Icons.person_off_outlined,
                  actionLabel: 'Find collectors',
                  onAction: () => context.push('/search'),
                ),
              ),
            )
          : _ProfileBody(
              profile: person,
              isMe: _isMe || person.id == ref.watch(currentUserIdProvider),
              tab: _tab,
              onTabChanged: (tab) => setState(() => _tab = tab),
              onRefresh: () => _refresh(person.id),
            ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.profile,
    required this.isMe,
    required this.tab,
    required this.onTabChanged,
    required this.onRefresh,
  });

  final Profile profile;
  final bool isMe;
  final ProfileTab tab;
  final ValueChanged<ProfileTab> onTabChanged;
  final Future<void> Function() onRefresh;

  List<ProfileTab> get _tabs => <ProfileTab>[
    for (final candidate in ProfileTab.values)
      if (isMe || !candidate.isPrivate) candidate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleTab = _tabs.contains(tab) ? tab : ProfileTab.collections;

    return KScaffold(
      safeTop: false,
      onRefresh: onRefresh,
      body: CustomScrollView(
        slivers: <Widget>[
          _ProfileAppBar(profile: profile, isMe: isMe),
          SliverToBoxAdapter(
            child: _ProfileHeader(profile: profile, isMe: isMe),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              tabs: _tabs,
              selected: visibleTab,
              onChanged: onTabChanged,
            ),
          ),
          _ProfileTabContent(
            key: ValueKey<ProfileTab>(visibleTab),
            profile: profile,
            tab: visibleTab,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.s20)),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── collapsing bar ──

class _ProfileAppBar extends ConsumerWidget {
  const _ProfileAppBar({required this.profile, required this.isMe});

  final Profile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final banner = bannerUrlOf(api, profile.bannerPath);
    final canPop = Navigator.of(context).canPop();

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: ProfileScreen.bannerHeight,
      collapsedHeight: Layout.topBarHeight,
      toolbarHeight: Layout.topBarHeight,
      backgroundColor: colors.surfaceGlass,
      surfaceTintColor: colors.bgBase.withValues(alpha: 0),
      elevation: Elevation.none.y,
      scrolledUnderElevation: Elevation.none.y,
      automaticallyImplyLeading: false,
      leading: canPop
          ? Padding(
              padding: const EdgeInsets.only(left: Space.s2),
              child: KIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                color: colors.textPrimary,
                background: colors.surfaceScrim,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      actions: <Widget>[
        if (isMe)
          KIconButton(
            icon: Icons.settings_outlined,
            semanticLabel: 'Settings',
            color: colors.textPrimary,
            background: colors.surfaceScrim,
            onPressed: () => context.push('/settings'),
          ),
        const SizedBox(width: Space.s2),
        KIconButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'More options',
          color: colors.textPrimary,
          background: colors.surfaceScrim,
          onPressed: () => UserActions.showOverflow(context, profile: profile),
        ),
        const SizedBox(width: Space.s3),
      ],
      // Same glass treatment as every other chrome surface: the bar's fill is
      // translucent `surface.glass`, so without a real blur the bio scrolling
      // underneath reads straight through the collapsed header.
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
          child: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(
              left: Space.s14,
              right: Space.s14,
              bottom: Space.s3,
            ),
            centerTitle: true,
            expandedTitleScale: 1,
            title: _CollapsedTitle(profile: profile),
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (banner == null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[colors.surface2, colors.surface1],
                      ),
                    ),
                  )
                else
                  KBlurhashImage(
                    url: banner,
                    borderRadius: BorderRadius.zero,
                    semanticLabel: '${profile.name} banner',
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        colors.bgBase.withValues(alpha: 0),
                        colors.bgBase,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final extent = settings == null
        ? 0.0
        : (settings.maxExtent - settings.minExtent);
    final collapsed = settings == null || extent <= 0
        ? 1.0
        : (1 - (settings.currentExtent - settings.minExtent) / extent).clamp(
            0.0,
            1.0,
          );

    // Fades in continuously as the banner collapses — no threshold, so a slow
    // scroll never snaps.
    return Opacity(
      opacity: collapsed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              profile.name,
              style: context.kt.title3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (profile.isVerified) ...<Widget>[
            const SizedBox(width: Space.s1),
            Icon(
              Icons.verified_rounded,
              size: Space.s4,
              color: context.kc.accentDefault,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── identity ──

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile, required this.isMe});

  final Profile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);

    // Keep the avatar inside this sliver's paint bounds. Painting it upward
    // into the banner clips the top edge on Android's sliver viewport.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s3,
        Space.s5,
        Space.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(Space.s05),
                decoration: BoxDecoration(
                  color: colors.bgBase,
                  shape: BoxShape.circle,
                ),
                child: KAvatar(
                  imageUrl: avatarUrlOf(api, profile.avatarPath),
                  name: profile.name,
                  size: Space.s20,
                  heroTag: 'avatar:${profile.id}',
                ),
              ),
              const Spacer(),
              if (isMe)
                KButton(
                  label: 'Edit profile',
                  variant: KButtonVariant.secondary,
                  size: KButtonSize.small,
                  icon: Icons.edit_outlined,
                  onPressed: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (routeContext) =>
                          EditProfileScreen(profile: profile),
                    ),
                  ),
                )
              else ...<Widget>[
                KButton(
                  label: 'Message',
                  variant: KButtonVariant.secondary,
                  size: KButtonSize.small,
                  icon: Icons.forum_outlined,
                  onPressed: () =>
                      UserActions.message(context, ref, profile.id),
                ),
                const SizedBox(width: Space.s2),
                FollowButton(
                  userId: profile.id,
                  displayName: profile.name,
                  followerCount: profile.followerCount,
                  size: KButtonSize.small,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.s3),
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  profile.name,
                  style: context.kt.display2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.isVerified) ...<Widget>[
                const SizedBox(width: Space.s2),
                Icon(
                  Icons.verified_rounded,
                  size: Space.s5,
                  color: colors.accentDefault,
                ),
              ],
            ],
          ),
          Text(
            profile.handle,
            style: context.kt.callout.copyWith(color: colors.textTertiary),
          ),
          if (profile.bio?.isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: Space.s3),
            Text(
              profile.bio!,
              style: context.kt.body.copyWith(color: colors.textSecondary),
            ),
          ],
          if ((profile.location?.isNotEmpty ?? false) ||
              (profile.website?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s4,
              runSpacing: Space.s1,
              children: <Widget>[
                if (profile.location?.isNotEmpty ?? false)
                  _MetaLine(
                    icon: Icons.place_outlined,
                    label: profile.location!,
                  ),
                if (profile.website?.isNotEmpty ?? false)
                  _MetaLine(
                    icon: Icons.link_rounded,
                    label: profile.website!,
                    tint: colors.accentDefault,
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.s5),
          _CountsRow(profile: profile),
          _TasteStrip(userId: profile.id, isMe: isMe),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final color = tint ?? colors.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: Space.s4, color: color),
        const SizedBox(width: Space.s1),
        Text(label, style: context.kt.caption.copyWith(color: color)),
      ],
    );
  }
}

class _CountsRow extends ConsumerWidget {
  const _CountsRow({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The follower count is the one number that moves while you look at it:
    // read it from the optimistic engine when it has been hydrated, so tapping
    // Follow updates the header at the same instant as the button.
    final follow = ref.watch(followProvider(profile.id));
    final followers = follow.hydrated
        ? follow.followerCount
        : profile.followerCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ProfileCountStat(
            label: 'Followers',
            value: followers,
            onTap: () => FollowListSheet.show(
              context,
              userId: profile.id,
              followers: true,
              subjectName: profile.name,
            ),
          ),
        ),
        Expanded(
          child: ProfileCountStat(
            label: 'Following',
            value: profile.followingCount,
            onTap: () => FollowListSheet.show(
              context,
              userId: profile.id,
              followers: false,
              subjectName: profile.name,
            ),
          ),
        ),
        Expanded(
          child: ProfileCountStat(
            label: 'Collections',
            value: profile.collectionCount,
          ),
        ),
        Expanded(
          child: ProfileCountStat(label: 'Items', value: profile.itemCount),
        ),
      ],
    );
  }
}

class _TasteStrip extends ConsumerWidget {
  const _TasteStrip({required this.userId, required this.isMe});

  final String userId;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final tags = ref.watch(profileTasteTagsProvider(userId)).value;
    if (tags == null || tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isMe ? 'YOUR TASTE' : 'THEIR TASTE',
            style: context.kt.micro.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: Space.s2),
          SizedBox(
            height: Space.s8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tags.length,
              separatorBuilder: (context, _) => const SizedBox(width: Space.s2),
              itemBuilder: (context, index) {
                final taste = tags[index];
                return Center(
                  child: KChip(
                    label: '#${taste.tag.name}',
                    onTap: () => context.push('/search?q=${taste.tag.slug}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── tabs ──

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<ProfileTab> tabs;
  final ProfileTab selected;
  final ValueChanged<ProfileTab> onChanged;

  static const double _height = Space.s12;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.tabs.length != tabs.length;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.kc;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: colors.surfaceGlass,
            border: Border(
              bottom: BorderSide(
                color: colors.borderSubtle,
                width: Strokes.hairline,
              ),
            ),
          ),
          child: tabs.length <= 3
              ? Row(
                  children: <Widget>[
                    for (final tab in tabs)
                      Expanded(
                        child: _TabButton(
                          tab: tab,
                          selected: tab == selected,
                          onTap: () => onChanged(tab),
                        ),
                      ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                  child: Row(
                    children: <Widget>[
                      for (final tab in tabs)
                        SizedBox(
                          width: Space.s24,
                          child: _TabButton(
                            tab: tab,
                            selected: tab == selected,
                            onTap: () => onChanged(tab),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ProfileTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.kt.label.copyWith(
                color: selected ? colors.textPrimary : colors.textTertiary,
              ),
            ),
            const SizedBox(height: Space.s15),
            AnimatedContainer(
              duration: KMotion.duration(context, KDurations.base),
              curve: Curves_.emphasized,
              height: Space.s05,
              width: selected ? Space.s8 : Space.s0,
              decoration: BoxDecoration(
                color: colors.accentDefault,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTabContent extends ConsumerWidget {
  const _ProfileTabContent({
    required this.profile,
    required this.tab,
    super.key,
  });

  final Profile profile;
  final ProfileTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tab) {
      ProfileTab.posts => _PostsSliver(userId: profile.id),
      ProfileTab.collections => _CardsSliver(
        value: ref
            .watch(profileCollectionsProvider(profile.id))
            .whenData(
              (list) => <ProfileEntityCard>[
                for (final collection in list)
                  ProfileEntityCard.fromCollection(collection),
              ],
            ),
        onRetry: () => ref.invalidate(profileCollectionsProvider(profile.id)),
        emptyTitle: 'No shelves yet',
        emptyMessage:
            'A collection is the top of the hierarchy — "Anime", "Vinyl", '
            '"Cameras". Everything else hangs off it.',
        emptyAction: 'Start a collection',
        onEmptyAction: () => context.push('/create/collection'),
        showEmptyAction: profile.id == ref.watch(currentUserIdProvider),
      ),
      ProfileTab.items => _CardsSliver(
        value: ref
            .watch(profileItemsProvider(profile.id))
            .whenData(
              (list) => <ProfileEntityCard>[
                for (final item in list) ProfileEntityCard.fromItem(item),
              ],
            ),
        onRetry: () => ref.invalidate(profileItemsProvider(profile.id)),
        emptyTitle: 'Nothing on the shelves',
        emptyMessage:
            'Items are the things themselves — each with as many '
            'photos as it deserves.',
        emptyAction: 'Add an item',
        onEmptyAction: () => context.push('/create/item'),
        showEmptyAction: profile.id == ref.watch(currentUserIdProvider),
      ),
      ProfileTab.likes => _CardsSliver(
        value: ref.watch(profileLikesProvider(profile.id)),
        onRetry: () => ref.invalidate(profileLikesProvider(profile.id)),
        emptyTitle: 'Nothing liked yet',
        emptyMessage:
            'Tap the heart on anything — a whole collection, one '
            'shelf inside it, or a single item.',
        emptyAction: 'Go surfing',
        onEmptyAction: () => context.go('/surf'),
      ),
      ProfileTab.saves => _CardsSliver(
        value: ref.watch(profileSavesProvider(profile.id)),
        onRetry: () => ref.invalidate(profileSavesProvider(profile.id)),
        emptyTitle: 'Nothing saved yet',
        emptyMessage:
            'Saving is the brand action — it is how you build a '
            'reference shelf from collections you do not own.',
        emptyAction: 'Go surfing',
        onEmptyAction: () => context.go('/surf'),
      ),
    };
  }
}

/// The Posts tab — `user_posts` (0021) rendered with the exact stream row
/// the Pulse feed uses, so a post reads identically on both surfaces.
class _PostsSliver extends ConsumerWidget {
  const _PostsSliver({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userPostsProvider(userId));

    if (state.loading && state.items.isEmpty) {
      return const SliverToBoxAdapter(child: KSkeletonList(rows: 3));
    }
    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: KErrorState(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(userPostsProvider(userId)),
        ),
      );
    }
    if (state.items.isEmpty) {
      return const SliverToBoxAdapter(
        child: KEmptyState(
          title: 'Nothing said yet',
          message:
              'Posts, quotes and reposts land here — the Pulse side of '
              'a collector.',
          icon: Icons.bolt_outlined,
          compact: true,
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: <Widget>[
        SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final item = state.items[index];
            return PulseCard(key: ValueKey<String>(item.key), item: item);
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: error != null
                ? KInlineError(
                    message: error.message,
                    onRetry: () => unawaited(
                      ref.read(userPostsProvider(userId).notifier).loadMore(),
                    ),
                  )
                : state.hasMore
                ? KButton(
                    label: state.loadingMore ? 'Loading…' : 'Show more posts',
                    variant: KButtonVariant.ghost,
                    size: KButtonSize.small,
                    busy: state.loadingMore,
                    expand: true,
                    onPressed: state.loadingMore
                        ? null
                        : () => unawaited(
                            ref
                                .read(userPostsProvider(userId).notifier)
                                .loadMore(),
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// A uniform, virtualised gallery grid.
///
/// The ragged masonry belongs to Surf; a library reads better — and scrolls
/// cheaper — as an even gallery, because [SliverGrid] only builds the tiles
/// actually on screen.
class _CardsSliver extends StatelessWidget {
  const _CardsSliver({
    required this.value,
    required this.onRetry,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyAction,
    required this.onEmptyAction,
    this.showEmptyAction = true,
  });

  final AsyncValue<List<ProfileEntityCard>> value;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptyMessage;
  final String emptyAction;
  final VoidCallback onEmptyAction;
  final bool showEmptyAction;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const SliverToBoxAdapter(child: KSkeletonGrid(tiles: 6)),
      error: (error, _) => SliverToBoxAdapter(
        child: KErrorState(error: error, onRetry: onRetry, compact: true),
      ),
      data: (cards) {
        if (cards.isEmpty) {
          return SliverToBoxAdapter(
            child: KEmptyState(
              title: emptyTitle,
              message: emptyMessage,
              actionLabel: showEmptyAction ? emptyAction : null,
              onAction: showEmptyAction ? onEmptyAction : null,
              compact: true,
            ),
          );
        }
        final columns = Layout.masonryColumns(MediaQuery.sizeOf(context).width);
        return SliverPadding(
          padding: const EdgeInsets.all(Layout.masonryGutter),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Layout.masonryGutter,
              crossAxisSpacing: Layout.masonryGutter,
              childAspectRatio: Aspect.cover,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => EntityTile(
                key: ValueKey<String>(cards[index].key),
                card: cards[index],
                index: index,
              ),
              childCount: cards.length,
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    child: KShimmer(
      child: Padding(
        padding: EdgeInsets.all(Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KSkeleton(
              height: Space.s24,
              borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
            ),
            SizedBox(height: Space.s4),
            KSkeleton.circle(size: Space.s20),
            SizedBox(height: Space.s4),
            KSkeleton.text(width: Space.s24, height: Space.s6),
            SizedBox(height: Space.s2),
            KSkeleton.text(width: Space.s20),
            SizedBox(height: Space.s6),
            KSkeleton.text(),
            SizedBox(height: Space.s2),
            KSkeleton.text(width: Space.s24),
          ],
        ),
      ),
    ),
  );
}
