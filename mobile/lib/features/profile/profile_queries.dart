import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/theme.dart';

/// One tile in a profile grid.
///
/// Collections, subcollections and items are all independently likeable,
/// saveable and repostable, so the grid renders one card shape for all three
/// rather than pretending a profile is only a bag of items.
class ProfileEntityCard {
  /// Creates a card.
  const ProfileEntityCard({
    required this.entityType,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverPath,
    this.blurhash,
    this.width,
    this.height,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.childCount = 0,
  });

  /// Builds a card from an `items` row.
  factory ProfileEntityCard.fromItem(ItemModel item) => ProfileEntityCard(
        entityType: EntityType.item,
        id: item.id,
        title: item.title,
        subtitle: item.brand,
        coverPath: item.coverPath,
        blurhash: item.coverBlurhash,
        width: item.coverWidth,
        height: item.coverHeight,
        likeCount: item.likeCount,
        saveCount: item.saveCount,
        repostCount: item.repostCount,
        commentCount: item.commentCount,
        viewCount: item.viewCount,
        childCount: item.mediaCount,
      );

  /// Builds a card from a `collections` row.
  factory ProfileEntityCard.fromCollection(CollectionModel collection) =>
      ProfileEntityCard(
        entityType: EntityType.collection,
        id: collection.id,
        title: collection.name,
        subtitle: collection.description,
        coverPath: collection.coverPath,
        blurhash: collection.coverBlurhash,
        likeCount: collection.likeCount,
        saveCount: collection.saveCount,
        repostCount: collection.repostCount,
        commentCount: collection.commentCount,
        viewCount: collection.viewCount,
        childCount: collection.itemCount,
      );

  /// Builds a card from a `search_all` collection hit.
  factory ProfileEntityCard.fromSearchCollection(CollectionSearchHit hit) =>
      ProfileEntityCard(
        entityType: EntityType.collection,
        id: hit.id,
        title: hit.name,
        subtitle: hit.displayName ?? hit.username,
        coverPath: hit.coverPath,
        blurhash: hit.coverBlurhash,
        likeCount: hit.likeCount,
        childCount: hit.itemCount,
      );

  /// Builds a card from a `search_all` item hit.
  factory ProfileEntityCard.fromSearchItem(ItemSearchHit hit) =>
      ProfileEntityCard(
        entityType: EntityType.item,
        id: hit.id,
        title: hit.title,
        subtitle: hit.brand ?? hit.displayName ?? hit.username,
        coverPath: hit.coverPath,
        blurhash: hit.coverBlurhash,
        width: hit.coverWidth,
        height: hit.coverHeight,
        likeCount: hit.likeCount,
      );

  /// Builds a card from a `subcollections` row.
  factory ProfileEntityCard.fromSubcollection(SubcollectionModel sub) =>
      ProfileEntityCard(
        entityType: EntityType.subcollection,
        id: sub.id,
        title: sub.name,
        subtitle: sub.description,
        coverPath: sub.coverPath,
        blurhash: sub.coverBlurhash,
        likeCount: sub.likeCount,
        saveCount: sub.saveCount,
        repostCount: sub.repostCount,
        commentCount: sub.commentCount,
        viewCount: sub.viewCount,
        childCount: sub.itemCount,
      );

  /// Which of the three curation levels this is.
  final EntityType entityType;

  /// The entity's uuid.
  final String id;

  /// Card headline.
  final String title;

  /// Second line — brand for an item, description for a shelf.
  final String? subtitle;

  /// Cover image path or absolute URL.
  final String? coverPath;

  /// Blurhash placeholder for [coverPath].
  final String? blurhash;

  /// Intrinsic cover width, when the row carries it.
  final int? width;

  /// Intrinsic cover height, when the row carries it.
  final int? height;

  /// Trigger-maintained like count.
  final int likeCount;

  /// Trigger-maintained save count.
  final int saveCount;

  /// Trigger-maintained repost count.
  final int repostCount;

