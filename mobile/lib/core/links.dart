import 'models/models.dart';

/// Canonical KLECT links.
///
/// Mobile routes and web URLs use the same paths, so a shared link opens the
/// right screen on either client.
abstract final class KlectLinks {
  /// Public web origin. Overridable per build with
  /// `--dart-define=KLECT_WEB_ORIGIN=https://…`; it is the only place the
  /// host appears.
  static const String webOrigin = String.fromEnvironment(
    'KLECT_WEB_ORIGIN',
    defaultValue: 'https://klect-web.vercel.app',
  );

  /// The origin without its scheme — for human-facing copy like
  /// "your profile lives at …".
  static final String displayOrigin = webOrigin.replaceFirst(
    RegExp('^https?://'),
    '',
  );

  /// In-app path for an entity.
  static String pathFor(EntityType type, String id) => switch (type) {
    EntityType.collection => '/c/$id',
    EntityType.subcollection => '/s/$id',
    EntityType.item => '/i/$id',
    EntityType.post => '/closeup/post/$id',
    EntityType.comment => '/closeup/comment/$id',
  };

  /// In-app path for a profile.
  static String profilePath(String username) => '/u/$username';

  /// Shareable absolute URL for an entity.
  static String urlFor(EntityType type, String id) =>
      '$webOrigin${pathFor(type, id)}';

  /// Shareable absolute URL for a profile.
  static String profileUrl(String username) =>
      '$webOrigin${profilePath(username)}';

  /// The closeup route for an entity — the single-tap destination.
  static String closeupPath(EntityType type, String id) =>
      '/closeup/${type.wire}/$id';

  /// The immersive route for an entity — the double-tap destination.
  static String immersivePath(EntityType type, String id) =>
      '/immersive/${type.wire}/$id';
}
