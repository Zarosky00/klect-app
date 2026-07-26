import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../design/theme.dart';

/// A **real** masonry sliver: variable tile heights, shortest-column packing,
/// lazy building, and no reflow ever.
///
/// The tile box is derived from the feed's intrinsic `width`/`height` *before*
/// the photo loads (`docs/DESIGN_SYSTEM.md` §5), so an image arriving late can
/// never move anything that is already on screen.
///
/// It is implemented as a [SliverGrid] with a custom [SliverGridDelegate]
/// rather than as N side-by-side lists, which means it keeps everything a
/// sliver gives you for free: one scroll position, lazy child building,
/// `cacheExtent`, and automatic repaint boundaries per tile.
class KMasonryGrid extends StatelessWidget {
  /// Creates a masonry sliver.
  ///
  /// [aspects] must have exactly one entry per tile — pass
  /// `SurfCard.tileAspect`, which is already clamped into the grid's allowed
  /// band so one pathological photo cannot own a whole column.
  const KMasonryGrid({
    required this.aspects,
    required this.itemBuilder,
    super.key,
    this.columns = 2,
    this.gutter = Layout.masonryGutter,
  });

  /// Width / height of every tile, in order.
  final List<double> aspects;

  /// Builds the tile at an index.
  final NullableIndexedWidgetBuilder itemBuilder;

  /// Column count. Use [Layout.masonryColumns] to derive it from the viewport.
  final int columns;

  /// Space between tiles, both axes.
  final double gutter;

  @override
  Widget build(BuildContext context) => SliverGrid(
        gridDelegate: _MasonryGridDelegate(
          aspects: aspects,
          columns: columns < 1 ? 1 : columns,
          gutter: gutter,
        ),
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: aspects.length,
        ),
      );
}

class _MasonryGridDelegate extends SliverGridDelegate {
  _MasonryGridDelegate({
    required this.aspects,
    required this.columns,
    required this.gutter,
  });

  final List<double> aspects;
  final int columns;
  final double gutter;

  _MasonryGridLayout? _cached;
  double _cachedExtent = double.negativeInfinity;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final cached = _cached;
    if (cached != null && _cachedExtent == constraints.crossAxisExtent) {
      return cached;
    }
    final layout = _MasonryGridLayout.pack(
      aspects: aspects,
      columns: columns,
      gutter: gutter,
      crossAxisExtent: constraints.crossAxisExtent,
    );
    _cached = layout;
    _cachedExtent = constraints.crossAxisExtent;
    return layout;
  }

  @override
  bool shouldRelayout(covariant _MasonryGridDelegate oldDelegate) =>
      oldDelegate.columns != columns ||
      oldDelegate.gutter != gutter ||
      !listEquals(oldDelegate.aspects, aspects);
}

/// The packed geometry, plus two monotone index maps that let the sliver
/// answer "which children intersect this scroll offset?" in O(log n).
class _MasonryGridLayout extends SliverGridLayout {
  const _MasonryGridLayout({
    required this.geometries,
    required this.suffixMinLeading,
    required this.prefixMaxTrailing,
    required this.maxExtent,
  });

  /// Runs shortest-column packing once for a given viewport width.
  factory _MasonryGridLayout.pack({
    required List<double> aspects,
    required int columns,
    required double gutter,
    required double crossAxisExtent,
  }) {
    final count = aspects.length;
    final columnWidth =
        (crossAxisExtent - gutter * (columns - 1)) / columns;
    final safeWidth = columnWidth.isFinite && columnWidth > 0
        ? columnWidth
        : crossAxisExtent;

    final columnTops = List<double>.filled(columns, 0);
    final geometries = <SliverGridGeometry>[];

    for (var index = 0; index < count; index++) {
      var column = 0;
      for (var c = 1; c < columns; c++) {
        if (columnTops[c] < columnTops[column]) column = c;
      }
      final aspect = aspects[index];
      final height =
          aspect > 0 && aspect.isFinite ? safeWidth / aspect : safeWidth;
      geometries.add(
        SliverGridGeometry(
          scrollOffset: columnTops[column],
          crossAxisOffset: column * (safeWidth + gutter),
          mainAxisExtent: height,
          crossAxisExtent: safeWidth,
        ),
      );
      columnTops[column] += height + gutter;
    }

    final suffixMinLeading = List<double>.filled(count, 0);
    final prefixMaxTrailing = List<double>.filled(count, 0);
    for (var index = count - 1; index >= 0; index--) {
      final leading = geometries[index].scrollOffset;
      suffixMinLeading[index] = index == count - 1
          ? leading
          : (leading < suffixMinLeading[index + 1]
              ? leading
              : suffixMinLeading[index + 1]);
    }
    for (var index = 0; index < count; index++) {
      final trailing =
          geometries[index].scrollOffset + geometries[index].mainAxisExtent;
      prefixMaxTrailing[index] = index == 0
          ? trailing
          : (trailing > prefixMaxTrailing[index - 1]
              ? trailing
              : prefixMaxTrailing[index - 1]);
    }

    var maxExtent = 0.0;
    for (final top in columnTops) {
      if (top > maxExtent) maxExtent = top;
    }

    return _MasonryGridLayout(
      geometries: geometries,
      suffixMinLeading: suffixMinLeading,
      prefixMaxTrailing: prefixMaxTrailing,
      maxExtent: maxExtent > 0 ? maxExtent - gutter : 0,
    );
  }

  final List<SliverGridGeometry> geometries;

  /// `min(scrollOffset)` over every child at or after this index — a
  /// non-decreasing sequence, so it is binary-searchable.
  final List<double> suffixMinLeading;

  /// `max(scrollOffset + mainAxisExtent)` over every child up to this index —
  /// also non-decreasing.
  final List<double> prefixMaxTrailing;

  final double maxExtent;

  @override
  double computeMaxScrollOffset(int childCount) =>
      childCount <= 0 ? 0 : maxExtent;

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index < 0 || index >= geometries.length) {
      return const SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent: 0,
        crossAxisExtent: 0,
      );
    }
    return geometries[index];
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    final count = prefixMaxTrailing.length;
    if (count == 0) return 0;
    // First index whose bottom edge is still below the offset; everything
    // before it is entirely above the viewport.
    var low = 0;
    var high = count;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (prefixMaxTrailing[mid] > scrollOffset) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low >= count ? count - 1 : low;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    final count = suffixMinLeading.length;
    if (count == 0) return 0;
    // Last index whose top edge can still be above the offset; everything
    // after it starts below the viewport.
    var low = 0;
    var high = count - 1;
    var answer = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (suffixMinLeading[mid] <= scrollOffset) {
        answer = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return answer;
  }
}