  /// Trigger-maintained comment count.
  final int commentCount;

  /// Trigger-maintained view count.
  final int viewCount;

  /// Items inside, for a shelf; photos, for an item.
  final int childCount;

  /// The polymorphic key the interaction engine is keyed by.
  EntityRef get entity => EntityRef(entityType, id);

  /// Stable list key.
  String get key => entity.key;

  /// The ratio this tile occupies, clamped so one extreme photo cannot make a
  /// column unreadable.
  double get tileAspect {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return Aspect.cover;
    return (w / h).clamp(Aspect.gridMin, Aspect.gridMax);
  }

  /// Authoritative social state, for seeding the optimistic engine.
  InteractionState get interactionSeed => InteractionState(
        likeCount: likeCount,
        saveCount: saveCount,
        repostCount: repostCount,
        commentCount: commentCount,
        viewCount: viewCount,
        hydrated: true,
      );
}

/// One tag the account actually collects, with how often it appears.
class TasteTag {
  /// Creates a taste tag.
  const TasteTag({required this.tag, required this.count});

  /// The tag itself.
  final TagModel tag;

  /// How many of this account's entities carry it.
  final int count;
}

/// Reads that the profile, search, matches and settings surfaces need and that
/// [KlectApi] does not expose yet.
///
/// Everything here goes through [KlectApi.client] — the same PostgREST client,
/// the same publishable key, the same RLS. It lives in this file rather than in
/// `core/api/` only because `core/` is owned by another agent; the five methods
/// below belong on [KlectApi] the next time that file is touched:
///
///  * `fetchUserItems` — `items` has no per-user list method;
///  * `fetchLiked` / `fetchSaved` — the private "Likes"/"Saves" profile tabs;
///  * `fetchTasteTags` — the "Your taste" strip;
///  * `fetchMutedUsers` — the mute list (blocks already have one);
///  * `fetchTrendingTags` — the search zero-state.
///
/// No count is ever computed here: every number is a trigger-maintained
/// counter column read straight off the row.
class ProfileQueries {
  /// Wraps the app's API instance.
  const ProfileQueries(this._api);

  final KlectApi _api;

