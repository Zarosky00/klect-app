// ignore_for_file: prefer_initializing_formals
import 'package:klect/core/api/api_error.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A [KlectApi] stand-in that models the server the way Postgres actually
/// behaves: each toggle **flips** the stored relationship and returns the
/// authoritative `{active, count}` afterwards.
///
/// It also counts calls, which is how the coalescing test proves that ten taps
/// do not become ten round trips.
class FakeKlectApi implements KlectApi {
  /// Creates a fake with a starting state.
  FakeKlectApi({
    bool liked = false,
    int likeCount = 0,
    bool saved = false,
    int saveCount = 0,
    bool reposted = false,
    int repostCount = 0,
    this.userId = 'test-user',
  })  : _liked = liked,
        _likeCount = likeCount,
        _saved = saved,
        _saveCount = saveCount,
        _reposted = reposted,
        _repostCount = repostCount;

  /// The signed-in user this fake reports.
  final String? userId;

  bool _liked;
  int _likeCount;
  bool _saved;
  int _saveCount;
  bool _reposted;
  int _repostCount;

  /// How many `toggle_like` round trips happened.
  int likeCalls = 0;

  /// How many `toggle_save` round trips happened.
  int saveCalls = 0;

  /// How many `toggle_repost` round trips happened.
  int repostCalls = 0;

  /// How many `toggle_follow` round trips happened.
  int followCalls = 0;

  /// Set to make the next toggle fail with this error.
  KlectError? failWith;

  /// Server truth, for assertions.
  bool get serverLiked => _liked;

  /// Server truth, for assertions.
  int get serverLikeCount => _likeCount;

  /// Server truth, for assertions.
  bool get serverSaved => _saved;

  /// Server truth, for assertions.
  int get serverSaveCount => _saveCount;

  void _maybeFail() {
    final error = failWith;
    if (error != null) {
      failWith = null;
      throw error;
    }
  }

  @override
  Future<ToggleResult> toggleLike(EntityType type, String id) async {
    likeCalls++;
    _maybeFail();
    _liked = !_liked;
    _likeCount += _liked ? 1 : -1;
    if (_likeCount < 0) _likeCount = 0;
    return ToggleResult(active: _liked, count: _likeCount);
  }

  @override
  Future<ToggleResult> toggleSave(
    EntityType type,
    String id, {
    String? note,
  }) async {
    saveCalls++;
    _maybeFail();
    _saved = !_saved;
    _saveCount += _saved ? 1 : -1;
    if (_saveCount < 0) _saveCount = 0;
    return ToggleResult(active: _saved, count: _saveCount);
  }

  @override
  Future<ToggleResult> toggleRepost(
    EntityType type,
    String id, {
    String? quote,
  }) async {
    repostCalls++;
    _maybeFail();
    _reposted = !_reposted;
    _repostCount += _reposted ? 1 : -1;
    if (_repostCount < 0) _repostCount = 0;
    return ToggleResult(active: _reposted, count: _repostCount);
  }

  @override
  Future<ToggleResult> toggleFollow(String targetUserId) async {
    followCalls++;
    _maybeFail();
    return const ToggleResult(active: true, count: 1);
  }

  @override
  Future<bool> hasLiked(EntityType type, String id) async => _liked;

  @override
  Future<bool> hasSaved(EntityType type, String id) async => _saved;

  @override
  Future<bool> hasReposted(EntityType type, String id) async => _reposted;

  @override
  Future<bool> hasFollowed(String targetUserId) async => false;

  @override
  Future<int> recordView(EntityType type, String id) async => 1;

  @override
  String? get currentUserId => userId;

  @override
  String get requireUserId =>
      userId ?? (throw const KlectError(KlectErrorKind.auth, 'No session'));

  // Everything else is out of scope for these tests. `noSuchMethod` keeps the
  // fake short without silently pretending an unimplemented call worked: it
  // throws, so a test that reaches for an unstubbed method fails loudly.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  SupabaseClient get client =>
      throw UnimplementedError('FakeKlectApi exposes no Supabase client');
}
