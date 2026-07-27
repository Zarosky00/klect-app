import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/interaction_feedback.dart';
import '../../core/interactions/interactions.dart';
import '../../core/supabase.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'profile_queries.dart';

/// The follow control, wired to the optimistic engine.
///
/// `toggle_follow` returns the **target's** follower count, so every follow
/// button on screen — header, match card, search row, follower list — moves to
/// the same number the instant the finger lifts, and reconciles with the RPC.
///
/// Follow state is seeded from [myFollowingIdsProvider]: one query for the
/// whole session rather than a `has_followed` round trip per button.
class FollowButton extends ConsumerStatefulWidget {
  /// Creates a follow button for [userId].
  const FollowButton({
    required this.userId,
    required this.displayName,
    super.key,
    this.avatarPath,
    this.followerCount = 0,
    this.initiallyFollowing,
    this.size = KButtonSize.medium,
    this.expand = false,
  });

  /// Whose follow state this controls.
  final String userId;

  /// Human-readable target used by contextual outcome toasts.
  final String displayName;

  /// Avatar storage path used by the global follow outcome panel.
  final String? avatarPath;

  /// The target's follower count as the caller last saw it — used to seed the
  /// optimistic delta so the first tap does not jump from zero.
  final int followerCount;

  /// Authoritative follow state when the caller already fetched it.
  final bool? initiallyFollowing;

  /// Button size ramp.
  final KButtonSize size;

  /// Stretch to the parent's width.
  final bool expand;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confirmation;

  @override
  void initState() {
    super.initState();
    _confirmation = AnimationController(
      vsync: this,
      duration: KDurations.slow,
      value: 1,
    );
    final explicit = widget.initiallyFollowing;
    if (explicit != null) {
      _hydrateFollowing(explicit);
    } else {
      final cached = ref.read(myFollowingIdsProvider).value;
      if (cached != null) _hydrate(cached);
    }
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId ||
        widget.followerCount != oldWidget.followerCount ||
        widget.initiallyFollowing != oldWidget.initiallyFollowing) {
      final explicit = widget.initiallyFollowing;
      if (explicit != null) {
        _hydrateFollowing(explicit);
      } else {
        final cached = ref.read(myFollowingIdsProvider).value;
        if (cached != null) _hydrate(cached);
      }
    }
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  void _hydrate(Set<String> followingIds) {
    _hydrateFollowing(followingIds.contains(widget.userId));
  }

  void _hydrateFollowing(bool following) {
    ref
        .read(followProvider(widget.userId).notifier)
        .hydrate(following: following, followerCount: widget.followerCount);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Set<String>>>(myFollowingIdsProvider, (
      previous,
      next,
    ) {
      final ids = next.value;
      if (ids != null && widget.initiallyFollowing == null) _hydrate(ids);
    });

    ref.listen<InteractionFeedbackEvent?>(interactionFeedbackProvider, (
      previous,
      next,
    ) {
      if (next?.action == InteractionFeedbackAction.follow &&
          next?.targetKey == widget.userId &&
          next?.result == InteractionFeedbackResult.confirmed &&
          !KMotion.reduced(context)) {
        _confirmation.forward(from: 0);
      }
    });

    final signedIn = ref.watch(isSignedInProvider);
    final state = ref.watch(followProvider(widget.userId));
    final colors = context.kc;

    final button = KButton(
      label: state.following ? 'Following' : 'Follow',
      icon: state.following ? Icons.check_rounded : Icons.add_rounded,
      size: widget.size,
      expand: widget.expand,
      animateChanges: true,
      variant: state.following
          ? KButtonVariant.secondary
          : KButtonVariant.primary,
      semanticLabel: state.following
          ? 'Following, tap to unfollow'
          : 'Follow this collector',
      onPressed: signedIn
          ? () => ref
                .read(followProvider(widget.userId).notifier)
                .toggle(
                  targetLabel: widget.displayName,
                  targetAvatarPath: widget.avatarPath,
                )
          : null,
    );

    return AnimatedBuilder(
      animation: _confirmation,
      child: button,
      builder: (context, child) {
        final glow = 1 - Curves.easeOut.transform(_confirmation.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: glow <= 0
                ? const <BoxShadow>[]
                : <BoxShadow>[
                    BoxShadow(
                      color: colors.accentRing.withValues(
                        alpha: colors.accentRing.a * glow,
                      ),
                      blurRadius: Space.s5 * glow,
                      spreadRadius: Space.s1 * glow,
                    ),
                  ],
          ),
          child: child,
        );
      },
    );
  }
}