  /// How many rows a taste scan reads before it stops. Tag counts converge long
  /// before this; it exists so one prolific account cannot stall the profile.
  static const int tasteScanLimit = 400;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw KlectError.from(error);
    }
  }

  /// Every item an account owns, newest first.
  Future<List<ItemModel>> fetchUserItems(String userId, {int limit = 60}) =>
      _guard(() async {
        final rows = await _api.client
            .from('items')
            .select()
            .eq('user_id', userId)
            .isFilter('deleted_at', null)
            .isFilter('hidden_at', null)
            .order('created_at', ascending: false)
            .limit(limit);
        return <ItemModel>[for (final row in rows) ItemModel.fromJson(row)];
      });

  /// Everything [userId] has liked, newest first.
  Future<List<ProfileEntityCard>> fetchLiked(
    String userId, {
    int limit = 60,
  }) =>
      _fetchRelated('likes', userId, limit);

  /// Everything [userId] has saved, newest first.
  Future<List<ProfileEntityCard>> fetchSaved(
    String userId, {
    int limit = 60,
  }) =>
      _fetchRelated('saves', userId, limit);

  /// Resolves a polymorphic social table into renderable cards.
  ///
  /// Two round trips at most per entity type, never one per row, and the
  /// original chronological order of the relation is preserved.
  Future<List<ProfileEntityCard>> _fetchRelated(
    String table,
    String userId,
    int limit,
  ) =>
      _guard(() async {
        final rows = await _api.client
            .from(table)
            .select('entity_type, entity_id, created_at')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);

        final order = <String>[];
        final byType = <EntityType, List<String>>{};
        for (final row in rows) {
          final type = EntityType.tryParse(row['entity_type']);
          final id = asStringOrNull(row['entity_id']);
          if (type == null || id == null) continue;
          // Only the three curation levels are renderable as tiles; a like on a
          // post or a comment lives in that thread, not in a grid.
          if (type != EntityType.collection &&
              type != EntityType.subcollection &&
              type != EntityType.item) {
            continue;
          }
          order.add('${type.wire}:$id');
          (byType[type] ??= <String>[]).add(id);
        }
        if (order.isEmpty) return const <ProfileEntityCard>[];

        final resolved = <String, ProfileEntityCard>{};
        for (final entry in byType.entries) {
          final fetched = await _fetchCardsByIds(entry.key, entry.value);
          for (final card in fetched) {
            resolved[card.key] = card;
          }
        }

        return <ProfileEntityCard>[
          for (final key in order)
            if (resolved[key] != null) resolved[key]!,
        ];
      });

  Future<List<ProfileEntityCard>> _fetchCardsByIds(
    EntityType type,
    List<String> ids,
  ) async {
    final rows = await _api.client
        .from(type.table)
        .select()
        .inFilter('id', ids)
        .isFilter('deleted_at', null);
    return <ProfileEntityCard>[
      for (final row in rows)
        switch (type) {
          EntityType.collection =>
            ProfileEntityCard.fromCollection(CollectionModel.fromJson(row)),
          EntityType.subcollection => ProfileEntityCard.fromSubcollection(
              SubcollectionModel.fromJson(row),
            ),
          _ => ProfileEntityCard.fromItem(ItemModel.fromJson(row)),
        },
    ];
  }

  /// The tags this account actually collects, most-used first.
  Future<List<TasteTag>> fetchTasteTags(String userId, {int limit = 10}) =>
      _guard(() async {
        final rows = await _api.client
            .from('entity_tags')
            .select('tag_id, tags!tag_id(id, slug, name, use_count)')
            .eq('user_id', userId)
            .limit(tasteScanLimit);

        final counts = <String, int>{};
        final tags = <String, TagModel>{};
        for (final row in rows) {
          final json = asMap(row['tags']);
          if (json.isEmpty) continue;
          final tag = TagModel.fromJson(json);
          if (tag.slug.isEmpty) continue;
          tags[tag.slug] = tag;
          counts[tag.slug] = (counts[tag.slug] ?? 0) + 1;
        }

        final ranked = counts.keys.toList()
          ..sort((a, b) {
            final byCount = counts[b]!.compareTo(counts[a]!);
            return byCount != 0 ? byCount : a.compareTo(b);
          });

        return <TasteTag>[
          for (final slug in ranked.take(limit))
            TasteTag(tag: tags[slug]!, count: counts[slug]!),
        ];
      });

  /// Everyone the viewer has muted, newest first.
  Future<List<Profile>> fetchMutedUsers() => _guard(() async {
        final rows = await _api.client
            .from('mutes')
            .select('muted_id, created_at, profiles!muted_id(*)')
            .eq('muter_id', _api.requireUserId)
            .order('created_at', ascending: false);
        return <Profile>[
          for (final row in rows)
            if (asMap(row['profiles']).isNotEmpty)
              Profile.fromJson(asMap(row['profiles'])),
        ];
      });

  /// The most-used tags across the whole product — the search zero-state.
  Future<List<TagModel>> fetchTrendingTags({int limit = 16}) =>
      _guard(() async {
        final rows = await _api.client
            .from('tags')
            .select()
            .order('use_count', ascending: false)
            .limit(limit);
        return <TagModel>[for (final row in rows) TagModel.fromJson(row)];
      });
}

/// Resolves an `avatar_path` into a loadable URL.
///
/// Demo avatars are absolute URLs and real uploads are storage keys;
/// [KlectApi.publicUrl] handles both, and this names the bucket once so no
/// caller has to remember it.
String? avatarUrlOf(KlectApi api, String? path) =>
    api.publicUrl(path, bucket: StorageBucket.avatars);

/// Resolves a `banner_path` into a loadable URL.
String? bannerUrlOf(KlectApi api, String? path) =>
    api.publicUrl(path, bucket: StorageBucket.banners);

