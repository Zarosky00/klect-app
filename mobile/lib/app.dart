import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/feedback/interaction_feedback.dart';
import 'core/offline/action_queue.dart';
import 'core/settings/app_settings.dart';
import 'core/supabase.dart';
import 'design/theme.dart';
import 'router.dart';
import 'ui/ui.dart';

/// The application root.
///
/// Owns three things and nothing else: the theme, the router, and the
/// lifecycle hooks that drain the offline queue when we come back to life.
class KlectApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const KlectApp({super.key});

  @override
  ConsumerState<KlectApp> createState() => _KlectAppState();
}

class _KlectAppState extends ConsumerState<KlectApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Anything queued while offline (or before the app was killed) replays now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(offlineQueueProvider).flush());
      unawaited(ref.read(interactionFeedbackProvider.notifier).preload());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(offlineQueueProvider).flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // A fresh session means a fresh queue drain — we may have come back from
    // a long offline stretch.
    ref.listen(sessionProvider, (previous, next) {
      if (next != null) {
        unawaited(ref.read(offlineQueueProvider).flush());
      }
    });

    return MaterialApp.router(
      title: 'KLECT',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: KlectThemeData.light(),
      darkTheme: KlectThemeData.dark(),
      themeMode: themeMode,
      builder: (context, child) =>
          KInteractionFeedbackHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
