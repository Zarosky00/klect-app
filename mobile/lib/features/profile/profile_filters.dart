import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../../core/models/models.dart';

/// Which slice of a profile is on screen.
enum ProfileMode {
  /// The shelves this account owns.
  surf('Surf', Icons.grid_view_outlined, Icons.grid_view_rounded),

  /// Posts, quotes and reposts — `user_posts` (0021).
  pulse('Pulse', Icons.bolt_outlined, Icons.bolt_rounded),

  /// What the owner liked and saved, newest first.
  activity('Activity', Icons.history_toggle_off_rounded, Icons.history_rounded);

  const ProfileMode(this.label, this.icon, this.activeIcon);

  /// Tab label.
  final String label;

  /// Glyph while another section is showing.
  final IconData icon;

  /// Glyph while this section is showing.
  final IconData activeIcon;

  /// Whether only the account owner may see this tab.
  bool get isPrivate => this == ProfileMode.activity;

  /// This section as a navigation option.
  ProfileNavOption get option =>
      ProfileNavOption(label: label, icon: icon, activeIcon: activeIcon);
}

/// The two halves of a profile's Surf section.
enum ProfileSurfSection {
  /// The account's shelves.
  collections(
    'Collections',
    Icons.collections_bookmark_outlined,
    Icons.collections_bookmark_rounded,
  ),

  /// Every item on those shelves, newest first.
  items('Items', Icons.category_outlined, Icons.category_rounded);

  const ProfileSurfSection(this.label, this.icon, this.activeIcon);

  /// Filter label.
  final String label;

  /// Resting glyph.
  final IconData icon;

  /// Selected glyph.
  final IconData activeIcon;
}

/// The three timelines of a profile's Pulse section.
enum ProfilePulseTab {
  /// Originals, reposts and quotes.
  posts('Posts', Icons.article_outlined, Icons.article_rounded),

  /// Comments and nested replies from Surf and Pulse.
  replies('Replies', Icons.forum_outlined, Icons.forum_rounded),

  /// Photos uploaded in original posts and quotes.
  media('Media', Icons.perm_media_outlined, Icons.perm_media_rounded);

  const ProfilePulseTab(this.label, this.icon, this.activeIcon);

  /// Filter label.
  final String label;

  /// Resting glyph.
  final IconData icon;

  /// Selected glyph.
  final IconData activeIcon;
}

/// One choice in a profile section switcher or filter row.
@immutable
class ProfileNavOption {
  /// Creates an option. [activeIcon] defaults to [icon].
  const ProfileNavOption({
    required this.label,
    required this.icon,
    IconData? activeIcon,
  }) : activeIcon = activeIcon ?? icon;

  /// Visible and announced label.
  final String label;

  /// Resting glyph.
  final IconData icon;

  /// Selected glyph.
  final IconData activeIcon;
}

