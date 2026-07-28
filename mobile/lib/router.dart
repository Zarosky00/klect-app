import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models/models.dart';
import 'core/supabase.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/sign_up_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/chat/call_screen.dart';
import 'features/chat/conversation_screen.dart';
import 'features/chat/group_info_screen.dart';
import 'features/chat/messages_screen.dart';
import 'features/chat/new_group_screen.dart';
import 'features/create/create_collection_screen.dart';
import 'features/create/create_item_flow_screen.dart';
import 'features/create/create_pick_screen.dart';
import 'features/create/create_subcollection_screen.dart';
import 'features/library/collection_screen.dart';
import 'features/library/item_screen.dart';
import 'features/library/subcollection_screen.dart';
import 'features/matches/matches_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/pulse/pulse_screen.dart';
import 'features/pulse/thread/post_thread_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/appearance_settings_screen.dart';
import 'features/settings/blocked_users_screen.dart';
import 'features/settings/privacy_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/root_shell.dart';
import 'features/surf/closeup_screen.dart';
import 'features/surf/immersive_screen.dart';
import 'features/surf/surf_screen.dart';
import 'ui/ui.dart';

/// Named route paths, so nothing in the app hand-writes a URL.
abstract final class Routes {
  /// Session bootstrap.
  static const String splash = '/splash';

  /// Sign in.
  static const String signIn = '/signin';

  /// Sign up.
  static const String signUp = '/signup';

  /// Password reset request.
  static const String forgotPassword = '/forgot-password';

  /// Three-step onboarding.
  static const String onboarding = '/onboarding';

  /// The Pinterest grid — the home tab.
  static const String surf = '/surf';

  /// The X-style stream.
  static const String pulse = '/pulse';

  /// The create hub.
  static const String create = '/create';

  /// Notifications.
  static const String notifications = '/notifications';

  /// The signed-in user's own profile tab.
  static const String me = '/me';

  /// Search.
  static const String search = '/search';

  /// Collectors like you.
  static const String matches = '/matches';

  /// Inbox.
  static const String messages = '/messages';

  /// Settings hub.
  static const String settings = '/settings';
}

/// Paths reachable while signed out.
const Set<String> _publicPaths = <String>{
  Routes.signIn,
  Routes.signUp,
  Routes.forgotPassword,
};

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// The app router.
///
/// Every route in the product is declared here, including the ones whose
/// screens are still placeholders — so deep links, the back gesture and the
/// tab shell all behave correctly from day one.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionProvider, (_, _) => refresh.value++)
    ..listen(myProfileProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final signedIn = ref.read(currentUserIdProvider) != null;
      final path = state.matchedLocation;

      if (!signedIn) {
        return _publicPaths.contains(path) ? null : Routes.signIn;
      }

      // Signed in: wait for the profile before deciding between onboarding
      // and the app, otherwise a slow network flashes the wrong screen.
      final profile = ref.read(myProfileProvider);
      if (!profile.hasValue && !profile.hasError) {
        return path == Routes.splash ? null : Routes.splash;
      }

      final onboarded = profile.value?.isOnboarded ?? false;
      if (!onboarded) {
        return path == Routes.onboarding ? null : Routes.onboarding;
      }

      if (_publicPaths.contains(path) ||
          path == Routes.splash ||
          path == Routes.onboarding) {
        return Routes.surf;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── the tab shell ────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            RootShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.surf,
                builder: (context, state) => const SurfScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.pulse,
                builder: (context, state) => const PulseScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.create,
                builder: (context, state) => const CreatePickScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.notifications,
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.me,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // `/` is the shell's front door.
      GoRoute(path: '/', redirect: (context, state) => Routes.surf),

      // ── create flows, pushed over the shell ──────────────────────────
      GoRoute(
        path: '/create/collection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CreateCollectionScreen(
          // `return=1` pops back with the created shelf so the flow that
          // needed it resumes, instead of stranding the user on its page.
          popOnCreate: state.uri.queryParameters['return'] == '1',
        ),
      ),
      GoRoute(
        path: '/create/subcollection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CreateSubcollectionScreen(
          collectionId: state.uri.queryParameters['collection'],
          popOnCreate: state.uri.queryParameters['return'] == '1',
        ),
      ),
      GoRoute(
        path: '/create/item',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CreateItemFlowScreen(
          draftId: state.uri.queryParameters['draft'],
          collectionId: state.uri.queryParameters['collection'],
          subcollectionId: state.uri.queryParameters['subcollection'],
        ),
      ),

      // ── discovery ────────────────────────────────────────────────────
      GoRoute(
        path: Routes.search,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            SearchScreen(initialQuery: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: Routes.matches,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MatchesScreen(),
      ),

      // ── the post thread — a Pulse row's single-tap destination ───────
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PostThreadScreen(
          postId: state.pathParameters['id'] ?? '',
          highlightCommentId: state.uri.queryParameters['comment'],
        ),
      ),
      // Canonical short link (`klect.app/p/:id`, shared by both clients)
      // lands on the same thread.
      GoRoute(
        path: '/p/:id',
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) =>
            '/post/${state.pathParameters['id'] ?? ''}',
      ),

      // ── the gesture contract's two destinations ──────────────────────
      GoRoute(
        path: '/closeup/:type/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CloseupScreen(
          entityType: EntityType.parse(state.pathParameters['type']),
          entityId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/immersive/:type/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ImmersiveScreen(
          entityType: EntityType.parse(state.pathParameters['type']),
          entityId: state.pathParameters['id'] ?? '',
          initialIndex: int.tryParse(state.uri.queryParameters['i'] ?? '') ?? 0,
        ),
      ),

      // ── canonical, shareable entity links ────────────────────────────
      GoRoute(
        path: '/u/:username',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ProfileScreen(username: state.pathParameters['username']),
      ),
      GoRoute(
        path: '/c/:collectionId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CollectionScreen(
          collectionId: state.pathParameters['collectionId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/s/:subcollectionId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => SubcollectionScreen(
          subcollectionId: state.pathParameters['subcollectionId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/i/:itemId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ItemScreen(itemId: state.pathParameters['itemId'] ?? ''),
      ),

      // ── messaging and calls ──────────────────────────────────────────
      GoRoute(
        path: Routes.messages,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MessagesScreen(),
        routes: <RouteBase>[
          // Declared before `:conversationId` so the literal wins the match.
          GoRoute(
            path: 'new-group',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const NewGroupScreen(),
          ),
          GoRoute(
            path: ':conversationId',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => ConversationScreen(
              conversationId: state.pathParameters['conversationId'] ?? '',
            ),
            routes: <RouteBase>[
              GoRoute(
                path: 'info',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) => GroupInfoScreen(
                  conversationId: state.pathParameters['conversationId'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/call/:callId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            CallScreen(callId: state.pathParameters['callId'] ?? ''),
      ),

      // ── settings ─────────────────────────────────────────────────────
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'privacy',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const PrivacySettingsScreen(),
          ),
          GoRoute(
            path: 'blocked',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const BlockedUsersScreen(),
          ),
          GoRoute(
            path: 'appearance',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => const AppearanceSettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteNotFound(location: state.uri.toString()),
  );
}, name: 'router');

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => KScaffold(
    body: KEmptyState(
      title: 'That link goes nowhere',
      message: '$location does not exist — or is no longer visible to you.',
      icon: Icons.link_off_rounded,
      actionLabel: 'Back to Surf',
      onAction: () => GoRouter.of(context).go(Routes.surf),
    ),
  );
}
