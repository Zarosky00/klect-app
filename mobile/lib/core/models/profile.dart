import 'enums.dart';
import 'json.dart';

/// A row of `public.profiles`.
///
/// Partial projections (the `owner` block of `get_closeup`, the `people`
/// block of `search_all`) parse through the same class — absent columns land
/// on their defaults.
class Profile {
  /// Creates a profile.
  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.location,
    this.website,
    this.avatarPath,
    this.bannerPath,
    this.accentColor,
    this.accountVisibility = AccountVisibility.public,
    this.allowMessagesFrom = AllowMessagesFrom.everyone,
    this.showSimilarity = true,
    this.isVerified = false,
    this.isSuspended = false,
    this.suspendedUntil,
    this.suspensionReason,
    this.onboardedAt,
    this.followerCount = 0,
    this.followingCount = 0,
    this.collectionCount = 0,
    this.itemCount = 0,
    this.lastSeenAt,
    this.createdAt,
  });

  /// Parses a `profiles` row or an embedded owner object.
  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: asString(json['id']),
        username: asString(json['username']),
        displayName: asStringOrNull(json['display_name']),
        bio: asStringOrNull(json['bio']),
        location: asStringOrNull(json['location']),
        website: asStringOrNull(json['website']),
        avatarPath: asStringOrNull(json['avatar_path']),
        bannerPath: asStringOrNull(json['banner_path']),
        accentColor: asStringOrNull(json['accent_color']),
        accountVisibility:
            AccountVisibility.parse(json['account_visibility']),
        allowMessagesFrom:
            AllowMessagesFrom.parse(json['allow_messages_from']),
        showSimilarity: asBool(json['show_similarity'], fallback: true),
        isVerified: asBool(json['is_verified']),
        isSuspended: asBool(json['is_suspended']),
        suspendedUntil: asDateOrNull(json['suspended_until']),
        suspensionReason: asStringOrNull(json['suspension_reason']),
        onboardedAt: asDateOrNull(json['onboarded_at']),
        followerCount: asInt(json['follower_count']),
        followingCount: asInt(json['following_count']),
        collectionCount: asInt(json['collection_count']),
        itemCount: asInt(json['item_count']),
        lastSeenAt: asDateOrNull(json['last_seen_at']),
        createdAt: asDateOrNull(json['created_at']),
      );

  /// `auth.users.id`.
  final String id;

  /// Unique handle, no `@`.
  final String username;

  /// Shown in display serif. May be null before onboarding completes.
  final String? displayName;

  /// Free text bio.
  final String? bio;

  /// Free text location.
  final String? location;

  /// Absolute URL the user entered.
  final String? website;

  /// Storage path (or absolute URL) of the avatar.
  final String? avatarPath;

  /// Storage path (or absolute URL) of the profile banner.
  final String? bannerPath;

  /// Optional hex accent chosen by the user for their profile.
  final String? accentColor;

  /// Who can see this account's content.
  final AccountVisibility accountVisibility;

  /// Who may open a DM. Enforced by `start_dm`, not by the client.
  final AllowMessagesFrom allowMessagesFrom;

  /// Whether the user opts into taste-match ranking.
  final bool showSimilarity;

  /// Verified badge.
  final bool isVerified;

  /// Suspended accounts are refused by every write RPC.
  final bool isSuspended;

  /// When the suspension lifts, if temporary.
  final DateTime? suspendedUntil;

  /// Reason shown on the suspension screen.
  final String? suspensionReason;

  /// Null until the 3-step onboarding finishes. The router guards on this.
  final DateTime? onboardedAt;

  /// Trigger-maintained follower count.
  final int followerCount;

  /// Trigger-maintained following count.
  final int followingCount;

  /// Trigger-maintained collection count.
  final int collectionCount;

  /// Trigger-maintained item count.
  final int itemCount;

  /// Presence heartbeat.
  final DateTime? lastSeenAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Display name if set, otherwise the handle.
  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  /// `@handle` for metadata rows.
  String get handle => '@$username';

  /// True once the user has finished onboarding.
  bool get isOnboarded => onboardedAt != null;

  /// Copy with overrides — used for optimistic follower-count updates.
  Profile copyWith({
    String? username,
    String? displayName,
    String? bio,
    String? location,
    String? website,
    String? avatarPath,
    String? bannerPath,
    String? accentColor,
    AccountVisibility? accountVisibility,
    AllowMessagesFrom? allowMessagesFrom,
    bool? showSimilarity,
    bool? isVerified,
    DateTime? onboardedAt,
    int? followerCount,
    int? followingCount,
    int? collectionCount,
    int? itemCount,
  }) =>
      Profile(
        id: id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        location: location ?? this.location,
        website: website ?? this.website,
        avatarPath: avatarPath ?? this.avatarPath,
        bannerPath: bannerPath ?? this.bannerPath,
        accentColor: accentColor ?? this.accentColor,
        accountVisibility: accountVisibility ?? this.accountVisibility,
        allowMessagesFrom: allowMessagesFrom ?? this.allowMessagesFrom,
        showSimilarity: showSimilarity ?? this.showSimilarity,
        isVerified: isVerified ?? this.isVerified,
        isSuspended: isSuspended,
        suspendedUntil: suspendedUntil,
        suspensionReason: suspensionReason,
        onboardedAt: onboardedAt ?? this.onboardedAt,
        followerCount: followerCount ?? this.followerCount,
        followingCount: followingCount ?? this.followingCount,
        collectionCount: collectionCount ?? this.collectionCount,
        itemCount: itemCount ?? this.itemCount,
        lastSeenAt: lastSeenAt,
        createdAt: createdAt,
      );
}
