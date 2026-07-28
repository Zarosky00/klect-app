import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../pulse/data/pulse_entry_view.dart';
import '../pulse/widgets/comment_action_bar.dart';
import '../pulse/widgets/pulse_card.dart';
import '../pulse/widgets/pulse_target_card.dart';
import 'edit_profile_screen.dart';
import 'entity_tile.dart';
import 'fill_viewport.dart';
import 'follow_button.dart';
import 'follow_list_sheet.dart';
import 'profile_queries.dart';
import 'user_actions.dart';
import 'user_posts_controller.dart';

/// Which slice of a profile is on screen.
enum ProfileMode {
  /// The shelves this account owns.
  surf('Surf'),

  /// Posts, quotes and reposts — `user_posts` (0021).
  pulse('Pulse'),

  /// Every item, newest first.
  activity('Activity');

  const ProfileMode(this.label);

  /// Tab label.
  final String label;

  /// Whether only the account owner may see this tab.
  bool get isPrivate => this == ProfileMode.activity;
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
  ProfileMode _mode = ProfileMode.surf;

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
      ..invalidate(profileItemsProvider(userId))
      ..invalidate(profileTasteTagsProvider(userId))
      ..invalidate(profileLikesProvider(userId))
      ..invalidate(profileSavesProvider(userId))
      ..invalidate(myFollowingIdsProvider);
    for (final view in ProfilePulseView.values) {
      ref.invalidate(userPostsProvider((userId: userId, view: view)));
    }
    for (final surface in ProfileSurface.values) {
      ref.invalidate(
        profileDiscussionProvider((userId: userId, surface: surface)),
      );
    }
    for (final action in ProfileReactionAction.values) {
      for (final surface in <ProfileSurface>[
        ProfileSurface.surf,
        ProfileSurface.pulse,
      ]) {
        ref.invalidate(
          profileReactionProvider((action: action, surface: surface)),
        );
      }
    }
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
              mode: _mode,
              onModeChanged: (mode) => setState(() => _mode = mode),
              onRefresh: () => _refresh(person.id),
            ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.profile,
    required this.isMe,
    required this.mode,
    required this.onModeChanged,
    required this.onRefresh,
  });

  final Profile profile;
  final bool isMe;
  final ProfileMode mode;
  final ValueChanged<ProfileMode> onModeChanged;
  final Future<void> Function() onRefresh;

  List<ProfileMode> get _tabs => <ProfileMode>[
    for (final candidate in ProfileMode.values)
      if (isMe || !candidate.isPrivate) candidate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleTab = _tabs.contains(mode) ? mode : ProfileMode.surf;

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
              onChanged: onModeChanged,
            ),
          ),
          _ProfileModeContent(
            key: ValueKey<ProfileMode>(visibleTab),
            profile: profile,
            mode: visibleTab,
            isMe: isMe,
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
                  avatarPath: profile.avatarPath,
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

  final List<ProfileMode> tabs;
  final ProfileMode selected;
  final ValueChanged<ProfileMode> onChanged;

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

  final ProfileMode tab;
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
      child: KPressable(
        enforceMinTapTarget: false,
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

class _ProfileModeContent extends ConsumerWidget {
  const _ProfileModeContent({
    required this.profile,
    required this.mode,
    required this.isMe,
    super.key,
  });

  final Profile profile;
  final ProfileMode mode;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (mode) {
      ProfileMode.surf => _SurfSliver(profile: profile),
      ProfileMode.pulse => _PostsSliver(userId: profile.id),
      ProfileMode.activity =>
        isMe
            ? const _ActivitySliver()
            : const SliverToBoxAdapter(child: SizedBox.shrink()),
    };
  }
}

/// The Posts tab — `user_posts` (0021) rendered with the exact stream row
/// the Pulse feed uses, so a post reads identically on both surfaces.
enum _SurfSection {
  collections('Collections'),
  items('Items');

  const _SurfSection(this.label);
  final String label;
}

class _SurfSliver extends ConsumerStatefulWidget {
  const _SurfSliver({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_SurfSliver> createState() => _SurfSliverState();
}

class _SurfSliverState extends ConsumerState<_SurfSliver> {
  _SurfSection _section = _SurfSection.collections;

  @override
  Widget build(BuildContext context) {
    final userId = widget.profile.id;
    final isMe = userId == ref.watch(currentUserIdProvider);
    final content = switch (_section) {
      _SurfSection.collections => _CardsSliver(
        value: ref
            .watch(profileCollectionsProvider(userId))
            .whenData(
              (list) => <ProfileEntityCard>[
                for (final collection in list)
                  ProfileEntityCard.fromCollection(collection),
              ],
            ),
        onRetry: () => ref.invalidate(profileCollectionsProvider(userId)),
        emptyTitle: 'No shelves yet',
        emptyMessage:
            'Collections are the public home of everything this collector keeps.',
        emptyAction: 'Start a collection',
        onEmptyAction: () => context.push('/create/collection'),
        showEmptyAction: isMe,
      ),
      _SurfSection.items => _CardsSliver(
        value: ref
            .watch(profileItemsProvider(userId))
            .whenData(
              (list) => <ProfileEntityCard>[
                for (final item in list) ProfileEntityCard.fromItem(item),
              ],
            ),
        onRetry: () => ref.invalidate(profileItemsProvider(userId)),
        emptyTitle: 'Nothing on the shelves',
        emptyMessage: 'Individual collected things appear here newest first.',
        emptyAction: 'Add an item',
        onEmptyAction: () => context.push('/create/item'),
        showEmptyAction: isMe,
      ),
    };

    return SliverMainAxisGroup(
      slivers: <Widget>[
        _ProfileFilterRail(
          labels: <String>[
            for (final value in _SurfSection.values) value.label,
          ],
          selected: _section.index,
          onSelected: (index) =>
              setState(() => _section = _SurfSection.values[index]),
        ),
        content,
      ],
    );
  }
}

enum _ProfilePulseTab {
  posts('Posts'),
  replies('Replies'),
  media('Media');

  const _ProfilePulseTab(this.label);

  final String label;
}

class _PostsSliver extends ConsumerStatefulWidget {
  const _PostsSliver({required this.userId});

  final String userId;

  @override
  ConsumerState<_PostsSliver> createState() => _PostsSliverState();
}

class _PostsSliverState extends ConsumerState<_PostsSliver> {
  _ProfilePulseTab _tab = _ProfilePulseTab.posts;
  ProfilePulseView _postView = ProfilePulseView.all;
  ProfileSurface _replySurface = ProfileSurface.all;

  @override
  Widget build(BuildContext context) {
    return _buildPulse(context);
  }

  Widget _buildPulse(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: <Widget>[
        _ProfileFilterRail(
          labels: <String>[
            for (final value in _ProfilePulseTab.values) value.label,
          ],
          selected: _tab.index,
          onSelected: (index) =>
              setState(() => _tab = _ProfilePulseTab.values[index]),
        ),
        if (_tab == _ProfilePulseTab.posts) ...<Widget>[
          _ProfileFilterRail(
            labels: const <String>['All', 'Originals', 'Reposts', 'Quotes'],
            selected: <ProfilePulseView>[
              ProfilePulseView.all,
              ProfilePulseView.originals,
              ProfilePulseView.reposts,
              ProfilePulseView.quotes,
            ].indexOf(_postView),
            compact: true,
            onSelected: (index) => setState(
              () => _postView = <ProfilePulseView>[
                ProfilePulseView.all,
                ProfilePulseView.originals,
                ProfilePulseView.reposts,
                ProfilePulseView.quotes,
              ][index],
            ),
          ),
          _PulseItemsSliver(userId: widget.userId, view: _postView),
        ] else if (_tab == _ProfilePulseTab.media)
          _PulseItemsSliver(userId: widget.userId, view: ProfilePulseView.media)
        else ...<Widget>[
          _ProfileFilterRail(
            labels: const <String>['All', 'Surf', 'Pulse'],
            selected: _replySurface.index,
            compact: true,
            onSelected: (index) =>
                setState(() => _replySurface = ProfileSurface.values[index]),
          ),
          _DiscussionSliver(userId: widget.userId, surface: _replySurface),
        ],
      ],
    );
  }
}

/// A uniform, virtualised gallery grid.
///
/// The ragged masonry belongs to Surf; a library reads better — and scrolls
/// cheaper — as an even gallery, because [SliverGrid] only builds the tiles
/// actually on screen.
class _ProfileFilterRail extends StatelessWidget {
  const _ProfileFilterRail({
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        Space.s4,
        compact ? Space.s1 : Space.s3,
        Space.s4,
        Space.s2,
      ),
      child: Row(
        children: <Widget>[
          for (var index = 0; index < labels.length; index++) ...<Widget>[
            KChip(
              label: labels[index],
              selected: selected == index,
              dense: true,
              onTap: () => onSelected(index),
            ),
            if (index != labels.length - 1) const SizedBox(width: Space.s2),
          ],
        ],
      ),
    ),
  );
}

class _PulseItemsSliver extends ConsumerWidget {
  const _PulseItemsSliver({required this.userId, required this.view});

  final String userId;
  final ProfilePulseView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, view: view);
    final state = ref.watch(userPostsProvider(query));
    if (state.loading && state.items.isEmpty) {
      return const SliverToBoxAdapter(child: KSkeletonList(rows: 3));
    }
    if (state.error != null && state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: KErrorState(
          error: state.error,
          compact: true,
          onRetry: () => ref.read(userPostsProvider(query).notifier).refresh(),
        ),
      );
    }
    final items = <PulseItem>[
      for (final item in state.items)
        if (!(item.kind == PulseKind.repost &&
            (item.target?.unavailable ?? false)))
          item,
    ];
    return SliverMainAxisGroup(
      slivers: <Widget>[
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: KEmptyState(
              title: view == ProfilePulseView.media
                  ? 'No uploaded media yet'
                  : 'Nothing here yet',
              message: view == ProfilePulseView.media
                  ? 'Only photos uploaded in original posts and quotes appear here.'
                  : 'Original posts, reposts and quotes will appear in this timeline.',
              icon: view == ProfilePulseView.media
                  ? Icons.perm_media_outlined
                  : Icons.bolt_outlined,
              compact: true,
            ),
          )
        else
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => PulseCard(
              key: ValueKey<String>(items[index].key),
              item: items[index],
              showOwnerActions: userId == ref.watch(currentUserIdProvider),
            ),
          ),
        _PagingFooter(
          loading: state.loadingMore,
          hasMore: state.hasMore,
          error: state.error,
          label: 'Show more posts',
          onLoad: () => ref.read(userPostsProvider(query).notifier).loadMore(),
        ),
      ],
    );
  }
}