/// One row of mutually exclusive filter choices.
@immutable
class ProfileFilterRow {
  /// Creates a row.
  const ProfileFilterRow({
    required this.id,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  /// Stable identity, so a control can tell a new row from a new selection.
  final String id;

  /// The choices, in display order.
  final List<ProfileNavOption> options;

  /// Index of the active choice.
  final int selected;

  /// Called with the index the user picked.
  final ValueChanged<int> onSelected;

  /// The active choice.
  ProfileNavOption get current => options[selected];
}

/// Everything a section offers to filter by: a primary row and, for some
/// primary choices, a narrower scope row.
@immutable
class ProfileFilterSpec {
  /// Creates a spec.
  const ProfileFilterSpec({
    required this.primary,
    required this.isDefault,
    this.scope,
  });

  /// e.g. Posts · Replies · Media.
  final ProfileFilterRow primary;

  /// e.g. All · Originals · Reposts · Quotes, under Posts.
  final ProfileFilterRow? scope;

  /// Whether the section shows its default view.
  final bool isDefault;

  /// "Posts", or "Posts · Originals" when the scope is narrowed.
  String get summary {
    final narrowed = scope;
    if (narrowed == null || narrowed.selected == 0) {
      return primary.current.label;
    }
    return '${primary.current.label} · ${narrowed.current.label}';
  }
}

/// The filter state of one profile, shared by every section's controls.
@immutable
class ProfileFilters {
  /// Creates the state. The defaults are what a profile opens on.
  const ProfileFilters({
    this.surfSection = ProfileSurfSection.collections,
    this.pulseTab = ProfilePulseTab.posts,
    this.postView = ProfilePulseView.all,
    this.replySurface = ProfileSurface.all,
    this.activityAction = ProfileReactionAction.like,
    this.activitySurface = ProfileSurface.surf,
  });

  /// Surf: shelves or items.
  final ProfileSurfSection surfSection;

  /// Pulse: posts, replies or media.
  final ProfilePulseTab pulseTab;

  /// Pulse › Posts scope.
  final ProfilePulseView postView;

  /// Pulse › Replies scope.
  final ProfileSurface replySurface;

  /// Activity: likes or saves.
  final ProfileReactionAction activityAction;

  /// Activity scope. Only Surf or Pulse, never all.
  final ProfileSurface activitySurface;

  /// A copy with the given fields replaced.
  ProfileFilters copyWith({
    ProfileSurfSection? surfSection,
    ProfilePulseTab? pulseTab,
    ProfilePulseView? postView,
    ProfileSurface? replySurface,
    ProfileReactionAction? activityAction,
    ProfileSurface? activitySurface,
  }) => ProfileFilters(
    surfSection: surfSection ?? this.surfSection,
    pulseTab: pulseTab ?? this.pulseTab,
    postView: postView ?? this.postView,
    replySurface: replySurface ?? this.replySurface,
    activityAction: activityAction ?? this.activityAction,
    activitySurface: activitySurface ?? this.activitySurface,
  );

  @override
  bool operator ==(Object other) =>
      other is ProfileFilters &&
      other.surfSection == surfSection &&
      other.pulseTab == pulseTab &&
      other.postView == postView &&
      other.replySurface == replySurface &&
      other.activityAction == activityAction &&
      other.activitySurface == activitySurface;

  @override
  int get hashCode => Object.hash(
    surfSection,
    pulseTab,
    postView,
    replySurface,
    activityAction,
    activitySurface,
  );
}

/// Owns a profile's [ProfileFilters] for as long as the profile is open.
class ProfileFilterController extends ValueNotifier<ProfileFilters> {
  /// Starts from the defaults.
  ProfileFilterController() : super(const ProfileFilters());

  /// Replaces the state with what [change] makes of the current one.
  void update(ProfileFilters Function(ProfileFilters current) change) {
    value = change(value);
  }
}

const List<ProfilePulseView> _postViews = <ProfilePulseView>[
  ProfilePulseView.all,
  ProfilePulseView.originals,
  ProfilePulseView.reposts,
  ProfilePulseView.quotes,
];

const List<ProfileNavOption> _postViewOptions = <ProfileNavOption>[
  ProfileNavOption(label: 'All', icon: Icons.all_inclusive_rounded),
  ProfileNavOption(label: 'Originals', icon: Icons.edit_note_rounded),
  ProfileNavOption(label: 'Reposts', icon: Icons.repeat_rounded),
  ProfileNavOption(label: 'Quotes', icon: Icons.format_quote_rounded),
];

const List<ProfileNavOption> _replySurfaceOptions = <ProfileNavOption>[
  ProfileNavOption(label: 'All', icon: Icons.all_inclusive_rounded),
  ProfileNavOption(label: 'Surf', icon: Icons.grid_view_rounded),
  ProfileNavOption(label: 'Pulse', icon: Icons.bolt_rounded),
];

const List<ProfileSurface> _activitySurfaces = <ProfileSurface>[
  ProfileSurface.surf,
  ProfileSurface.pulse,
];

const List<ProfileNavOption> _activitySurfaceOptions = <ProfileNavOption>[
  ProfileNavOption(label: 'Surf', icon: Icons.grid_view_rounded),
  ProfileNavOption(label: 'Pulse', icon: Icons.bolt_rounded),
];

const List<ProfileNavOption> _activityActionOptions = <ProfileNavOption>[
  ProfileNavOption(
    label: 'Likes',
    icon: Icons.favorite_border_rounded,
    activeIcon: Icons.favorite_rounded,
  ),
  ProfileNavOption(
    label: 'Saves',
    icon: Icons.bookmark_border_rounded,
    activeIcon: Icons.bookmark_rounded,
  ),
];

/// What [mode] offers to filter by, given the current [filters]. Selections
/// are written back through [controller].
ProfileFilterSpec profileFilterSpec(
  ProfileMode mode,
  ProfileFilters filters,
  ProfileFilterController controller,
) {
  switch (mode) {
    case ProfileMode.surf:
      return ProfileFilterSpec(
        primary: ProfileFilterRow(
          id: 'surf',
          options: <ProfileNavOption>[
            for (final section in ProfileSurfSection.values)
              ProfileNavOption(
                label: section.label,
                icon: section.icon,
                activeIcon: section.activeIcon,
              ),
          ],
          selected: filters.surfSection.index,
          onSelected: (index) => controller.update(
            (current) =>
                current.copyWith(surfSection: ProfileSurfSection.values[index]),
          ),
        ),
        isDefault: filters.surfSection == ProfileSurfSection.collections,
      );

    case ProfileMode.pulse:
      final scope = switch (filters.pulseTab) {
        ProfilePulseTab.posts => ProfileFilterRow(
          id: 'pulse.posts',
          options: _postViewOptions,
          selected: _postViews.indexOf(filters.postView).clamp(0, 3),
          onSelected: (index) => controller.update(
            (current) => current.copyWith(postView: _postViews[index]),
          ),
        ),
        ProfilePulseTab.replies => ProfileFilterRow(
          id: 'pulse.replies',
          options: _replySurfaceOptions,
          selected: filters.replySurface.index,
          onSelected: (index) => controller.update(
            (current) =>
                current.copyWith(replySurface: ProfileSurface.values[index]),
          ),
        ),
        ProfilePulseTab.media => null,
      };
      return ProfileFilterSpec(
        primary: ProfileFilterRow(
          id: 'pulse',
          options: <ProfileNavOption>[
            for (final tab in ProfilePulseTab.values)
              ProfileNavOption(
                label: tab.label,
                icon: tab.icon,
                activeIcon: tab.activeIcon,
              ),
          ],
          selected: filters.pulseTab.index,
          onSelected: (index) => controller.update(
            (current) =>
                current.copyWith(pulseTab: ProfilePulseTab.values[index]),
          ),
        ),
        scope: scope,
        isDefault:
            filters.pulseTab == ProfilePulseTab.posts &&
            filters.postView == ProfilePulseView.all,
      );

    case ProfileMode.activity:
      return ProfileFilterSpec(
        primary: ProfileFilterRow(
          id: 'activity',
          options: _activityActionOptions,
          selected: filters.activityAction.index,
          onSelected: (index) => controller.update(
            (current) => current.copyWith(
              activityAction: ProfileReactionAction.values[index],
            ),
          ),
        ),
        scope: ProfileFilterRow(
          id: 'activity.surface',
          options: _activitySurfaceOptions,
          selected: _activitySurfaces
              .indexOf(filters.activitySurface)
              .clamp(0, 1),
          onSelected: (index) => controller.update(
            (current) =>
                current.copyWith(activitySurface: _activitySurfaces[index]),
          ),
        ),
        isDefault:
            filters.activityAction == ProfileReactionAction.like &&
            filters.activitySurface == ProfileSurface.surf,
      );
  }
}
