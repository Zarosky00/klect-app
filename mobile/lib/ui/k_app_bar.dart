import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_button.dart';

/// The collapsing app bar.
///
/// Large display-serif title at rest; as the user scrolls it shrinks into the
/// compact UI title. Chrome sits on `surface.glass` with a blur so photography
/// stays visible behind it.
///
/// Use inside a `CustomScrollView`. For a screen that does not scroll, use
/// [KFixedAppBar].
class KAppBar extends StatelessWidget {
  /// Creates a collapsing app bar.
  const KAppBar({
    required this.title,
    super.key,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
    this.expandedHeight = Space.s24,
    this.pinned = true,
    this.floating = false,
    this.bottom,
    this.background,
    this.centerTitle = false,
  });

  /// The screen name.
  final String title;

  /// Optional second line, shown only while expanded.
  final String? subtitle;

  /// Trailing controls.
  final List<Widget> actions;

  /// Leading control. Defaults to the platform back button when one is needed.
  final Widget? leading;

  /// Height at rest.
  final double expandedHeight;

  /// Stays on screen when collapsed.
  final bool pinned;

  /// Reappears on an upward scroll.
  final bool floating;

  /// A tab bar or filter row pinned under the title.
  final PreferredSizeWidget? bottom;

  /// A photo or gradient behind the expanded bar.
  final Widget? background;

  /// Centre the collapsed title.
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;

    return SliverAppBar(
      pinned: pinned,
      floating: floating,
      stretch: true,
      expandedHeight: expandedHeight,
      collapsedHeight: Layout.topBarHeight,
      toolbarHeight: Layout.topBarHeight,
      backgroundColor: colors.surfaceGlass,
      surfaceTintColor: Colors.transparent,
      elevation: Elevation.none.y,
      scrolledUnderElevation: Elevation.none.y,
      centerTitle: centerTitle,
      leading: leading,
      actions: <Widget>[
        ...actions,
        const SizedBox(width: Space.s2),
      ],
      bottom: bottom,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
          child: FlexibleSpaceBar(
            titlePadding: EdgeInsets.only(
              left: centerTitle ? 0 : Space.s4,
              right: Space.s4,
              // The flexible space extends behind [bottom], so the title has
              // to clear its band or it renders underneath the filter row.
              bottom: Space.s3 + (bottom?.preferredSize.height ?? 0),
            ),
            centerTitle: centerTitle,
            // Derived from the type ramp, not invented: expanded reads as
            // display2, collapsed settles back to display3.
            expandedTitleScale:
                TypeScale.display2.size / TypeScale.display3.size,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: centerTitle
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.display3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  _ExpandedSubtitle(
                    subtitle: subtitle!,
                    centerTitle: centerTitle,
                  ),
              ],
            ),
            background: background,
          ),
        ),
      ),
    );
  }
}

/// The second line under a [KAppBar] title, alive only while expanded.
///
/// Fades *and* collapses with scroll progress — the fade keeps a slow scroll
/// from snapping, and giving the space back is what lets the shrunken title
/// sit centred in the toolbar instead of being pushed off its top edge.
class _ExpandedSubtitle extends StatelessWidget {
  const _ExpandedSubtitle({
    required this.subtitle,
    required this.centerTitle,
  });

  final String subtitle;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final extent =
        settings == null ? 0.0 : (settings.maxExtent - settings.minExtent);
    // 1 at rest, 0 once the bar has fully collapsed — the exact inverse of
    // the profile screen's collapsed title.
    final expanded = settings == null || extent <= 0
        ? 1.0
        : ((settings.currentExtent - settings.minExtent) / extent)
            .clamp(0.0, 1.0);

    return ClipRect(
      child: Align(
        alignment: centerTitle ? Alignment.topCenter : Alignment.topLeft,
        heightFactor: expanded,
        child: Opacity(
          opacity: expanded,
          child: Text(
            subtitle,
            style: context.kt.caption.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// A fixed-height top bar for screens that do not scroll under their chrome.
class KFixedAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a fixed app bar.
  const KFixedAppBar({
    super.key,
    this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.showBack = false,
    this.onBack,
    this.transparent = false,
    this.centerTitle = false,
    this.titleWidget,
  });

  /// The screen name.
  final String? title;

  /// A widget in place of the title, e.g. a search field.
  final Widget? titleWidget;

  /// Trailing controls.
  final List<Widget> actions;

  /// Leading control.
  final Widget? leading;

  /// Draws a back chevron.
  final bool showBack;

  /// Back handler; defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Renders over content with no fill.
  final bool transparent;

  /// Centre the title.
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(Layout.topBarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return AppBar(
      backgroundColor: transparent ? Colors.transparent : colors.bgBase,
      surfaceTintColor: Colors.transparent,
      elevation: Elevation.none.y,
      scrolledUnderElevation: Elevation.none.y,
      centerTitle: centerTitle,
      toolbarHeight: Layout.topBarHeight,
      automaticallyImplyLeading: false,
      leading: leading ??
          (showBack
              ? KIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  color: colors.textPrimary,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                )
              : null),
      title: titleWidget ??
          (title == null
              ? null
              : Text(title!, style: context.kt.title2)),
      actions: <Widget>[
        ...actions,
        const SizedBox(width: Space.s2),
      ],
    );
  }
}
