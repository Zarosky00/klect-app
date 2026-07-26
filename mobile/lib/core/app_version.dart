/// The semantic version of this build.
///
/// ⚠ MUST move in lockstep with BOTH of these on every release:
///   * `version:` in `pubspec.yaml` (its `x.y.z` part — currently `1.2.0+3`),
///   * the tag of the GitHub release that ships this build
///     (repo `Zarosky00/klect-app`, tagged `vX.Y.Z`, asset `klect.apk`).
///
/// The in-app update checker (`core/updates/update_checker.dart`) compares
/// this constant against the newest release tag. If this constant lags the
/// pubspec, users are told to "update" to the build they already run; if it
/// leads, they never hear about real updates.
const String kAppVersion = '1.3.0';
