/// The semantic version of this build.
///
/// Must move in lockstep with both of these on every release:
///   * `version:` in `pubspec.yaml` (currently `1.6.6+16`),
///   * the GitHub release tag that ships this build
///     (repo `Zarosky00/klect-app`, tag `vX.Y.Z`, asset `klect.apk`).
///
/// The in-app update checker (`core/updates/update_checker.dart`) compares
/// this constant against the newest release tag. If this constant lags the
/// pubspec, users are told to update to the build they already run; if it
/// leads, they never hear about real updates.
const String kAppVersion = '1.6.6';
