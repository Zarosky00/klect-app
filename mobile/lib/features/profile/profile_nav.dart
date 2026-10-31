import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/feedback/interaction_feedback.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'profile_filters.dart';

/// The two profile navigation designs.
enum ProfileNavStyle {
  /// An icon-first section lens pinned under the header, plus a glass filter
  /// shelf that tucks away while you read and comes back when you scroll up.
  dock,

  /// The v1.7.0 design: an underlined Surf | Pulse | Activity tab bar with
  /// rows of chips at the top of each tab.
  classic,
}

/// **The one switch for the profile navigation design.**
///
/// Set this to [ProfileNavStyle.classic] to bring back the v1.7.0 tab bar and
/// chip rows exactly as they were. Both designs read the same
/// [ProfileFilters], so nothing else has to change.
const ProfileNavStyle kProfileNavStyle = ProfileNavStyle.dock;

/// Geometry shared by the dock, the filter shelf and the page spacers that
/// keep content clear of the shelf.
abstract final class ProfileDockMetrics {
  /// Height of the pinned section dock.
  static const double dockHeight = Space.s14;

  /// Height of the section lens inside the dock.
  static const double lensHeight = Layout.tapTargetMin;

  /// Space above the shelf's primary row.
  static const double shelfTop = Space.s2;

  /// Height of the primary filter control.
  static const double primaryHeight = Space.s10;

  /// Space between the primary and scope rows.
  static const double scopeGap = Space.s1;

  /// Height of the scope row.
  static const double scopeHeight = Space.s8;

  /// Space below the last row.
  static const double shelfBottom = Space.s2;

  /// How far a tab list must scroll before the shelf may tuck away.
  static const double revealExtent = Space.s24;

  /// Full height of the shelf for [spec].
  static double shelfHeight(ProfileFilterSpec spec) =>
      shelfTop +
      primaryHeight +
      (spec.scope == null ? 0 : scopeGap + scopeHeight) +
      shelfBottom;
}

// ────────────────────────────────────────────────────────────── the dock ──

/// The pinned bar under the profile header: the section lens on the leading
/// edge and, while the filter shelf is tucked away, a chip naming the active
/// filter that brings the shelf back.
class ProfileDockDelegate extends SliverPersistentHeaderDelegate {
  /// Creates the delegate.
  const ProfileDockDelegate({
    required this.sections,
    required this.selectedIndex,
    required this.pageProgress,
    required this.onSelected,
    required this.shelfVisibility,
    required this.filters,
    required this.selectedSpec,
    required this.onShowFilters,
  });

  /// The sections, in pager order.
  final List<ProfileNavOption> sections;

  /// The committed section.
  final int selectedIndex;

  /// The pager's live fractional page.
  final ValueListenable<double> pageProgress;

  /// Called when the user picks a section.
  final ValueChanged<int> onSelected;

  /// 1 while the filter shelf is out, 0 while it is tucked away.
  final Animation<double> shelfVisibility;

  /// The profile's filter state.
  final ValueListenable<ProfileFilters> filters;

  /// The committed section's filters, for the tucked-away chip.
  final ProfileFilterSpec Function(ProfileFilters filters) selectedSpec;

  /// Brings the filter shelf back.
  final VoidCallback onShowFilters;

  @override
  double get minExtent => ProfileDockMetrics.dockHeight;

  @override
  double get maxExtent => ProfileDockMetrics.dockHeight;

