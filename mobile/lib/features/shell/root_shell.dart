import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';

/// Unread notification count, for the tab badge.
final unreadNotificationCountProvider = FutureProvider<int>(
  (ref) async {
    if (ref.watch(currentUserIdProvider) == null) return 0;
    return ref.watch(klectApiProvider).fetchUnreadNotificationCount();
  },
  name: 'unreadNotificationCount',
);

/// The five-tab shell: surf · pulse · create · notifications · profile.
///
/// Each tab keeps its own navigation stack, so switching away and back returns
/// you exactly where you were.
class RootShell extends ConsumerWidget {
  /// Wraps the branch navigator produced by `StatefulShellRoute`.
  const RootShell({required this.navigationShell, super.key});

  /// The branch navigator go_router hands us.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;

    return Scaffold(
      backgroundColor: colors.bgBase,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceGlass,
              border: Border(
                top: BorderSide(
                  color: colors.borderSubtle,
                  width: Strokes.hairline,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: Layout.bottomBarHeight,
                child: Row(
                  children: <Widget>[
                    _Tab(
                      index: 0,
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_rounded,
                      label: 'Surf',
                      shell: navigationShell,
                    ),
                    _Tab(
                      index: 1,
                      icon: Icons.bolt_outlined,
                      activeIcon: Icons.bolt_rounded,
                      label: 'Pulse',
                      shell: navigationShell,
                    ),
                    _Tab(
                      index: 2,
                      icon: Icons.add_box_outlined,
                      activeIcon: Icons.add_box_rounded,
                      label: 'Create',
                      shell: navigationShell,
                    ),
                    _Tab(
                      index: 3,
                      icon: Icons.notifications_none_rounded,
                      activeIcon: Icons.notifications_rounded,
                      label: 'Alerts',
                      badge: unread,
                      shell: navigationShell,
                    ),
                    _Tab(
                      index: 4,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'You',
                      shell: navigationShell,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.shell,
    this.badge = 0,
  });

  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final StatefulNavigationShell shell;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final selected = shell.currentIndex == index;
    final tint = selected ? colors.textPrimary : colors.textTertiary;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: badge > 0 ? '$label, $badge unread' : label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // `initialLocation: true` on a re-tap pops that branch to its root,
          // which is the behaviour people expect from a tab bar.
          onTap: () => shell.goBranch(index, initialLocation: selected),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AnimatedScale(
                    scale: selected ? 1 : KMotion.pressScale,
                    duration: KMotion.duration(context, KDurations.fast),
                    curve: Curves_.emphasized,
                    child: Icon(
                      selected ? activeIcon : icon,
                      size: Space.s6,
                      color: tint,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -Space.s15,
                      top: -Space.s1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s1,
                          vertical: Space.s05,
                        ),
                        constraints: const BoxConstraints(minWidth: Space.s4),
                        decoration: BoxDecoration(
                          color: colors.actionLike,
                          borderRadius: BorderRadius.circular(Radii.full),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: context.kt.micro
                              .copyWith(color: colors.textInverse),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.s05),
              Text(label, style: context.kt.micro.copyWith(color: tint)),
            ],
          ),
        ),
      ),
    );
  }
}
