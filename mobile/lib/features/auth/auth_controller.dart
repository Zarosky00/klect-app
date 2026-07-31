import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../core/offline/action_queue.dart';
import '../../core/supabase.dart';
import '../notifications/notification_surfaces.dart';

/// What an auth form is doing right now.
@immutable
class AuthStatus {
  /// Creates a status.
  const AuthStatus({this.busy = false, this.error, this.message});

  /// A request is in flight.
  final bool busy;

  /// The last failure, ready to render under the form.
  final KlectError? error;

  /// A success notice, e.g. "check your inbox".
  final String? message;

  /// Copy with overrides.
  AuthStatus copyWith({
    bool? busy,
    KlectError? error,
    String? message,
    bool clear = false,
  }) =>
      AuthStatus(
        busy: busy ?? this.busy,
        error: clear ? null : (error ?? this.error),
        message: clear ? null : (message ?? this.message),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthStatus &&
          other.busy == busy &&
          other.error == error &&
          other.message == message;

  @override
  int get hashCode => Object.hash(busy, error, message);
}

/// Sign in, sign up, password reset, sign out.
///
/// Screens call these and render [AuthStatus]; nothing here navigates — the
/// router's redirect guard reacts to the session changing.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => const AuthStatus();

  SupabaseClient get _client => ref.read(supabaseClientProvider);

  /// Email + password sign in.
  Future<bool> signIn({required String email, required String password}) =>
      _run(() async {
        await _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      });

  /// Email + password sign up.
  ///
  /// A database trigger creates the `profiles` row; the router then sends the
  /// new account to onboarding because `onboarded_at` is still null.
  Future<bool> signUp({
    required String email,
    required String password,
    String? username,
  }) =>
      _run(() async {
        final response = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: username == null
              ? null
              : <String, dynamic>{'username': username.trim()},
        );
        if (response.session == null) {
          state = state.copyWith(
            message: 'Check your inbox to confirm your email, then sign in.',
          );
        }
      });

  /// Sends the password-reset email.
  Future<bool> sendPasswordReset(String email) => _run(() async {
        await _client.auth.resetPasswordForEmail(email.trim());
        state = state.copyWith(
          message: 'If that address has an account, a reset link is on its way.',
        );
      });

  /// Applies a new password once the recovery link has been followed.
  Future<bool> updatePassword(String password) => _run(() async {
        await _client.auth.updateUser(UserAttributes(password: password));
        state = state.copyWith(message: 'Password updated.');
      });

  /// Signs out and drops per-account client state so nothing leaks into the
  /// next session.
  Future<void> signOut() async {
    await ref.read(pushNotificationsProvider).unregister();
    ref.read(interactionSeedStoreProvider).clear();
    await ref.read(offlineQueueProvider).clear();
    await _client.auth.signOut();
    state = const AuthStatus();
  }

  /// Clears the error/message banner.
  void clear() => state = state.copyWith(clear: true, busy: false);

  Future<bool> _run(Future<void> Function() body) async {
    state = const AuthStatus(busy: true);
    try {
      await body();
      state = state.copyWith(busy: false);
      return true;
    } catch (error) {
      state = AuthStatus(busy: false, error: KlectError.from(error));
      return false;
    }
  }
}

/// The auth form controller.
final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
  name: 'authController',
);

/// The signed-in user's own profile.
///
/// The router's guard reads this to decide between onboarding and the app, so
/// it must stay cheap and cached.
final myProfileProvider = FutureProvider<Profile?>(
  (ref) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;
    return ref.watch(klectApiProvider).fetchProfile(userId);
  },
  name: 'myProfile',
);

/// The staff roles the viewer holds — gates staff-only affordances. The server
/// enforces this regardless, so a leaked route exposes nothing.
final myRolesProvider = FutureProvider<List<String>>(
  (ref) async {
    if (ref.watch(currentUserIdProvider) == null) return const <String>[];
    return ref.watch(klectApiProvider).fetchMyRoles();
  },
  name: 'myRoles',
);
