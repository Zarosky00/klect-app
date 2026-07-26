import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interactions/interactions.dart';
import '../../core/supabase.dart';
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
    super.key,
    this.followerCount = 0,
    this.size = KButtonSize.medium,
    this.expand = false,
  });

  /// Whose follow state this controls.
  final String userId;

  /// The target's follower count as the caller last saw it — used to seed the
  /// optimistic delta so the first tap does not jump from zero.
  final int followerCount;

  /// Button size ramp.
  final KButtonSize size;

  /// Stretch to the parent's width.
  final bool expand;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  @override
  void initState() {
    super.initState();
    // Seed synchronously when the following set is already cached, so the
    // button never renders "Follow" for somebody the viewer already follows.
    final cached = ref.read(myFollowingIdsProvider).value;
    if (cached != null) _hydrate(cached);
  }

  void _hydrate(Set<String> followingIds) {
    ref.read(followProvider(widget.userId).notifier).hydrate(
          following: followingIds.contains(widget.userId),
          followerCount: widget.followerCount,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Set<String>>>(myFollowingIdsProvider,
        (previous, next) {
      final ids = next.value;
      if (ids != null) _hydrate(ids);
    });

    ref.listen<FollowState>(followProvider(widget.userId), (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        KToast.error(context, error.message);
      }
    });

    final signedIn = ref.watch(isSignedInProvider);
    final state = ref.watch(followProvider(widget.userId));

    return KButton(
      label: state.following ? 'Following' : 'Follow',
      icon: state.following ? Icons.check_rounded : Icons.add_rounded,
      size: widget.size,
      expand: widget.expand,
      variant: state.following
          ? KButtonVariant.secondary
          : KButtonVariant.primary,
      semanticLabel: state.following
          ? 'Following, tap to unfollow'
          : 'Follow this collector',
      onPressed: signedIn
          ? ref.read(followProvider(widget.userId).notifier).toggle
          : null,
    );
  }
}
