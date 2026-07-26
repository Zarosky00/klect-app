import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/theme.dart';

/// Kept for `setUpAll(useOfflineFonts)` call sites: fonts are now bundled
/// variable TTFs (pubspec `fonts:`), so typography is always offline and this
/// is a no-op. New tests do not need to call it.
void useOfflineFonts() {}

/// Pumps [child] inside a real KLECT theme and a Riverpod scope.
///
/// Use it for any widget that reads `context.kc` / `context.kt`.
/// Pass [container] to inject fakes; build it with
/// `ProviderContainer.test(overrides: [...])`.
Future<void> pumpKlect(
  WidgetTester tester,
  Widget child, {
  ProviderContainer? container,
  ThemeMode themeMode = ThemeMode.dark,
  bool disableAnimations = false,
}) async {
  final app = _KlectTestApp(
    themeMode: themeMode,
    disableAnimations: disableAnimations,
    child: child,
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
}

class _KlectTestApp extends StatelessWidget {
  const _KlectTestApp({
    required this.child,
    required this.themeMode,
    required this.disableAnimations,
  });

  final Widget child;
  final ThemeMode themeMode;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: KlectThemeData.light(),
      darkTheme: KlectThemeData.dark(),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }
}
