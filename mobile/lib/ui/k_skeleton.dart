import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../design/motion.dart';
import '../design/theme.dart';

/// A shimmering placeholder block.
///
/// Skeletons must match the real layout's shape exactly, or the swap-in
/// flashes. Loading is never a centred spinner on a full page.
class KSkeleton extends StatelessWidget {
  /// Creates a skeleton block.
  const KSkeleton({
    super.key,
    this.width,
    this.height = Space.s4,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  /// A circular skeleton, e.g. an avatar placeholder.
  const KSkeleton.circle({Key? key, required double size})
      : this(key: key, width: size, height: size, shape: BoxShape.circle);

  /// A line of text, sized from the type ramp.
  const KSkeleton.text({Key? key, double? width, double height = Space.s3})
      : this(key: key, width: width, height: height);

  /// Explicit width. Null fills the parent.
  final double? width;

  /// Explicit height.
  final double height;

  /// Corner rounding for rectangles.
  final BorderRadius? borderRadius;

  /// Rectangle or circle.
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.skeletonBase,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : borderRadius ??
                const BorderRadius.all(Radius.circular(Radii.sm)),
      ),
    );
  }
}

/// Wraps a tree of [KSkeleton]s in the shimmer sweep.
///
/// Under reduced motion the sweep is dropped and the base colour stays —
/// still obviously a placeholder, without the movement.
class KShimmer extends StatelessWidget {
  /// Wraps [child].
  const KShimmer({required this.child, super.key, this.enabled = true});

  /// The skeleton tree.
  final Widget child;

  /// Set false once real content arrives.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    if (!enabled || KMotion.reduced(context)) return child;
    return Shimmer.fromColors(
      baseColor: colors.skeletonBase,
      highlightColor: colors.skeletonShimmer,
      period: KDurations.deliberate * 3,
      child: child,
    );
  }
}

/// The masonry placeholder: staggered tiles in the real column count.
class KSkeletonGrid extends StatelessWidget {
  /// Creates a grid of skeleton tiles.
  const KSkeletonGrid({super.key, this.tiles = 8});

  /// How many tiles to draw.
  final int tiles;

  @override
  Widget build(BuildContext context) {
    final columns = Layout.masonryColumns(MediaQuery.sizeOf(context).width);
    // Three heights, cycled, so the placeholder has the same ragged rhythm as
    // a real masonry page.
    const ratios = <double>[Aspect.gridMin, Aspect.cover, Aspect.gridMax];
    return KShimmer(
      child: Padding(
        padding: const EdgeInsets.all(Layout.masonryGutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var column = 0; column < columns; column++) ...<Widget>[
              if (column > 0) const SizedBox(width: Layout.masonryGutter),
              Expanded(
                child: Column(
                  children: <Widget>[
                    for (var index = column; index < tiles; index += columns)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: Layout.masonryGutter),
                        child: AspectRatio(
                          aspectRatio: ratios[index % ratios.length],
                          child: const KSkeleton(
                            borderRadius:
                                BorderRadius.all(Radius.circular(Radii.lg)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Pulse placeholder: avatar + two text lines + a media block.
class KSkeletonList extends StatelessWidget {
  /// Creates a list of skeleton rows.
  const KSkeletonList({super.key, this.rows = 5, this.showMedia = true});

  /// How many rows.
  final int rows;

  /// Whether each row includes a media block.
  final bool showMedia;

  @override
  Widget build(BuildContext context) => KShimmer(
        child: Column(
          children: <Widget>[
            for (var index = 0; index < rows; index++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const KSkeleton.circle(size: Space.s10),
                    const SizedBox(width: Space.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const KSkeleton.text(width: Space.s24),
                          const SizedBox(height: Space.s2),
                          const KSkeleton.text(),
                          const SizedBox(height: Space.s2),
                          const KSkeleton.text(width: Space.s20),
                          if (showMedia) ...<Widget>[
                            const SizedBox(height: Space.s3),
                            const AspectRatio(
                              aspectRatio: Aspect.gridMax,
                              child: KSkeleton(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(Radii.lg),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