class _DiscussionSliver extends ConsumerWidget {
  const _DiscussionSliver({required this.userId, required this.surface});

  final String userId;
  final ProfileSurface surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, surface: surface);
    final state = ref.watch(profileDiscussionProvider(query));
    if (state.loading && state.items.isEmpty) {
      return const SliverToBoxAdapter(child: KSkeletonList(rows: 4));
    }
    if (state.error != null && state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: KErrorState(
          error: state.error,
          compact: true,
          onRetry: () =>
              ref.read(profileDiscussionProvider(query).notifier).refresh(),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: <Widget>[
        if (state.items.isEmpty)
          const SliverToBoxAdapter(
            child: KEmptyState(
              title: 'No discussions yet',
              message:
                  'Comments and nested replies from Surf and Pulse appear here in one clear chronology.',
              icon: Icons.forum_outlined,
              compact: true,
            ),
          )
        else
          SliverList.builder(
            itemCount: state.items.length,
            itemBuilder: (context, index) => _DiscussionCard(
              key: ValueKey<String>(state.items[index].comment.id),
              activity: state.items[index],
            ),
          ),
        _PagingFooter(
          loading: state.loadingMore,
          hasMore: state.hasMore,
          error: state.error,
          label: 'Show more replies',
          onLoad: () =>
              ref.read(profileDiscussionProvider(query).notifier).loadMore(),
        ),
      ],
    );
  }
}

