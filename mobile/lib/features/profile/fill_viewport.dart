import 'package:flutter/material.dart';

/// Makes a non-scrolling state — an empty state, an error state, a skeleton —
/// fill the viewport, scroll when it does not fit, and still respond to
/// pull-to-refresh.
///
/// Three problems, one wrapper:
///  * `KEmptyState` centres itself, so it needs a box at least as tall as the
///    viewport or it collapses to its content;
///  * `KSkeletonList` is a plain `Column`, which overflows on a short screen;
///  * `RefreshIndicator` needs a scrollable descendant that always accepts a
///    drag, which `AlwaysScrollableScrollPhysics` guarantees.
class FillViewport extends StatelessWidget {
  /// Wraps [child].
  const FillViewport({required this.child, super.key});

  /// The state to show.
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      );
}
