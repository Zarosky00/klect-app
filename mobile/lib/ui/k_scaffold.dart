import 'package:flutter/material.dart';

import '../design/theme.dart';

/// The screen shell.
///
/// Handles the token background, safe areas, notches and the Android back
/// gesture consistently so no screen has to think about them.
class KScaffold extends StatelessWidget {
  /// Creates a screen shell.
  const KScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.bottomBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.onRefresh,
    this.refreshNotificationPredicate = defaultScrollNotificationPredicate,
    this.refreshEdgeOffset = 0,
    this.safeTop = true,
    this.safeBottom = true,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
    this.onPopInvoked,
    this.canPop = true,
  });

  /// Screen content.
  final Widget body;

  /// Fixed top bar. Use a `CustomScrollView` + `KAppBar` for a collapsing one.
  final PreferredSizeWidget? appBar;

  /// Bottom navigation or a composer.
  final Widget? bottomBar;

  /// Floating action button.
  final Widget? floatingActionButton;

  /// Overrides `bg.base`.
  final Color? backgroundColor;

  /// Enables pull-to-refresh over [body].
  final Future<void> Function()? onRefresh;

  /// Which scroll notifications may drive pull-to-refresh.
  ///
  /// The default only listens to the outermost scrollable. A body whose
  /// scrolling list sits deeper (a `NestedScrollView` over a pager) must widen
  /// this, or the pull never reaches the indicator.
  final ScrollNotificationPredicate refreshNotificationPredicate;

  /// Where the refresh indicator emerges from, measured from the body's top.
  final double refreshEdgeOffset;

  /// Inset for the status bar.
  final bool safeTop;

  /// Inset for the home indicator.
  final bool safeBottom;

  /// Lets content run under a transparent app bar.
  final bool extendBodyBehindAppBar;

  /// Whether the keyboard resizes the body.
  final bool resizeToAvoidBottomInset;

  /// Back-gesture interception, e.g. "discard this draft?".
  final void Function(bool didPop, Object? result)? onPopInvoked;

  /// Whether the route may pop.
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;

    var content = body;
    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        notificationPredicate: refreshNotificationPredicate,
        edgeOffset: refreshEdgeOffset,
        color: colors.accentDefault,
        backgroundColor: colors.surface2,
        displacement: Space.s10,
        child: content,
      );
    }

    content = SafeArea(
      top: safeTop && appBar == null,
      bottom: safeBottom && bottomBar == null,
      child: content,
    );

    final scaffold = Scaffold(
      backgroundColor: backgroundColor ?? colors.bgBase,
      appBar: appBar,
      body: content,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );

    if (onPopInvoked == null && canPop) return scaffold;
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: onPopInvoked,
      child: scaffold,
    );
  }
}