class _DiscussionCard extends ConsumerWidget {
  const _DiscussionCard({required this.activity, super.key});

  final ProfileDiscussionActivity activity;

  String get _destination {
    final destination = activity.destination;
    final base = destination.type == EntityType.post
        ? KlectLinks.postThreadPath(destination.id)
        : KlectLinks.closeupPath(destination.type, destination.id);
    return '$base?comment=${destination.highlightCommentId}';
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete this reply?',
      message: 'It disappears from the original discussion too.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(klectApiProvider).deleteComment(activity.comment.id);
      ref
          .read(socialActivityMutationProvider.notifier)
          .record(
            SocialActivityMutationKind.delete,
            entity: EntityRef.comment(activity.comment.id),
            active: false,
          );
      if (context.mounted) KToast.success(context, 'Reply deleted');
    } on KlectError catch (error) {
      if (context.mounted) KToast.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final comment = activity.comment;
    final author = comment.author;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);
    final replyingTo = activity.replyingTo;
    final isMine = comment.authorId == ref.watch(currentUserIdProvider);

    return KGestureRegion(
      semanticLabel: '${author?.name ?? 'Someone'} replied: ${comment.body}',
      onTap: () => context.push(_destination),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s4,
          Space.s2,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrl,
                  name: author?.name,
                  size: Space.s10,
                  isVerified: author?.isVerified ?? false,
                ),
                const SizedBox(height: Space.s1),
                Container(
                  width: Strokes.thick,
                  height: Space.s8,
                  color: activity.surface == ProfileSurface.surf
                      ? colors.actionSave
                      : colors.actionComment,
                ),
              ],
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          author?.name ?? 'Someone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.kt.bodyStrong,
                        ),
                      ),
                      if (author != null) ...<Widget>[
                        const SizedBox(width: Space.s1),
                        Flexible(
                          child: Text(
                            author.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.kt.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: Space.s1),
                      Text(
                        comment.createdAt == null
                            ? ''
                            : timeago.format(
                                comment.createdAt!,
                                locale: 'en_short',
                              ),
                        style: context.kt.micro.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      if (isMine) ...<Widget>[
                        const Spacer(),
                        KIconButton(
                          icon: Icons.more_horiz_rounded,
                          semanticLabel: 'Reply options',
                          size: Space.s4,
                          onPressed: () => unawaited(_delete(context, ref)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  Row(
                    children: <Widget>[
                      _SourceBadge(surface: activity.surface),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: Text(
                          replyingTo?.username != null
                              ? 'Replying to @${replyingTo!.username}'
                              : 'On ${activity.context.title ?? activity.context.body ?? 'a discussion'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.kt.micro.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (replyingTo?.body?.isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: Space.s2),
                    Container(
                      padding: const EdgeInsets.only(left: Space.s2),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colors.borderStrong,
                            width: Strokes.thick,
                          ),
                        ),
                      ),
                      child: Text(
                        replyingTo!.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.kt.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.s2),
                  Text(comment.body, style: context.kt.body),
                  const SizedBox(height: Space.s1),
                  CommentActionBar(
                    comment: comment,
                    onReply: () => context.push(_destination),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.surface});

  final ProfileSurface surface;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final pulse = surface == ProfileSurface.pulse;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s15,
        vertical: Space.s05,
      ),
      decoration: BoxDecoration(
        color: pulse ? colors.actionCommentSubtle : colors.actionSaveSubtle,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Text(
        pulse ? 'PULSE' : 'SURF',
        style: context.kt.micro.copyWith(
          color: pulse ? colors.actionComment : colors.actionSave,
        ),
      ),
    );
  }
}

class _ActivitySliver extends ConsumerStatefulWidget {
  const _ActivitySliver();

  @override
  ConsumerState<_ActivitySliver> createState() => _ActivitySliverState();
}

class _ActivitySliverState extends ConsumerState<_ActivitySliver> {
  ProfileReactionAction _action = ProfileReactionAction.like;
  ProfileSurface _surface = ProfileSurface.surf;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: <Widget>[
      _ProfileFilterRail(
        labels: const <String>['Likes', 'Saves'],
        selected: _action.index,
        onSelected: (index) =>
            setState(() => _action = ProfileReactionAction.values[index]),
      ),
      _ProfileFilterRail(
        labels: const <String>['Surf', 'Pulse'],
        selected: _surface == ProfileSurface.surf ? 0 : 1,
        compact: true,
        onSelected: (index) => setState(
          () => _surface = index == 0
              ? ProfileSurface.surf
              : ProfileSurface.pulse,
        ),
      ),
      _ReactionItemsSliver(action: _action, surface: _surface),
    ],
  );
}

class _ReactionItemsSliver extends ConsumerWidget {
  const _ReactionItemsSliver({required this.action, required this.surface});

  final ProfileReactionAction action;
  final ProfileSurface surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (action: action, surface: surface);
    final state = ref.watch(profileReactionProvider(query));
    if (state.loading && state.items.isEmpty) {
      return surface == ProfileSurface.surf
          ? const SliverToBoxAdapter(child: KSkeletonGrid(tiles: 6))
          : const SliverToBoxAdapter(child: KSkeletonList(rows: 3));
    }
    if (state.error != null && state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: KErrorState(
          error: state.error,
          compact: true,
          onRetry: () =>
              ref.read(profileReactionProvider(query).notifier).refresh(),
        ),
      );
    }
    if (state.items.isEmpty) {
      return SliverToBoxAdapter(
        child: KEmptyState(
          title: action == ProfileReactionAction.like
              ? 'Nothing liked here yet'
              : 'Nothing saved here yet',
          message: surface == ProfileSurface.surf
              ? 'Your private Surf history is collected here.'
              : 'Posts and comments from Pulse appear here.',
          icon: action == ProfileReactionAction.like
              ? Icons.favorite_border_rounded
              : Icons.bookmark_border_rounded,
          compact: true,
        ),
      );
    }

    final content = surface == ProfileSurface.surf
        ? _ReactionSurfGrid(items: state.items)
        : SliverList.builder(
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final item = state.items[index];
              final entry = item.entry;
              if (entry != null) {
                return PulseCard(item: PulseItem.fromEntry(entry));
              }
              final target = item.target;
              return target == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(Space.s4),
                      child: PulseTargetCard(target: target),
                    );
            },
          );
    return SliverMainAxisGroup(
      slivers: <Widget>[
        content,
        _PagingFooter(
          loading: state.loadingMore,
          hasMore: state.hasMore,
          error: state.error,
          label: 'Show more activity',
          onLoad: () =>
              ref.read(profileReactionProvider(query).notifier).loadMore(),
        ),
      ],
    );
  }
}

class _ReactionSurfGrid extends StatelessWidget {
  const _ReactionSurfGrid({required this.items});

  final List<ProfileReactionActivity> items;

  @override
  Widget build(BuildContext context) {
    final cards = <ProfileEntityCard>[
      for (final item in items)
        if (item.target != null && !item.target!.unavailable)
          ProfileEntityCard.fromTarget(item.target!),
    ];
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
  }
}

class _PagingFooter extends StatelessWidget {
  const _PagingFooter({
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.label,
    required this.onLoad,
  });

  final bool loading;
  final bool hasMore;
  final KlectError? error;
  final String label;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: error != null
          ? KInlineError(message: error!.message, onRetry: onLoad)
          : hasMore
          ? KButton(
              label: loading ? 'Loading…' : label,
              variant: KButtonVariant.ghost,
              size: KButtonSize.small,
              busy: loading,
              expand: true,
              onPressed: loading ? null : onLoad,
            )
          : const SizedBox.shrink(),
    ),
  );
}

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
