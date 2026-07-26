import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../supabase.dart';
import 'api_error.dart';

/// The **only** place in the app that talks to Supabase.
///
/// Every method maps 1:1 onto something in `docs/BACKEND_API.md`. Errors are
/// normalised to [KlectError] so callers never have to know about
/// `PostgrestException`.
class KlectApi {
  /// Wraps a Supabase client.
  const KlectApi(this._client);

  final SupabaseClient _client;

  /// The underlying client, for the realtime helpers in
  /// `core/interactions/` that need to build their own channels.
  SupabaseClient get client => _client;

  /// The signed-in user's id, or null.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// The signed-in user's id, or throws — for code paths that already know
  /// there is a session.
  String get requireUserId {
    final id = currentUserId;
    if (id == null) {
      throw const KlectError(KlectErrorKind.auth, 'You need to sign in.');
    }
    return id;
  }

  // ───────────────────────────────────────────────────────────── plumbing ──

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw KlectError.from(error);
    }
  }

  Future<Object?> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _guard(() => _client.rpc<dynamic>(fn, params: params));

  // ───────────────────────────────────────────────────────── interactions ──

  /// `toggle_like(p_type, p_id)` → authoritative `{active, count}`.
  Future<ToggleResult> toggleLike(EntityType type, String id) async =>
      ToggleResult.fromJson(
        asMap(
          await _rpc('toggle_like', <String, dynamic>{
            'p_type': type.wire,
            'p_id': id,
          }),
        ),
      );

  /// `toggle_save(p_type, p_id, p_note)` → authoritative `{active, count}`.
  Future<ToggleResult> toggleSave(
    EntityType type,
    String id, {
    String? note,
  }) async => ToggleResult.fromJson(
    asMap(
      await _rpc('toggle_save', <String, dynamic>{
        'p_type': type.wire,
        'p_id': id,
        'p_note': note,
      }),
    ),
  );

  /// `toggle_repost(p_type, p_id, p_quote)` → authoritative `{active, count}`.
  Future<ToggleResult> toggleRepost(
    EntityType type,
    String id, {
    String? quote,
  }) async => ToggleResult.fromJson(
    asMap(
      await _rpc('toggle_repost', <String, dynamic>{
        'p_type': type.wire,
        'p_id': id,
        'p_quote': quote,
      }),
    ),
  );

  /// `toggle_follow(p_user)` → `{active, count}` where `count` is the
  /// **target's** follower count.
  Future<ToggleResult> toggleFollow(String userId) async =>
      ToggleResult.fromJson(
        asMap(await _rpc('toggle_follow', <String, dynamic>{'p_user': userId})),
      );

  /// `record_view(p_type, p_id)` → the new view count. Deduped per viewer
  /// per day server-side, so calling it on every impression is safe.
  Future<int> recordView(EntityType type, String id) async => asInt(
    await _rpc('record_view', <String, dynamic>{
      'p_type': type.wire,
      'p_id': id,
    }),
  );

  /// `add_comment(p_type, p_id, p_body, p_parent)` → `{id, count}`.
  Future<CommentResult> addComment({
    required EntityType type,
    required String id,
    required String body,
    String? parentId,
  }) async => CommentResult.fromJson(
    asMap(
      await _rpc('add_comment', <String, dynamic>{
        'p_type': type.wire,
        'p_id': id,
        'p_body': body,
        'p_parent': parentId,
      }),
    ),
  );

  /// `delete_comment(p_comment)` → the parent entity's new comment count.
  Future<int> deleteComment(String commentId) async {
    final result = asMap(
      await _rpc('delete_comment', <String, dynamic>{'p_comment': commentId}),
    );
    return asInt(result['count']);
  }

  /// `submit_report(...)` → `{id, already_reported}`.
  ///
  /// Reporting the same target twice is not an error: [ReportResult.alreadyReported]
  /// comes back true and the UI says so.
  Future<ReportResult> submitReport({
    required ReportReason reason,
    EntityType? type,
    String? entityId,
    String? userId,
    String? messageId,
    String? details,
  }) async => ReportResult.fromJson(
    asMap(
      await _rpc('submit_report', <String, dynamic>{
        'p_reason': reason.wire,
        'p_type': type?.wire,
        'p_id': entityId,
        'p_user': userId,
        'p_message': messageId,
        'p_details': details,
      }),
    ),
  );

  // ───────────────────────────────────────────────── feeds and discovery ──

  /// `surf_feed` — the Pinterest grid.
  ///
  /// [seed] must be stable per user (e.g. `userId` or `userId + yyyy-mm-dd`)
  /// so pagination never duplicates or skips a card.
  Future<List<SurfCard>> surfFeed({
    int limit = 30,
    int offset = 0,
    required String seed,
    SurfFilter filter = SurfFilter.all,
  }) async {
    final rows = asMapList(
      await _rpc('surf_feed', <String, dynamic>{
        'p_limit': limit,
        'p_offset': offset,
        'p_seed': seed,
        'p_filter': filter.wire,
      }),
    );
    return <SurfCard>[for (final row in rows) SurfCard.fromJson(row)];
  }

  /// `pulse_feed` — the X-style stream. Pass the oldest [before] you have to
  /// page backwards; [mode] picks the ranked For-you feed or the
  /// chronological Following feed (`p_mode`, 0018).
  Future<List<PulseEntry>> pulseFeed({
    int limit = 25,
    DateTime? before,
    PulseMode mode = PulseMode.following,
  }) async {
    final rows = asMapList(
      await _rpc('pulse_feed', <String, dynamic>{
        'p_limit': limit,
        'p_before': isoOrNull(before),
        'p_mode': mode.wire,
      }),
    );
    return <PulseEntry>[for (final row in rows) PulseEntry.fromJson(row)];
  }

  /// `create_post` — **the** insert path for posts (0018).
  ///
  /// Share text, up to four photo descriptors ([media], already uploaded to
  /// `{uid}/posts/{draft}/…` in the `media` bucket), an attached entity, a
  /// quote (`entityType == EntityType.post`), or a reply ([replyTo]). The
  /// server derives `kind`; [kind] rides along for contract stability.
  ///
  /// Returns the new post's full pulse envelope so the composer can prepend
  /// it to the stream verbatim. The RPC's stable snake_case error texts are
  /// mapped to human copy here.
  Future<PulseEntry> createPost({
    String? body,
    PostKind kind = PostKind.post,
    EntityType? entityType,
    String? entityId,
    List<Map<String, dynamic>>? media,
    String? replyTo,
  }) async {
    try {
      return PulseEntry.fromJson(
        asMap(
          await _rpc('create_post', <String, dynamic>{
            'p_body': body,
            'p_kind': kind.wire,
            'p_entity_type': entityType?.wire,
            'p_entity_id': entityId,
            'p_media': media,
            'p_reply_to': replyTo,
          }),
        ),
      );
    } on KlectError catch (error) {
      throw _mapCreatePostError(error);
    }
  }

  /// Translates `create_post`'s stable snake_case error texts (see the 0018
  /// migration header) into copy a person can act on.
  KlectError _mapCreatePostError(KlectError error) {
    final code = error.raw.trim();
    return switch (code) {
      'body_too_long' => KlectError(
        KlectErrorKind.unknown,
        'Posts are capped at 2,000 characters.',
        code: error.code,
        cause: error,
      ),
      'body_or_attachment_required' => KlectError(
        KlectErrorKind.unknown,
        'Say something, or attach a photo or something you own.',
        code: error.code,
        cause: error,
      ),
      'bad_target' => KlectError(
        KlectErrorKind.unknown,
        'That attachment could not be used.',
        code: error.code,
        cause: error,
      ),
      'entity_not_found' => KlectError(
        KlectErrorKind.notFound,
        'What you attached is no longer available.',
        code: error.code,
        cause: error,
      ),
      'reply_not_found' => KlectError(
        KlectErrorKind.notFound,
        'The post you are replying to is gone.',
        code: error.code,
        cause: error,
      ),
      'blocked' => KlectError(
        KlectErrorKind.forbidden,
        'You cannot interact with this account.',
        code: error.code,
        cause: error,
      ),
      'bad_media' || 'media_not_yours' => KlectError(
        KlectErrorKind.storage,
        'One of the photos could not be attached. Try again.',
        code: error.code,
        cause: error,
      ),
      'too_many_media' => KlectError(
        KlectErrorKind.unknown,
        'A post can carry up to four photos.',
        code: error.code,
        cause: error,
      ),
      _ => error,
    };
  }

  /// One post by id, with its author joined.
  Future<PostModel?> fetchPost(String id) async {
    final row = await _guard(
      () => _client
          .from('posts')
          .select('*, author:profiles!author_id(*)')
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle(),
    );
    return row == null ? null : PostModel.fromJson(row);
  }

  /// Every photo of a post, ordered. `post_media` rows share `item_media`'s
  /// shape, so they parse through the same model.
  Future<List<ItemMedia>> fetchPostMedia(String postId) async {
    final rows = await _guard(
      () => _client
          .from('post_media')
          .select()
          .eq('post_id', postId)
          .order('position'),
    );
    return <ItemMedia>[for (final row in rows) ItemMedia.fromJson(row)];
  }

  /// `get_closeup(p_type, p_id)` — the single-tap detail payload.
  Future<Closeup> getCloseup(EntityType type, String id) async =>
      Closeup.fromJson(
        asMap(
          await _rpc('get_closeup', <String, dynamic>{
            'p_type': type.wire,
            'p_id': id,
          }),
        ),
      );

  /// `search_all(p_q, p_limit)` → people, collections, items, tags.
  Future<SearchResults> searchAll(String query, {int limit = 20}) async =>
      SearchResults.fromJson(
        asMap(
          await _rpc('search_all', <String, dynamic>{
            'p_q': query,
            'p_limit': limit,
          }),
        ),
      );

  /// `get_matches(p_limit)` — collectors ranked by taste overlap. Recomputes
  /// server-side on every call.
  Future<List<MatchModel>> getMatches({int limit = 20}) async {
    final rows = asMapList(
      await _rpc('get_matches', <String, dynamic>{'p_limit': limit}),
    );
    return <MatchModel>[for (final row in rows) MatchModel.fromJson(row)];
  }

  // ─────────────────────────────────────────────────────────────── social ──

  /// Whether the viewer currently likes an entity. Used by the offline queue
  /// to converge without double-toggling.
  Future<bool> hasLiked(EntityType type, String id) =>
      _hasRelation('likes', type, id);

  /// Whether the viewer currently saves an entity.
  Future<bool> hasSaved(EntityType type, String id) =>
      _hasRelation('saves', type, id);

  /// Whether the viewer currently reposts an entity.
  Future<bool> hasReposted(EntityType type, String id) =>
      _hasRelation('reposts', type, id);

  /// Whether the viewer currently follows [userId].
  Future<bool> hasFollowed(String userId) async {
    final me = currentUserId;
    if (me == null) return false;
    final rows = await _guard(
      () => _client
          .from('follows')
          .select('follower_id')
          .eq('follower_id', me)
          .eq('following_id', userId)
          .limit(1),
    );
    return rows.isNotEmpty;
  }

  Future<bool> _hasRelation(String table, EntityType type, String id) async {
    final me = currentUserId;
    if (me == null) return false;
    final rows = await _guard(
      () => _client
          .from(table)
          .select('user_id')
          .eq('user_id', me)
          .eq('entity_type', type.wire)
          .eq('entity_id', id)
          .limit(1),
    );
    return rows.isNotEmpty;
  }

  /// Blocks a user. Blocking is bidirectional and immediate server-side.
  Future<void> blockUser(String userId) => _guard(
    () => _client.from('blocks').upsert(<String, dynamic>{
      'blocker_id': requireUserId,
      'blocked_id': userId,
    }),
  );

  /// Lifts a block.
  Future<void> unblockUser(String userId) => _guard(
    () => _client
        .from('blocks')
        .delete()
        .eq('blocker_id', requireUserId)
        .eq('blocked_id', userId),
  );

  /// Mutes a user — their content stops surfacing, they are not told.
  Future<void> muteUser(String userId) => _guard(
    () => _client.from('mutes').upsert(<String, dynamic>{
      'muter_id': requireUserId,
      'muted_id': userId,
    }),
  );

  /// Unmutes a user.
  Future<void> unmuteUser(String userId) => _guard(
    () => _client
        .from('mutes')
        .delete()
        .eq('muter_id', requireUserId)
        .eq('muted_id', userId),
  );

  /// Everyone the viewer has blocked, newest first.
  Future<List<Profile>> fetchBlockedUsers() async {
    final rows = await _guard(
      () => _client
          .from('blocks')
          .select('blocked_id, created_at, profiles!blocked_id(*)')
          .eq('blocker_id', requireUserId)
          .order('created_at', ascending: false),
    );
    return <Profile>[
      for (final row in rows)
        if (asMap(row['profiles']).isNotEmpty)
          Profile.fromJson(asMap(row['profiles'])),
    ];
  }

  /// Followers of [userId].
  Future<List<Profile>> fetchFollowers(String userId, {int limit = 50}) async {
    final rows = await _guard(
      () => _client
          .from('follows')
          .select('profiles!follower_id(*)')
          .eq('following_id', userId)
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return _embeddedProfiles(rows, 'profiles');
  }

  /// Accounts [userId] follows.
  Future<List<Profile>> fetchFollowing(String userId, {int limit = 50}) async {
    final rows = await _guard(
      () => _client
          .from('follows')
          .select('profiles!following_id(*)')
          .eq('follower_id', userId)
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return _embeddedProfiles(rows, 'profiles');
  }

  List<Profile> _embeddedProfiles(
    List<Map<String, dynamic>> rows,
    String key,
  ) => <Profile>[
    for (final row in rows)
      if (asMap(row[key]).isNotEmpty) Profile.fromJson(asMap(row[key])),
  ];

  // ───────────────────────────────────────────────────────────── profiles ──

  /// Reads one profile by id.
  Future<Profile?> fetchProfile(String userId) async {
    final row = await _guard(
      () => _client.from('profiles').select().eq('id', userId).maybeSingle(),
    );
    return row == null ? null : Profile.fromJson(row);
  }

  /// Reads one profile by handle — the `/u/:username` route.
  Future<Profile?> fetchProfileByUsername(String username) async {
    final row = await _guard(
      () => _client
          .from('profiles')
          .select()
          .eq('username', username)
          .maybeSingle(),
    );
    return row == null ? null : Profile.fromJson(row);
  }

  /// True when [username] is free (or already belongs to the viewer).
  Future<bool> isUsernameAvailable(String username) async {
    final rows = await _guard(
      () => _client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .limit(1),
    );
    if (rows.isEmpty) return true;
    return asString(rows.first['id']) == currentUserId;
  }

  /// Patches the viewer's own profile row and returns the fresh copy.
  Future<Profile> updateMyProfile(Map<String, dynamic> patch) async {
    final row = await _guard(
      () => _client
          .from('profiles')
          .update(patch)
          .eq('id', requireUserId)
          .select()
          .single(),
    );
    return Profile.fromJson(row);
  }

  /// Stamps `onboarded_at`, which is what the router's onboarding guard reads.
  Future<Profile> completeOnboarding({
    required String displayName,
    required String username,
  }) => updateMyProfile(<String, dynamic>{
    'display_name': displayName,
    'username': username,
    'onboarded_at': DateTime.now().toUtc().toIso8601String(),
  });

  /// Suggested collectors for the onboarding follow step: the most-followed
  /// public accounts, excluding the viewer and anyone suspended.
  Future<List<Profile>> fetchSuggestedCollectors({int limit = 12}) async {
    final me = currentUserId;
    var query = _client
        .from('profiles')
        .select()
        .eq('account_visibility', AccountVisibility.public.wire)
        .eq('is_suspended', false);
    if (me != null) query = query.neq('id', me);
    final rows = await _guard(
      () => query.order('follower_count', ascending: false).limit(limit),
    );
    return <Profile>[for (final row in rows) Profile.fromJson(row)];
  }

  // ────────────────────────────────────────────────────────────── catalog ──

  /// The interest templates shown in onboarding step 2.
  Future<List<CollectionTemplate>> fetchCollectionTemplates() async {
    final rows = await _guard(
      () => _client.from('collection_templates').select().order('sort_order'),
    );
    return <CollectionTemplate>[
      for (final row in rows) CollectionTemplate.fromJson(row),
    ];
  }

  /// A user's collections, pinned first then by position.
  Future<List<CollectionModel>> fetchCollections(String userId) async {
    final rows = await _guard(
      () => _client
          .from('collections')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('is_pinned', ascending: false)
          .order('position'),
    );
    return <CollectionModel>[
      for (final row in rows) CollectionModel.fromJson(row),
    ];
  }

  /// One collection by id.
  Future<CollectionModel?> fetchCollection(String id) async {
    final row = await _guard(
      () => _client.from('collections').select().eq('id', id).maybeSingle(),
    );
    return row == null ? null : CollectionModel.fromJson(row);
  }

  /// The subcollections of a collection, in position order.
  Future<List<SubcollectionModel>> fetchSubcollections(
    String collectionId,
  ) async {
    final rows = await _guard(
      () => _client
          .from('subcollections')
          .select()
          .eq('collection_id', collectionId)
          .isFilter('deleted_at', null)
          .order('position'),
    );
    return <SubcollectionModel>[
      for (final row in rows) SubcollectionModel.fromJson(row),
    ];
  }

  /// One subcollection by id.
  Future<SubcollectionModel?> fetchSubcollection(String id) async {
    final row = await _guard(
      () => _client.from('subcollections').select().eq('id', id).maybeSingle(),
    );
    return row == null ? null : SubcollectionModel.fromJson(row);
  }

  /// Items inside a subcollection (or a whole collection when
  /// [subcollectionId] is null), in position order.
  Future<List<ItemModel>> fetchItems({
    String? collectionId,
    String? subcollectionId,
    int limit = 60,
  }) async {
    var query = _client.from('items').select().isFilter('deleted_at', null);
    if (subcollectionId != null) {
      query = query.eq('subcollection_id', subcollectionId);
    }
    if (collectionId != null) {
      query = query.eq('collection_id', collectionId);
    }
    final rows = await _guard(() => query.order('position').limit(limit));
    return <ItemModel>[for (final row in rows) ItemModel.fromJson(row)];
  }

  /// One item by id.
  Future<ItemModel?> fetchItem(String id) async {
    final row = await _guard(
      () => _client.from('items').select().eq('id', id).maybeSingle(),
    );
    return row == null ? null : ItemModel.fromJson(row);
  }

  /// Every photo of an item, ordered.
  Future<List<ItemMedia>> fetchItemMedia(String itemId) async {
    final rows = await _guard(
      () => _client
          .from('item_media')
          .select()
          .eq('item_id', itemId)
          .order('position'),
    );
    return <ItemMedia>[for (final row in rows) ItemMedia.fromJson(row)];
  }

  /// Creates a collection. Counters and slugs are handled server-side.
  Future<CollectionModel> createCollection({
    required String name,
    String? description,
    String? templateId,
    String? coverPath,
    String? coverBlurhash,
    String? accentColor,
    EntityVisibility visibility = EntityVisibility.public,
  }) async {
    final row = await _guard(
      () => _client
          .from('collections')
          .insert(<String, dynamic>{
            'user_id': requireUserId,
            'name': name,
            'description': description,
            'template_id': templateId,
            'cover_path': coverPath,
            'cover_blurhash': coverBlurhash,
            'accent_color': accentColor,
            'visibility': visibility.wire,
          })
          .select()
          .single(),
    );
    return CollectionModel.fromJson(row);
  }

  /// Creates a subcollection inside [collectionId].
  Future<SubcollectionModel> createSubcollection({
    required String collectionId,
    required String name,
    String? description,
    String? coverPath,
    String? coverBlurhash,
    EntityVisibility? visibility,
  }) async {
    final row = await _guard(
      () => _client
          .from('subcollections')
          .insert(<String, dynamic>{
            'user_id': requireUserId,
            'collection_id': collectionId,
            'name': name,
            'description': description,
            'cover_path': coverPath,
            'cover_blurhash': coverBlurhash,
            'visibility': visibility?.wire,
          })
          .select()
          .single(),
    );
    return SubcollectionModel.fromJson(row);
  }

  /// Creates an item. The cover is derived from media position 0 by a trigger.
  Future<ItemModel> createItem({
    required String collectionId,
    required String subcollectionId,
    required String title,
    String? description,
    String? brand,
    String? model,
    int? year,
    String? condition,
    String? rarity,
    double? purchasePrice,
    String? currency,
    Map<String, dynamic>? attributes,
    EntityVisibility? visibility,
  }) async {
    final row = await _guard(
      () => _client
          .from('items')
          .insert(<String, dynamic>{
            'user_id': requireUserId,
            'collection_id': collectionId,
            'subcollection_id': subcollectionId,
            'title': title,
            'description': description,
            'brand': brand,
            'model': model,
            'year': year,
            'condition': condition,
            'rarity': rarity,
            'purchase_price': purchasePrice,
            'currency': currency,
            'attributes': attributes ?? <String, dynamic>{},
            'visibility': visibility?.wire,
          })
          .select()
          .single(),
    );
    return ItemModel.fromJson(row);
  }

  /// Registers an uploaded photo against an item.
  Future<ItemMedia> createItemMedia({
    required String itemId,
    required String storagePath,
    required int width,
    required int height,
    String? blurhash,
    String? altText,
    String? mimeType,
    int? bytes,
    int position = 0,
  }) async {
    final row = await _guard(
      () => _client
          .from('item_media')
          .insert(<String, dynamic>{
            'item_id': itemId,
            'user_id': requireUserId,
            'storage_path': storagePath,
            'width': width,
            'height': height,
            'blurhash': blurhash,
            'alt_text': altText,
            'mime_type': mimeType,
            'bytes': bytes,
            'position': position,
          })
          .select()
          .single(),
    );
    return ItemMedia.fromJson(row);
  }

  /// Patches a collection.
  Future<void> updateCollection(String id, Map<String, dynamic> patch) =>
      _guard(() => _client.from('collections').update(patch).eq('id', id));

  /// Patches a subcollection.
  Future<void> updateSubcollection(String id, Map<String, dynamic> patch) =>
      _guard(() => _client.from('subcollections').update(patch).eq('id', id));

  /// Patches an item — including moving it between subcollections, which the
  /// counter triggers reconcile on both sides.
  Future<void> updateItem(String id, Map<String, dynamic> patch) =>
      _guard(() => _client.from('items').update(patch).eq('id', id));

  /// Persists a manual drag-reorder.
  Future<void> reorder({
    required String table,
    required List<String> orderedIds,
  }) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _guard(
        () => _client
            .from(table)
            .update(<String, dynamic>{'position': i})
            .eq('id', orderedIds[i]),
      );
    }
  }

  /// Soft-deletes a collection; the cascade purges its polymorphic rows.
  Future<void> deleteCollection(String id) =>
      _guard(() => _client.from('collections').delete().eq('id', id));

  /// Soft-deletes a subcollection.
  Future<void> deleteSubcollection(String id) =>
      _guard(() => _client.from('subcollections').delete().eq('id', id));

  /// Soft-deletes an item.
  Future<void> deleteItem(String id) =>
      _guard(() => _client.from('items').delete().eq('id', id));

  // ───────────────────────────────────────────────────────────── comments ──

  /// A page of **root** comments for any entity.
  ///
  /// [sort] picks the ordering: [CommentSort.top] is like-count descending
  /// (ties oldest-first), [CommentSort.newest] is newest-first. Replies come
  /// separately via [fetchCommentReplies]; the viewer's like state is seeded
  /// in one batch via [fetchLikedCommentIds].
  Future<List<CommentModel>> fetchComments({
    required EntityType type,
    required String id,
    CommentSort sort = CommentSort.top,
    int limit = 20,
    int offset = 0,
  }) async {
    final query = _client
        .from('comments')
        .select('*, author:profiles!author_id(*)')
        .eq('entity_type', type.wire)
        .eq('entity_id', id)
        .isFilter('parent_id', null)
        .isFilter('deleted_at', null);
    final ordered = switch (sort) {
      CommentSort.top =>
        query
            .order('like_count', ascending: false)
            .order('created_at', ascending: true),
      CommentSort.newest => query.order('created_at', ascending: false),
    };
    final rows = await _guard(() => ordered.range(offset, offset + limit - 1));
    return <CommentModel>[for (final row in rows) CommentModel.fromJson(row)];
  }

  /// Every reply on an entity's thread, oldest first. One query serves every
  /// loaded root — the view attaches each reply to its parent.
  Future<List<CommentModel>> fetchCommentReplies({
    required EntityType type,
    required String id,
    int limit = 400,
  }) async {
    final rows = await _guard(
      () => _client
          .from('comments')
          .select('*, author:profiles!author_id(*)')
          .eq('entity_type', type.wire)
          .eq('entity_id', id)
          .not('parent_id', 'is', null)
          .isFilter('deleted_at', null)
          .order('created_at')
          .limit(limit),
    );
    return <CommentModel>[for (final row in rows) CommentModel.fromJson(row)];
  }

  /// Which of [commentIds] the viewer has liked — **one** query for a whole
  /// page of comments, instead of a `viewer_liked` that never arrives from a
  /// plain table select.
  Future<Set<String>> fetchLikedCommentIds(List<String> commentIds) async {
    final me = currentUserId;
    if (me == null || commentIds.isEmpty) return const <String>{};
    final rows = await _guard(
      () => _client
          .from('likes')
          .select('entity_id')
          .eq('user_id', me)
          .eq('entity_type', EntityType.comment.wire)
          .inFilter('entity_id', commentIds),
    );
    return <String>{for (final row in rows) asString(row['entity_id'])};
  }

  // ──────────────────────────────────────────────────────── notifications ──

  /// The viewer's notifications, newest first.
  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async {
    final rows = await _guard(
      () => _client
          .from('notifications')
          .select('*, actor:profiles!actor_id(*)')
          .eq('user_id', requireUserId)
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return <NotificationModel>[
      for (final row in rows) NotificationModel.fromJson(row),
    ];
  }

  /// How many notifications are unread — for the tab badge.
  ///
  /// A `HEAD` request with `count=exact`: Postgres counts, nothing is
  /// materialised or shipped — the badge costs the same whether 3 or 3000
  /// rows are unread.
  Future<int> fetchUnreadNotificationCount() => _guard(
    () => _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', requireUserId)
        .isFilter('read_at', null),
  );

  /// `mark_notifications_read(p_ids)` — null marks everything read.
  Future<int> markNotificationsRead({List<String>? ids}) async => asInt(
    await _rpc('mark_notifications_read', <String, dynamic>{'p_ids': ids}),
  );

  // ──────────────────────────────────────────────────────────── messaging ──

  /// `start_dm(p_other)` → the conversation id. One DM per pair, ever.
  ///
  /// Throws [KlectErrorKind.messagesBlocked] when the recipient's
  /// `allow_messages_from` refuses.
  Future<String> startDm(String otherUserId) async => asString(
    await _rpc('start_dm', <String, dynamic>{'p_other': otherUserId}),
  );

  /// `mark_conversation_read(p_conversation)` — zeroes unread and clears the
  /// matching message notifications.
  Future<void> markConversationRead(String conversationId) async {
    await _rpc('mark_conversation_read', <String, dynamic>{
      'p_conversation': conversationId,
    });
  }

  /// The viewer's inbox, most recent first.
  Future<List<Conversation>> fetchConversations({int limit = 50}) async {
    final me = requireUserId;
    final memberships = await _guard(
      () => _client
          .from('conversation_members')
          .select(
            'conversation_id, unread_count, last_read_at, '
            'conversations!inner(*)',
          )
          .eq('user_id', me)
          .isFilter('left_at', null)
          .order('joined_at', ascending: false)
          .limit(limit),
    );

    final conversations = <Conversation>[];
    for (final row in memberships) {
      final conversationJson = asMap(row['conversations']);
      if (conversationJson.isEmpty) continue;
      conversationJson['unread_count'] = asInt(row['unread_count']);
      conversations.add(Conversation.fromJson(conversationJson));
    }
    conversations.sort((a, b) {
      final ax = a.lastMessageAt ?? a.createdAt ?? DateTime(0);
      final bx = b.lastMessageAt ?? b.createdAt ?? DateTime(0);
      return bx.compareTo(ax);
    });
    return conversations;
  }

  /// Members of one conversation, with their profiles.
  Future<List<ConversationMember>> fetchConversationMembers(
    String conversationId,
  ) async {
    final rows = await _guard(
      () => _client
          .from('conversation_members')
          .select('*, profile:profiles!user_id(*)')
          .eq('conversation_id', conversationId),
    );
    return <ConversationMember>[
      for (final row in rows) ConversationMember.fromJson(row),
    ];
  }

  /// A page of messages, newest first (reverse the list to render a thread).
  Future<List<MessageModel>> fetchMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    var query = _client
        .from('messages')
        .select('*, author:profiles!author_id(*)')
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null);
    final cutoff = isoOrNull(before);
    if (cutoff != null) query = query.lt('created_at', cutoff);
    final rows = await _guard(
      () => query.order('created_at', ascending: false).limit(limit),
    );
    return <MessageModel>[for (final row in rows) MessageModel.fromJson(row)];
  }

  /// Sends a message by inserting it. Triggers then update the conversation
  /// preview, bump unread counts, and create notifications.
  Future<MessageModel> sendMessage({
    required String conversationId,
    String? body,
    MessageKind kind = MessageKind.text,
    List<Map<String, dynamic>> attachments = const <Map<String, dynamic>>[],
    EntityType? sharedEntityType,
    String? sharedEntityId,
    String? replyToId,
  }) async {
    final row = await _guard(
      () => _client
          .from('messages')
          .insert(<String, dynamic>{
            'conversation_id': conversationId,
            'author_id': requireUserId,
            'body': body,
            'kind': kind.wire,
            'attachments': attachments,
            'shared_entity_type': sharedEntityType?.wire,
            'shared_entity_id': sharedEntityId,
            'reply_to_id': replyToId,
          })
          .select('*, author:profiles!author_id(*)')
          .single(),
    );
    return MessageModel.fromJson(row);
  }

  /// Adds an emoji reaction to a message.
  Future<void> reactToMessage(String messageId, String emoji) => _guard(
    () => _client.from('message_reactions').upsert(<String, dynamic>{
      'message_id': messageId,
      'user_id': requireUserId,
      'emoji': emoji,
    }),
  );

  /// Removes an emoji reaction.
  Future<void> unreactToMessage(String messageId, String emoji) => _guard(
    () => _client
        .from('message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', requireUserId)
        .eq('emoji', emoji),
  );

  // ──────────────────────────────────────────────────────────────── calls ──

  /// Starts a call in a conversation. The callee learns about it through
  /// realtime on `calls`.
  Future<CallModel> createCall({
    required String conversationId,
    CallKind kind = CallKind.audio,
  }) async {
    final row = await _guard(
      () => _client
          .from('calls')
          .insert(<String, dynamic>{
            'conversation_id': conversationId,
            'created_by': requireUserId,
            'kind': kind.wire,
            'status': CallStatus.ringing.wire,
          })
          .select()
          .single(),
    );
    return CallModel.fromJson(row);
  }

  /// Reads one call.
  Future<CallModel?> fetchCall(String callId) async {
    final row = await _guard(
      () => _client.from('calls').select().eq('id', callId).maybeSingle(),
    );
    return row == null ? null : CallModel.fromJson(row);
  }

  /// Moves a call through its lifecycle. Pass [durationSeconds] when ending.
  Future<void> updateCallStatus(
    String callId,
    CallStatus status, {
    int? durationSeconds,
    String? endReason,
  }) => _guard(
    () => _client
        .from('calls')
        .update(<String, dynamic>{
          'status': status.wire,
          if (status == CallStatus.active)
            'started_at': DateTime.now().toUtc().toIso8601String(),
          if (!status.isLive)
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          'duration_seconds': ?durationSeconds,
          'end_reason': ?endReason,
        })
        .eq('id', callId),
  );

  /// Records that the viewer joined the media session.
  Future<void> joinCall(String callId) => _guard(
    () => _client.from('call_participants').upsert(<String, dynamic>{
      'call_id': callId,
      'user_id': requireUserId,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  /// Records that the viewer left the media session.
  Future<void> leaveCall(String callId) => _guard(
    () => _client
        .from('call_participants')
        .update(<String, dynamic>{
          'left_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('call_id', callId)
        .eq('user_id', requireUserId),
  );

  /// Sends one WebRTC signal. Signals are applied in `created_at` order.
  Future<void> sendCallSignal({
    required String callId,
    required CallSignalType type,
    required Map<String, dynamic> payload,
    String? recipientId,
  }) => _guard(
    () => _client.from('call_signals').insert(<String, dynamic>{
      'call_id': callId,
      'sender_id': requireUserId,
      'recipient_id': recipientId,
      'type': type.wire,
      'payload': payload,
    }),
  );

  // ────────────────────────────────────────────────────────────── storage ──

  /// Turns a stored path into an absolute, loadable URL.
  ///
  /// Accepts three shapes:
  ///  * an absolute URL — returned unchanged;
  ///  * a bucket-prefixed path (`media/…`) — split and resolved;
  ///  * a bare object key — resolved against [bucket].
  String? publicUrl(
    String? path, {
    StorageBucket bucket = StorageBucket.media,
  }) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    var resolved = bucket;
    var key = path;
    final slash = path.indexOf('/');
    if (slash > 0) {
      final prefix = StorageBucket.tryParse(path.substring(0, slash));
      if (prefix != null) {
        resolved = prefix;
        key = path.substring(slash + 1);
      }
    }
    return _client.storage.from(resolved.id).getPublicUrl(key);
  }

  /// A time-limited URL for the private `chat` bucket.
  Future<String> signedUrl(
    String path, {
    StorageBucket bucket = StorageBucket.chat,
    int expiresInSeconds = 3600,
  }) => _guard(
    () =>
        _client.storage.from(bucket.id).createSignedUrl(path, expiresInSeconds),
  );

  /// Uploads bytes and returns the object key.
  ///
  /// The **first path segment must be the uploader's user id** — the storage
  /// policy enforces it, so this method builds the path for you.
  Future<String> upload({
    required StorageBucket bucket,
    required String objectPath,
    required Uint8List bytes,
    String contentType = 'image/webp',
    bool upsert = false,
  }) async {
    final userId = requireUserId;
    final key = objectPath.startsWith('$userId/')
        ? objectPath
        : '$userId/$objectPath';
    await _guard(
      () => _client.storage
          .from(bucket.id)
          .uploadBinary(
            key,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: upsert),
          ),
    );
    return key;
  }

  /// Deletes an uploaded object.
  Future<void> removeUpload(StorageBucket bucket, String objectPath) => _guard(
    () => _client.storage.from(bucket.id).remove(<String>[objectPath]),
  );

  // ───────────────────────────────────────────────────────────── realtime ──

  /// A channel that fires whenever the entity row's counters change.
  ///
  /// One `UPDATE` event carries every fresh counter at once — never subscribe
  /// to `likes`. Call `.subscribe()` on the result.
  RealtimeChannel entityCounterChannel({
    required EntityType type,
    required String id,
    required void Function(Map<String, dynamic> row) onRow,
  }) => _client
      .channel('counters:${type.wire}:$id')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: type.table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: id,
        ),
        callback: (payload) => onRow(payload.newRecord),
      );

  /// A channel of the viewer's incoming notifications.
  RealtimeChannel notificationsChannel({
    required void Function(Map<String, dynamic> row) onInsert,
  }) => _client
      .channel('notifications:$requireUserId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: requireUserId,
        ),
        callback: (payload) => onInsert(payload.newRecord),
      );

  /// A channel of new messages in one conversation.
  RealtimeChannel messagesChannel({
    required String conversationId,
    required void Function(Map<String, dynamic> row) onInsert,
  }) => _client
      .channel('messages:$conversationId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (payload) => onInsert(payload.newRecord),
      );

  /// A channel of WebRTC signals for one call.
  RealtimeChannel callSignalsChannel({
    required String callId,
    required void Function(Map<String, dynamic> row) onSignal,
  }) => _client
      .channel('call:$callId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (payload) => onSignal(payload.newRecord),
      );

  /// Tears a channel down.
  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  // ──────────────────────────────────────────────────────────────── admin ──
  // Every one of these re-checks `is_staff()` / `is_admin()` server-side, so a
  // leaked route exposes nothing. The client gates the UI on `user_roles`
  // purely so staff-only affordances do not appear for everyone else.

  /// The viewer's staff roles, empty for normal accounts.
  Future<List<String>> fetchMyRoles() async {
    final me = currentUserId;
    if (me == null) return const <String>[];
    final rows = await _guard(
      () => _client.from('user_roles').select('role').eq('user_id', me),
    );
    return <String>[for (final row in rows) asString(row['role'])];
  }

  /// `admin_metrics()`.
  Future<Map<String, dynamic>> adminMetrics() async =>
      asMap(await _rpc('admin_metrics'));

  /// `admin_list_reports(p_status, p_limit, p_offset)`.
  Future<List<Map<String, dynamic>>> adminListReports({
    String status = 'open',
    int limit = 50,
    int offset = 0,
  }) async => asMapList(
    await _rpc('admin_list_reports', <String, dynamic>{
      'p_status': status,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );

  /// `admin_resolve_report(...)`. Resolving one report auto-resolves every
  /// other open report about the same target.
  Future<Map<String, dynamic>> adminResolveReport({
    required String reportId,
    required String action,
    String? reason,
    int? suspendDays,
  }) async => asMap(
    await _rpc('admin_resolve_report', <String, dynamic>{
      'p_report': reportId,
      'p_action': action,
      'p_reason': reason,
      'p_suspend_days': suspendDays,
    }),
  );

  /// `admin_moderate_entity(...)`.
  Future<Map<String, dynamic>> adminModerateEntity({
    required EntityType type,
    required String entityId,
    required bool hidden,
    String? reason,
  }) async => asMap(
    await _rpc('admin_moderate_entity', <String, dynamic>{
      'p_type': type.wire,
      'p_id': entityId,
      'p_hidden': hidden,
      'p_reason': reason,
    }),
  );

  /// `admin_set_user_state(...)`.
  Future<Map<String, dynamic>> adminSetUserState({
    required String userId,
    required bool suspended,
    int? days,
    String? reason,
  }) async => asMap(
    await _rpc('admin_set_user_state', <String, dynamic>{
      'p_user': userId,
      'p_suspended': suspended,
      'p_days': days,
      'p_reason': reason,
    }),
  );

  /// `admin_set_verified(p_user, p_verified)`.
  Future<Map<String, dynamic>> adminSetVerified({
    required String userId,
    required bool verified,
  }) async => asMap(
    await _rpc('admin_set_verified', <String, dynamic>{
      'p_user': userId,
      'p_verified': verified,
    }),
  );

  /// `admin_set_role(p_user, p_role, p_grant)` — superadmin only.
  Future<Map<String, dynamic>> adminSetRole({
    required String userId,
    required String role,
    required bool grant,
  }) async => asMap(
    await _rpc('admin_set_role', <String, dynamic>{
      'p_user': userId,
      'p_role': role,
      'p_grant': grant,
    }),
  );

  /// `admin_user_detail(p_user)`.
  Future<Map<String, dynamic>> adminUserDetail(String userId) async => asMap(
    await _rpc('admin_user_detail', <String, dynamic>{'p_user': userId}),
  );
}

/// The app-wide API instance.
final klectApiProvider = Provider<KlectApi>(
  (ref) => KlectApi(ref.watch(supabaseClientProvider)),
  name: 'klectApi',
);
