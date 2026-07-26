import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';

/// Shown while the session is restored and the profile is fetched.
///
/// The router redirects away the moment it knows where the user belongs, so
/// this is deliberately quiet — a wordmark, not a spinner-on-a-page.
class SplashScreen extends ConsumerWidget {
  /// Creates the splash screen.
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    return KScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('KLECT', style: context.kt.display1),
            const SizedBox(height: Space.s3),
            Text(
              'Collections, not posts.',
              style: context.kt.callout.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: Space.s10),
            SizedBox(
              width: Space.s16,
              child: LinearProgressIndicator(
                minHeight: Strokes.thick,
                backgroundColor: colors.surface2,
                color: colors.accentDefault,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