  @override
  bool shouldRebuild(covariant ProfileDockDelegate oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.sections.length != sections.length ||
      oldDelegate.pageProgress != pageProgress ||
      oldDelegate.shelfVisibility != shelfVisibility ||
      oldDelegate.filters != filters ||
      oldDelegate.onSelected != onSelected ||
      oldDelegate.selectedSpec != selectedSpec;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.kc;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
        child: AnimatedBuilder(
          animation: shelfVisibility,
          builder: (context, lens) {
            final tucked = (1 - shelfVisibility.value).clamp(0.0, 1.0);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceGlass,
                border: Border(
                  bottom: BorderSide(
                    // The shelf carries the edge while it is out, so the dock
                    // and shelf read as one slab of glass.
                    color: colors.borderSubtle.withValues(
                      alpha: colors.borderSubtle.a * tucked,
                    ),
                    width: Strokes.hairline,
                  ),
                ),
              ),
              child: SizedBox(
                height: ProfileDockMetrics.dockHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: lens,
                          ),
                        ),
                      ),
                      ClipRect(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          widthFactor: tucked,
                          child: IgnorePointer(
                            ignoring: tucked < 0.5,
                            child: Opacity(
                              opacity: tucked,
                              child: ValueListenableBuilder<ProfileFilters>(
                                valueListenable: filters,
                                builder: (context, value, _) =>
                                    _FilterSummaryChip(
                                      spec: selectedSpec(value),
                                      onTap: onShowFilters,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: ProfileSectionLens(
            sections: sections,
            selectedIndex: selectedIndex,
            pageProgress: pageProgress,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }
}

/// The active filter, shown in the dock while the shelf is tucked away.
class _FilterSummaryChip extends StatelessWidget {
  const _FilterSummaryChip({required this.spec, required this.onTap});

  final ProfileFilterSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      semanticLabel: 'Filter: ${spec.summary}. Show filters',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Space.s24 + Space.s12),
        child: Container(
          height: Space.s8,
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(
              color: spec.isDefault ? colors.borderSubtle : colors.accentRing,
              width: Strokes.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                spec.primary.current.activeIcon,
                size: Space.s4,
                color: colors.accentHover,
              ),
              const SizedBox(width: Space.s15),
              Flexible(
                child: Text(
                  spec.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.kt.label.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: Space.s05),
              Icon(
                Icons.expand_more_rounded,
                size: Space.s4,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── section lens ──

/// The section switcher: one glass track, an icon per section, and an accent
/// lens that carries the active section's name.
///
/// Resting sections show only their icon. The lens follows the pager's live
/// page, so a swipe folds the old section's name away while the next one
/// unfolds. The lens can also be dragged along the track and lands on the
/// nearest section when released.
class ProfileSectionLens extends StatefulWidget {
  /// Creates the lens.
  const ProfileSectionLens({
    required this.sections,
    required this.selectedIndex,
    required this.pageProgress,
    required this.onSelected,
    super.key,
  });

  /// The sections, in pager order.
  final List<ProfileNavOption> sections;

  /// The committed section.
  final int selectedIndex;

  /// The pager's live fractional page.
  final ValueListenable<double> pageProgress;

  /// Called when the user picks a section.
  final ValueChanged<int> onSelected;

  @override
  State<ProfileSectionLens> createState() => _ProfileSectionLensState();
}

class _ProfileSectionLensState extends State<ProfileSectionLens>
    with SingleTickerProviderStateMixin {
  static const double _collapsed = Layout.tapTargetMin;
  static const double _inset = Space.s05;
  static const double _icon = Space.s5;
  static const double _gap = Space.s15;
  static const double _pad = Space.s4;

  /// The lens position while a finger drags it and while it lands.
  late final AnimationController _scrub = AnimationController.unbounded(
    vsync: this,
  );
  bool _scrubbing = false;
  List<double> _dragStarts = const <double>[];
  List<double> _dragWidths = const <double>[];

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

  static double _expansion(double position, int index) =>
      (1 - (position - index).abs()).clamp(0.0, 1.0);

  static List<double> _widthsAt(double position, List<double> expanded) =>
      <double>[
        for (var i = 0; i < expanded.length; i++)
          _collapsed + _expansion(position, i) * (expanded[i] - _collapsed),
      ];

  List<double> _expandedWidths(BuildContext context, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return <double>[
      for (final section in widget.sections)
        _measure(section.label, style, scaler, direction),
    ];
  }

  static double _measure(
    String label,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = _pad * 2 + _icon + _gap + painter.width;
    painter.dispose();
    return math.max(width, _collapsed);
  }

  /// Converts a finger position along the track into a section position,
  /// using the geometry the track had when the drag began.
  double _positionAt(double dx) {
    final total = _dragWidths.fold<double>(0, (sum, w) => sum + w);
    var x = dx - _inset;
    if (Directionality.of(context) == TextDirection.rtl) {
      final width = (context.size?.width ?? total + _inset * 2) - _inset * 2;
      x = width - x;
    }
    final last = _dragWidths.length - 1;
    for (var i = 0; i <= last; i++) {
      if (x < _dragStarts[i] + _dragWidths[i] || i == last) {
        final within = (x - _dragStarts[i]) / _dragWidths[i];
        return (i + within - 0.5).clamp(0.0, last.toDouble());
      }
    }
    return widget.selectedIndex.toDouble();
  }

  void _onDragStart(DragStartDetails details, List<double> expanded) {
    _dragWidths = _widthsAt(widget.selectedIndex.toDouble(), expanded);
    var start = 0.0;
    _dragStarts = <double>[
      for (final width in _dragWidths) (start += width) - width,
    ];
    _scrub.stop();
    _scrubbing = true;
    _scrub.value = _positionAt(details.localPosition.dx);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_scrubbing) return;
    _scrub.value = _positionAt(details.localPosition.dx);
  }

  void _onDragEnd() {
    if (!_scrubbing) return;
    final target = _scrub.value.round().clamp(0, widget.sections.length - 1);
    if (target != widget.selectedIndex) {
      triggerInteractionTapFeedback(context);
      widget.onSelected(target);
    }
    // The pager animates to the same section on the same curve, so handing
    // the lens back to the live page afterwards is seamless.
    _scrub
        .animateTo(
          target.toDouble(),
          duration: KMotion.duration(context, KDurations.medium),
          curve: KMotion.curve(context, KCurves.emphasized),
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          setState(() => _scrubbing = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final labelStyle = context.kt.label.copyWith(fontWeight: FontWeight.w600);
    final expanded = _expandedWidths(context, labelStyle);
    final last = widget.sections.length - 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) => _onDragStart(details, expanded),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _onDragEnd(),
      onHorizontalDragCancel: _onDragEnd,
      child: Container(
        height: ProfileDockMetrics.lensHeight,
        padding: const EdgeInsets.all(_inset),
        decoration: BoxDecoration(
          color: colors.bgSunken.withValues(alpha: Opacities.veil),
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            widget.pageProgress,
            _scrub,
          ]),
          builder: (context, _) {
            final position =
                (_scrubbing ? _scrub.value : widget.pageProgress.value).clamp(
                  0.0,
                  last.toDouble(),
                );
            final widths = _widthsAt(position, expanded);
            final starts = <double>[];
            var cursor = 0.0;
            for (final width in widths) {
              starts.add(cursor);
              cursor += width;
            }
            final from = position.floor().clamp(0, last);
            final to = (from + 1).clamp(0, last);
            final t = position - from;
            final lensStart = lerpDouble(starts[from], starts[to], t)!;
            final lensWidth = lerpDouble(widths[from], widths[to], t)!;

            return SizedBox(
              width: cursor,
              height: ProfileDockMetrics.lensHeight - _inset * 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  PositionedDirectional(
                    start: lensStart,
                    top: 0,
                    bottom: 0,
                    width: lensWidth,
                    child: const _AccentLens(),
                  ),
                  Row(
                    children: <Widget>[
                      for (var i = 0; i <= last; i++)
                        _SectionSegment(
                          option: widget.sections[i],
                          width: widths[i],
                          expansion: _expansion(position, i),
                          selected: i == widget.selectedIndex,
                          labelStyle: labelStyle,
                          onTap: () {
                            if (i != widget.selectedIndex) widget.onSelected(i);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The accent capsule under the active section: flat brand fill, a soft brand
/// glow, and a hairline specular rim with a faint top sheen.
class _AccentLens extends StatelessWidget {
  const _AccentLens();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final sheen = colors.textOnAccent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentDefault,
        borderRadius: BorderRadius.circular(Radii.full),
        boxShadow: KlectTheme.shadow(Elevation.glow),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(
            color: sheen.withValues(alpha: Opacities.ghost),
            width: Strokes.hairline,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              sheen.withValues(alpha: Opacities.ghost),
              sheen.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionSegment extends StatelessWidget {
  const _SectionSegment({
    required this.option,
    required this.width,
    required this.expansion,
    required this.selected,
    required this.labelStyle,
    required this.onTap,
  });

  final ProfileNavOption option;
  final double width;
  final double expansion;
  final bool selected;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final foreground = Color.lerp(
      colors.textTertiary,
      colors.textOnAccent,
      expansion,
    )!;
    // The name fades in late and out early, so it never smears across the
    // lens while the capsule is still growing.
    final labelAlpha = Curves_.accelerate.transform(expansion);

    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: option.label,
      excludeSemantics: true,
      child: KPressable(
        onTap: onTap,
        enforceMinTapTarget: false,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    expansion >= 0.5 ? option.activeIcon : option.icon,
                    size: _ProfileSectionLensState._icon,
                    color: foreground,
                  ),
                  ClipRect(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: expansion,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: _ProfileSectionLensState._gap,
                        ),
                        child: Text(
                          option.label,
                          maxLines: 1,
                          softWrap: false,
                          style: labelStyle.copyWith(
                            color: colors.textOnAccent.withValues(
                              alpha: labelAlpha,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── filter shelf ──

/// The glass filter shelf that hangs under the dock.
///
/// It shows the filters of whichever section the pager is on, cross-fading
/// between sections as the user swipes. Its height follows the page too, and
/// eases when a choice adds or removes the scope row. [visibility] slides it
/// up under the dock while the user reads and back down when they scroll up.
class ProfileFilterShelf extends StatefulWidget {
  /// Creates the shelf.
  const ProfileFilterShelf({
    required this.sectionCount,
    required this.specFor,
    required this.filters,
    required this.pageProgress,
    required this.visibility,
    super.key,
  });

  /// How many sections the pager has.
  final int sectionCount;

  /// The filters of section `index` for the given state.
  final ProfileFilterSpec Function(int index, ProfileFilters filters) specFor;

  /// The profile's filter state.
  final ValueListenable<ProfileFilters> filters;

  /// The pager's live fractional page.
  final ValueListenable<double> pageProgress;

  /// 1 while out, 0 while tucked away under the dock.
  final Animation<double> visibility;

  @override
  State<ProfileFilterShelf> createState() => _ProfileFilterShelfState();
}

class _ProfileFilterShelfState extends State<ProfileFilterShelf>
    with SingleTickerProviderStateMixin {
  late final AnimationController _resize = AnimationController(
    vsync: this,
    value: 1,
  );

  /// Per-section heights the shelf is easing from and to. Swipes between
  /// sections stay finger-exact because the page blend sits on top of these;
  /// only a scope row coming or going eases.
  late List<double> _from = _targets();
  late List<double> _to = _from;

  @override
  void initState() {
    super.initState();
    widget.filters.addListener(_onFiltersChanged);
  }

  @override
  void didUpdateWidget(covariant ProfileFilterShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      oldWidget.filters.removeListener(_onFiltersChanged);
      widget.filters.addListener(_onFiltersChanged);
    }
    if (oldWidget.sectionCount != widget.sectionCount) {
      _from = _targets();
      _to = _from;
      _resize.value = 1;
    }
  }

  @override
  void dispose() {
    widget.filters.removeListener(_onFiltersChanged);
    _resize.dispose();
    super.dispose();
  }

  List<double> _targets() => <double>[
    for (var i = 0; i < widget.sectionCount; i++)
      ProfileDockMetrics.shelfHeight(widget.specFor(i, widget.filters.value)),
  ];

  void _onFiltersChanged() {
    final targets = _targets();
    if (_listEquals(targets, _to)) return;
    _from = _current();
    _to = targets;
    _resize
      ..duration = KMotion.duration(context, KDurations.base)
      ..forward(from: 0);
  }

  List<double> _current() {
    final t = KMotion.curve(
      context,
      KCurves.emphasized,
    ).transform(_resize.value.clamp(0.0, 1.0));
    return <double>[
      for (var i = 0; i < _to.length; i++) lerpDouble(_from[i], _to[i], t)!,
    ];
  }

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return AnimatedBuilder(
      animation: widget.visibility,
      builder: (context, shelf) {
        final shown = widget.visibility.value.clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: shown < 0.5,
          child: ClipRect(
            child: Align(
              // Tucking away slides the shelf up under the dock.
              alignment: Alignment.bottomCenter,
              heightFactor: shown,
              child: shelf,
            ),
          ),
        );
      },
      child: ValueListenableBuilder<ProfileFilters>(
        valueListenable: widget.filters,
        builder: (context, filters, _) {
          final specs = <ProfileFilterSpec>[
            for (var i = 0; i < widget.sectionCount; i++)
              widget.specFor(i, filters),
          ];
          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              widget.pageProgress,
              _resize,
            ]),
            builder: (context, _) {
              final last = widget.sectionCount - 1;
              final page = widget.pageProgress.value.clamp(
                0.0,
                last.toDouble(),
              );
              final heights = _current();
              final from = page.floor().clamp(0, last);
              final to = (from + 1).clamp(0, last);
              final height = lerpDouble(
                heights[from],
                heights[to],
                page - from,
              )!;
              final active = page.round().clamp(0, last);

              return ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: Blurs.chrome,
                    sigmaY: Blurs.chrome,
                  ),
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: colors.surfaceGlass,
                      border: Border(
                        bottom: BorderSide(
                          color: colors.borderSubtle,
                          width: Strokes.hairline,
                        ),
                      ),
                    ),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.s4,
                            ProfileDockMetrics.shelfTop,
                            Space.s4,
                            0,
                          ),
                          child: Stack(
                            children: <Widget>[
                              for (var i = 0; i <= last; i++)
                                if ((page - i).abs() < 1)
                                  KeyedSubtree(
                                    key: ValueKey<int>(i),
                                    child: IgnorePointer(
                                      ignoring: i != active,
                                      child: Opacity(
                                        opacity: (1 - (page - i).abs()).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                        child: Transform.translate(
                                          offset: Offset(
                                            (i - page) *
                                                Space.s6 *
                                                (rtl ? -1 : 1),
                                            0,
                                          ),
                                          child: _SectionFilters(
                                            spec: specs[i],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionFilters extends StatelessWidget {
  const _SectionFilters({required this.spec});

  final ProfileFilterSpec spec;

  @override
  Widget build(BuildContext context) {
    final scope = spec.scope;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ProfileLensSegmented(
          key: ValueKey<String>(spec.primary.id),
          row: spec.primary,
        ),
        AnimatedSwitcher(
          duration: KMotion.duration(context, KDurations.base),
          switchInCurve: KCurves.decelerate,
          switchOutCurve: KCurves.accelerate,
          child: scope == null
              ? const SizedBox(
                  key: ValueKey<String>('no-scope'),
                  width: double.infinity,
                )
              : Padding(
                  key: ValueKey<String>(scope.id),
                  padding: const EdgeInsets.only(
                    top: ProfileDockMetrics.scopeGap,
                  ),
                  child: ProfileLensSegmented(row: scope, dense: true),
                ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────── segmented control ──

/// A row of equal segments with a thumb that glides to the chosen one.
///
/// The primary style sits in a sunken glass track with a raised neutral thumb
/// and shows each option's icon and name. The [dense] scope style is text only:
/// a faint pill and a short brand underline glide under the active name. Both
/// can be scrubbed: drag across the row and let go on a choice.
class ProfileLensSegmented extends StatefulWidget {
  /// Creates the control.
  const ProfileLensSegmented({
    required this.row,
    super.key,
    this.dense = false,
  });

  /// The choices and the active one.
  final ProfileFilterRow row;

  /// Scope-row styling.
  final bool dense;

  @override
  State<ProfileLensSegmented> createState() => _ProfileLensSegmentedState();
}

class _ProfileLensSegmentedState extends State<ProfileLensSegmented>
    with SingleTickerProviderStateMixin {
  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: widget.row.selected.toDouble(),
  );
  double _segmentWidth = 1;
  double? _dragOrigin;
  double _dragStartX = 0;

  @override
  void didUpdateWidget(covariant ProfileLensSegmented oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _thumb.value = widget.row.selected.toDouble();
      return;
    }
    if (_dragOrigin == null && oldWidget.row.selected != widget.row.selected) {
      _glideTo(widget.row.selected);
    }
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  void _glideTo(int index) {
    _thumb.animateTo(
      index.toDouble(),
      duration: KMotion.duration(context, KDurations.medium),
      curve: KMotion.curve(context, KCurves.emphasized),
    );
  }

  void _select(int index) {
    if (index == widget.row.selected) {
      _glideTo(index);
      return;
    }
    widget.row.onSelected(index);
  }

  void _onDragStart(DragStartDetails details) {
    _thumb.stop();
    _dragOrigin = _thumb.value;
    _dragStartX = details.localPosition.dx;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final origin = _dragOrigin;
    if (origin == null) return;
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final delta = (details.localPosition.dx - _dragStartX) * direction;
    _thumb.value = (origin + delta / _segmentWidth).clamp(
      0.0,
      (widget.row.options.length - 1).toDouble(),
    );
  }

  void _onDragEnd() {
    if (_dragOrigin == null) return;
    _dragOrigin = null;
    final target = _thumb.value.round().clamp(0, widget.row.options.length - 1);
    if (target != widget.row.selected) triggerInteractionTapFeedback(context);
    _select(target);
    _glideTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final dense = widget.dense;
    final options = widget.row.options;
    final inset = dense ? 0.0 : Space.s05;
    final height = dense
        ? ProfileDockMetrics.scopeHeight
        : ProfileDockMetrics.primaryHeight;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _onDragEnd(),
      onHorizontalDragCancel: _onDragEnd,
      child: Container(
        height: height,
        padding: EdgeInsets.all(inset),
        decoration: dense
            ? null
            : BoxDecoration(
                color: colors.bgSunken.withValues(alpha: Opacities.veil),
                borderRadius: BorderRadius.circular(Radii.full),
                border: Border.all(
                  color: colors.borderSubtle,
                  width: Strokes.hairline,
                ),
              ),
        // Measured inside the padding and the border, so the segments always
        // add up to exactly the space they have.
        child: LayoutBuilder(
          builder: (context, constraints) {
            _segmentWidth = math.max(constraints.maxWidth / options.length, 1);
            return AnimatedBuilder(
              animation: _thumb,
              builder: (context, _) {
                final position = _thumb.value;
                return Stack(
                  children: <Widget>[
                    PositionedDirectional(
                      start: position * _segmentWidth,
                      top: 0,
                      bottom: 0,
                      width: _segmentWidth,
                      child: dense ? const _ScopeThumb() : const _RaisedThumb(),
                    ),
                    Row(
                      children: <Widget>[
                        for (var i = 0; i < options.length; i++)
                          SizedBox(
                            width: _segmentWidth,
                            child: _FilterSegment(
                              option: options[i],
                              closeness: (1 - (position - i).abs()).clamp(
                                0.0,
                                1.0,
                              ),
                              selected: i == widget.row.selected,
                              dense: dense,
                              onTap: () => _select(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RaisedThumb extends StatelessWidget {
  const _RaisedThumb();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface3,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(
          color: colors.textPrimary.withValues(alpha: Opacities.ghost),
          width: Strokes.hairline,
        ),
        boxShadow: KlectTheme.shadow(Elevation.mid),
      ),
    );
  }
}

class _ScopeThumb extends StatelessWidget {
  const _ScopeThumb();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s1,
        vertical: Space.s05,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: Space.s4,
            height: Strokes.thick,
            decoration: BoxDecoration(
              color: colors.accentDefault,
              borderRadius: BorderRadius.circular(Radii.full),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.option,
    required this.closeness,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final ProfileNavOption option;
  final double closeness;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = Color.lerp(
      dense ? colors.textTertiary : colors.textSecondary,
      colors.textPrimary,
      closeness,
    )!;
    final style = (dense ? context.kt.caption : context.kt.label).copyWith(
      color: text,
    );

    final content = dense
        ? Text(option.label, maxLines: 1, softWrap: false, style: style)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                closeness >= 0.5 ? option.activeIcon : option.icon,
                size: Space.s4,
                color: Color.lerp(
                  colors.textTertiary,
                  colors.accentHover,
                  closeness,
                ),
              ),
              const SizedBox(width: Space.s15),
              Text(option.label, maxLines: 1, softWrap: false, style: style),
            ],
          );

    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: option.label,
      excludeSemantics: true,
      child: KPressable(
        onTap: onTap,
        enforceMinTapTarget: false,
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s1),
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab's content clear of the filter shelf at the top of the list,
/// easing with the shelf when a choice adds or removes the scope row.
class ProfileShelfSpacer extends StatelessWidget {
  /// Creates the spacer for [spec].
  const ProfileShelfSpacer({required this.spec, super.key});

  /// The filters shown above this tab.
  final ProfileFilterSpec spec;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: AnimatedContainer(
      duration: KMotion.duration(context, KDurations.base),
      curve: KMotion.curve(context, KCurves.emphasized),
      height: ProfileDockMetrics.shelfHeight(spec),
    ),
  );
}
