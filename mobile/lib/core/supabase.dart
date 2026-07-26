import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Connection details for the `new_klect` project.
///
/// Only the **publishable** key ever appears in client code. The service-role
/// key is not in this repository and must never be — server-only work belongs
/// in an edge function.
abstract final class KlectSupabase {
  /// Project URL.
  static const String url = 'https://dikhuygcwxnrsckqglzg.supabase.co';

  /// Publishable (anon) key. Safe to ship; RLS is the real boundary.
  static const String publishableKey =
      'sb_publishable_nwJjxG8yJ01lTjrv6pXQww_mQ9MNq5t';

  static bool _initialised = false;

  /// Whether [initialize] has completed.
  static bool get isInitialised => _initialised;

  /// Boots the SDK and restores any persisted session.
  ///
  /// Call once from `main()` before `runApp`. Safe to call twice.
  static Future<void> initialize() async {
    if (_initialised) return;
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.error,
      ),
    );
    _initialised = true;
  }

  /// The live client. Throws if [initialize] has not run.
  static SupabaseClient get client => Supabase.instance.client;
}

/// The Supabase client. Override this in tests with a fake.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => KlectSupabase.client,
  name: 'supabaseClient',
);

/// The raw auth event stream: sign-in, sign-out, token refresh, recovery.
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
  name: 'authStateChanges',
);

/// The current session, kept fresh by [authStateChangesProvider].
///
/// Emits the bootstrapped session immediately so the splash screen can decide
/// where to go without waiting for a network round-trip.
final sessionProvider = Provider<Session?>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    final event = ref.watch(authStateChangesProvider);
    return event.maybeWhen(
      data: (state) => state.session,
      orElse: () => client.auth.currentSession,
    );
  },
  name: 'session',
);

/// The signed-in user's id, or null when logged out.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider)?.user.id,
  name: 'currentUserId',
);

/// Whether anybody is signed in.
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentUserIdProvider) != null,
  name: 'isSignedIn',
);