/// The supplementary read layer.
final profileQueriesProvider = Provider<ProfileQueries>(
  (ref) => ProfileQueries(ref.watch(klectApiProvider)),
  name: 'profileQueries',
);

/// One profile by handle — the `/u/:username` route.
final profileByUsernameProvider =
    FutureProvider.autoDispose.family<Profile?, String>(
  (ref, username) =>
      ref.watch(klectApiProvider).fetchProfileByUsername(username),
  name: 'profileByUsername',
);

/// One profile by id.
final profileByIdProvider = FutureProvider.autoDispose.family<Profile?, String>(
  (ref, userId) => ref.watch(klectApiProvider).fetchProfile(userId),
  name: 'profileById',
);

/// An account's collections, pinned first.
final profileCollectionsProvider =
    FutureProvider.autoDispose.family<List<CollectionModel>, String>(
  (ref, userId) => ref.watch(klectApiProvider).fetchCollections(userId),
  name: 'profileCollections',
);

/// An account's items, newest first.
final profileItemsProvider =
    FutureProvider.autoDispose.family<List<ItemModel>, String>(
  (ref, userId) => ref.watch(profileQueriesProvider).fetchUserItems(userId),
  name: 'profileItems',
);

/// What an account has liked. Only ever requested for the viewer's own profile.
final profileLikesProvider =
    FutureProvider.autoDispose.family<List<ProfileEntityCard>, String>(
  (ref, userId) => ref.watch(profileQueriesProvider).fetchLiked(userId),
  name: 'profileLikes',
);

/// What an account has saved. Only ever requested for the viewer's own profile.
final profileSavesProvider =
    FutureProvider.autoDispose.family<List<ProfileEntityCard>, String>(
  (ref, userId) => ref.watch(profileQueriesProvider).fetchSaved(userId),
  name: 'profileSaves',
);

/// The "Your taste" strip.
final profileTasteTagsProvider =
    FutureProvider.autoDispose.family<List<TasteTag>, String>(
  (ref, userId) => ref.watch(profileQueriesProvider).fetchTasteTags(userId),
  name: 'profileTasteTags',
);

/// Followers of one account.
final followersProvider =
    FutureProvider.autoDispose.family<List<Profile>, String>(
  (ref, userId) => ref.watch(klectApiProvider).fetchFollowers(userId),
  name: 'followers',
);

/// Accounts one account follows.
final followingProvider =
    FutureProvider.autoDispose.family<List<Profile>, String>(
  (ref, userId) => ref.watch(klectApiProvider).fetchFollowing(userId),
  name: 'following',
);

/// Every id the viewer follows.
///
/// One query serves every follow button in the app — a profile header, a match
/// card, a search row, a follower list — instead of one `has_followed` round
/// trip per button.
final myFollowingIdsProvider = FutureProvider<Set<String>>(
  (ref) async {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return const <String>{};
    final following = await ref.watch(klectApiProvider).fetchFollowing(
          me,
          limit: 500,
        );
    return <String>{for (final person in following) person.id};
  },
  name: 'myFollowingIds',
);

/// Everyone the viewer has blocked.
final blockedUsersProvider = FutureProvider<List<Profile>>(
  (ref) async {
    if (ref.watch(currentUserIdProvider) == null) return const <Profile>[];
    return ref.watch(klectApiProvider).fetchBlockedUsers();
  },
  name: 'blockedUsers',
);

/// Everyone the viewer has muted.
final mutedUsersProvider = FutureProvider<List<Profile>>(
  (ref) async {
    if (ref.watch(currentUserIdProvider) == null) return const <Profile>[];
    return ref.watch(profileQueriesProvider).fetchMutedUsers();
  },
  name: 'mutedUsers',
);

/// The most-used tags across the product.
final trendingTagsProvider = FutureProvider<List<TagModel>>(
  (ref) => ref.watch(profileQueriesProvider).fetchTrendingTags(),
  name: 'trendingTags',
);
