import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import 'k_pressable.dart';

/// One member of a sibling tab set — "For you", "Following", "Collections".
///
/// [id] is what a route parameter names, so it is the stable value: renaming
/// [label] never breaks a deep link.
@immutable
class KTabPagerTab {
  /// Creates a member.
  const KTabPagerTab({
    required this.id,
    required this.label,
    this.semanticLabel,
    this.visible = true,
  });

  /// Stable identifier, also the route-parameter value.
  final String id;

  /// Rendered copy on the rail.
  final String label;

  /// What a screen reader announces; [label] when absent.
  final String? semanticLabel;

  /// Whether this member participates in paging and the rail.
  final bool visible;
}

/// Shared claim state for horizontally interactive descendants of a pager.
class HorizontalDragClaims extends ChangeNotifier {
  final Set<Object> _claims = <Object>{};
  final Map<Object, Timer> _releaseTimers = <Object, Timer>{};

  /// True while a descendant owns a horizontal pointer sequence.
  bool get isHeld => _claims.isNotEmpty;

  /// Claims the current pointer sequence and returns its opaque token.
  Object claim() {
    final token = Object();
    _claims.add(token);
    notifyListeners();
    return token;
  }

  /// Releases [token] after the gesture hand-off grace period.
  void release(Object token) {
    _releaseTimers.remove(token)?.cancel();
    _releaseTimers[token] = Timer(const Duration(milliseconds: 120), () {
      _releaseTimers.remove(token);
      if (_claims.remove(token)) notifyListeners();
    });
  }

  @override
  void dispose() {
    for (final timer in _releaseTimers.values) {
      timer.cancel();
    }
    _releaseTimers.clear();
    super.dispose();
  }
}

/// Publishes horizontal-drag claims to a pager and its nested gesture regions.
class KHorizontalDragGuard extends InheritedNotifier<HorizontalDragClaims> {
  /// Creates the guard.
  const KHorizontalDragGuard({
    required HorizontalDragClaims claims,
    required super.child,
    super.key,
  }) : super(notifier: claims);

  /// Nearest claim state, or null outside a pager.
  static HorizontalDragClaims? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KHorizontalDragGuard>()
      ?.notifier;
}

/// Gives an entire pointer sequence to a nested horizontal interaction.
class KHorizontalDragClaimRegion extends StatefulWidget {
  /// Creates a claim-publishing region.
  const KHorizontalDragClaimRegion({required this.child, super.key});

  /// Nested media pager, reply swipe, or row swipe.
  final Widget child;

  @override
  State<KHorizontalDragClaimRegion> createState() =>
      _KHorizontalDragClaimRegionState();
}

class _KHorizontalDragClaimRegionState
    extends State<KHorizontalDragClaimRegion> {
  final Map<int, ({HorizontalDragClaims claims, Object token})> _tokens =
      <int, ({HorizontalDragClaims claims, Object token})>{};

  void _claim(PointerDownEvent event) {
    final claims = KHorizontalDragGuard.maybeOf(context);
    if (claims == null) return;
    _tokens[event.pointer] = (claims: claims, token: claims.claim());
  }

  void _release(PointerEvent event) {
    final held = _tokens.remove(event.pointer);
    if (held != null) held.claims.release(held.token);
  }

  @override
  void dispose() {
    for (final held in _tokens.values) {
      held.claims.release(held.token);
    }
    _tokens.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _claim,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: widget.child,
  );
}

// ───────────────────────────────────────────────────────── pure decisions ──
//
// Everything the pager decides is a function of numbers, declared here rather
// than buried in the widget: the commit threshold, the indicator position, the
// overscroll clamp and the settle durations are all testable without a widget
// tree.

/// Whether a released horizontal drag commits to the adjacent member.
///
/// True on a cumulative [displacement] of at least [Drags.pageCommitFraction]
/// of [viewportWidth] **or** a release [velocity] of at least
/// [Drags.flingVelocityMin]; false otherwise, in which case the pager settles
/// back on the member it started from (Requirements 14.2, 14.11).
///
/// [displacement] and [velocity] are in scroll-axis terms: positive means the
/// pager travelled towards the *next* member — the finger moved left.
bool tabPagerDragCommits({
  required double displacement,
  required double velocity,
  required double viewportWidth,
}) {
  if (velocity.abs() >= Drags.flingVelocityMin) return true;
  if (viewportWidth <= 0) return false;
  return displacement.abs() >= viewportWidth * Drags.pageCommitFraction;
}

/// The member a released drag settles on.
///
/// Never wraps and never travels more than one member: the result is always
/// within `[0, length - 1]`, so a drag past the first or the last member leaves
/// the selection where it was (Requirements 14.5, 14.12).
int tabPagerSettleIndex({
  required int originIndex,
  required int length,
  required double displacement,
  required double velocity,
  required double viewportWidth,
}) {
  if (length <= 1) return 0;
  final origin = originIndex.clamp(0, length - 1);
  final commits = tabPagerDragCommits(
    displacement: displacement,
    velocity: velocity,
    viewportWidth: viewportWidth,
  );
  if (!commits) return origin;
  // A fling decides the direction; otherwise the travelled distance does.
  final direction = velocity.abs() >= Drags.flingVelocityMin
      ? (velocity > 0 ? 1 : -1)
      : (displacement > 0
            ? 1
            : displacement < 0
            ? -1
            : 0);
  return (origin + direction).clamp(0, length - 1);
}

/// The indicator's fractional position for a [PageController.page] value.
///
/// A straight clamp: the indicator sits at `page` between the originating and
/// the adjacent label, so it tracks the dragged fraction of the viewport
/// linearly and never leaves the rail (Requirements 14.3, 14.5).
double tabPagerIndicatorPage({required double page, required int length}) {
  if (length <= 1) return 0;
  if (page.isNaN) return 0;
  return page.clamp(0, (length - 1).toDouble());
}

/// Left edge of the indicator on a rail of [railWidth] holding [length]
/// equally sized label slots.
///
/// Pure in [page], so the indicator is a function of the drag and of nothing
/// else (Requirement 14.3).
double tabPagerIndicatorOffset({
  required double page,
  required int length,
  required double railWidth,
  required double indicatorWidth,
}) {
  if (length <= 0 || railWidth <= 0) return 0;
  final slot = railWidth / length;
  final position = tabPagerIndicatorPage(page: page, length: length);
  return slot * position + (slot - indicatorWidth) / 2;
}

/// How far the pager may travel towards [value] before the edge stops it.
///
/// Travel beyond the first or the last member is allowed up to
/// [Drags.overscrollMax] and no further, and there is no wrap: the pager
/// cannot reach the opposite end (Requirement 14.12).
double tabPagerClampedPixels({
  required double value,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  final min = minScrollExtent - Drags.overscrollMax;
  final max = math.max(min, maxScrollExtent + Drags.overscrollMax);
  return value.clamp(min, max);
}

/// How long a released drag takes to settle.
///
/// Inside the [KDurations.deliberate] ceiling always, collapsed to
/// [KDurations.instant] under reduced motion where the page change is a fade
/// rather than a slide (Requirements 14.2, 14.11, 14.10).
Duration tabPagerSettleDuration({required bool reducedMotion}) =>
    reducedMotion ? KDurations.instant : KDurations.medium;

/// How long a label tap takes to reach its member.
///
/// Between 160 ms and [KDurations.deliberate] whatever the distance, and
/// [KDurations.instant] under reduced motion (Requirements 14.4, 14.10).
Duration tabPagerTapDuration({required bool reducedMotion}) =>
    reducedMotion ? KDurations.instant : KDurations.medium;

/// The member the pager opens on.
///
/// A [routeParam] naming a member wins; an empty, absent or unknown value
/// falls back to [selectedIndex] clamped into the set, with nothing surfaced
/// to the viewer (Requirements 14.9, 14.13).
int tabPagerInitialIndex({
  required List<KTabPagerTab> tabs,
  required String? routeParam,
  required int selectedIndex,
}) {
  final visibleTabs = <KTabPagerTab>[
    for (final tab in tabs)
      if (tab.visible) tab,
  ];
  if (visibleTabs.isEmpty) return 0;
  if (routeParam != null && routeParam.isNotEmpty) {
    final named = visibleTabs.indexWhere((tab) => tab.id == routeParam);
    if (named >= 0) return named;
  }
  return selectedIndex.clamp(0, visibleTabs.length - 1);
}

// ─────────────────────────────────────────────────────────────── physics ──

/// A settle that reaches [end] in exactly the duration it was given.
///
/// Flutter has no fixed-duration scroll simulation, and the pager needs one:
/// the commit has a stated ceiling (`KDurations.deliberate`) and a stated
/// reduced-motion value (90 ms), neither of which a spring can promise
/// (Requirements 14.2, 14.10, 14.11).
class KTabPagerSettleSimulation extends Simulation {
  /// Creates a settle from [start] to [end].
  KTabPagerSettleSimulation({
    required this.start,
    required this.end,
    required Duration duration,
    this.curve = KCurves.emphasized,
    super.tolerance,
  }) : seconds = math.max(
         duration.inMicroseconds / Duration.microsecondsPerSecond,
         _minSeconds,
       );

  /// A zero duration would divide by zero; one frame is the floor.
  static const double _minSeconds = 0.001;

  /// Scroll offset the settle starts from.
  final double start;

  /// Scroll offset the settle lands on.
  final double end;

  /// Easing applied to the travel.
  final Curve curve;

  /// Total settle time in seconds.
  final double seconds;

  double _t(double time) => (time / seconds).clamp(0.0, 1.0);

  @override
  double x(double time) => start + (end - start) * curve.transform(_t(time));

  @override
  double dx(double time) {
    // Numeric derivative over one millisecond: `Curve` exposes no slope.
    const epsilon = 0.001;
    return (x(time + epsilon) - x(time)) / epsilon;
  }

  @override
  bool isDone(double time) => time >= seconds;
}

/// The pager's physics.
///
/// Three jobs, none of which `PageScrollPhysics` does: commit on a quarter of
/// the viewport rather than a half (14.2), clamp travel past the first and the
/// last member to [Drags.overscrollMax] without wrapping (14.12), and settle in
/// a stated duration (14.11, 14.10).
class KTabPagerPhysics extends ScrollPhysics {
  /// Creates the physics.
  ///
  /// [originPage] reports the page the in-flight drag started from — the
  /// commit is measured from there, so a drag that jitters back and forth still
  /// settles on the member it began on. [reducedMotion] reports the current
  /// accessibility setting; both are read at drag end rather than captured, so
  /// one physics instance survives the whole route.
  const KTabPagerPhysics({
    required this.originPage,
    required this.reducedMotion,
    super.parent,
  });

  /// The page the in-flight drag started from.
  final ValueGetter<double> originPage;

  /// Whether the platform asks us to remove animation travel.
  final ValueGetter<bool> reducedMotion;

  @override
  KTabPagerPhysics applyTo(ScrollPhysics? ancestor) => KTabPagerPhysics(
    originPage: originPage,
    reducedMotion: reducedMotion,
    parent: buildParent(ancestor),
  );

  /// The pager owns its own snapping, so nothing may scroll implicitly past a
  /// member boundary.
  @override
  bool get allowImplicitScrolling => false;

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final limit = tabPagerClampedPixels(
      value: value,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (limit == value) return 0;
    // Already past the allowance — a viewport resize can do that. Refuse the
    // whole delta rather than snapping, so nothing jumps under the finger.
    final beyondAlready = value < limit
        ? position.pixels <= limit
        : position.pixels >= limit;
    return beyondAlready ? value - position.pixels : value - limit;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final width = position.viewportDimension;
    if (width <= 0) return null;
    final length = (position.maxScrollExtent / width).round() + 1;
    final maxIndex = length - 1;
    final origin = maxIndex <= 0 ? 0 : originPage().round().clamp(0, maxIndex);
    final target = tabPagerSettleIndex(
      originIndex: origin,
      length: length,
      displacement: position.pixels - origin * width,
      velocity: velocity,
      viewportWidth: width,
    );
    final targetPixels = (target * width).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final tolerance = toleranceFor(position);
    if ((targetPixels - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return KTabPagerSettleSimulation(
      start: position.pixels,
      end: targetPixels,
      duration: tabPagerSettleDuration(reducedMotion: reducedMotion()),
      curve: reducedMotion() ? KCurves.linear : KCurves.emphasized,
      tolerance: tolerance,
    );
  }
}

// ───────────────────────────────────────────────────────────────── pager ──

/// Pages horizontally between the 2 to 6 members of a sibling tab set.
///
/// One member fills the viewport at rest; below two members no horizontal
/// paging drag is accepted at all (Requirement 14.1). A drag commits on a
/// quarter of the viewport or a 400 px/s fling and otherwise returns to the
/// member it started from, leaving the selection and every member's scroll
/// offset alone (14.2, 14.11). The indicator is a pure function of the page
/// value, so it tracks the finger and only the settle changes the selection
/// (14.3).
///
/// Controlled, like every other Klect input: [selectedIndex] comes in,
/// [onSelected] goes out, and the parent owns the state.
class KTabPager extends StatefulWidget {
  /// Creates a pager over [tabs].
  const KTabPager({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.builder,
    super.key,
    this.routeParam,
    this.showRail = true,
    this.onPageProgress,
  });

  /// The visible members, in order. Two to six.
  final List<KTabPagerTab> tabs;

  /// Which member is selected. Clamped into the set.
  final int selectedIndex;

  /// Called with the new index once a settle or a tap lands.
  final ValueChanged<int> onSelected;

  /// Builds the page for a member.
  final IndexedWidgetBuilder builder;

  /// Restores the opening member by [KTabPagerTab.id], with no animation.
  final String? routeParam;

  /// Whether the pager renders its own label rail and indicator.
  ///
  /// False where the enclosing screen already renders the rail — a pinned
  /// sliver header, for instance — and only wants the body.
  final bool showRail;

  /// Reports the live fractional page while a drag or tap animation moves.
  ///
  /// Parents with an external rail use this for immediate visual feedback
  /// while [onSelected] remains the single committed-state callback.
  final ValueChanged<double>? onPageProgress;

  @override
  State<KTabPager> createState() => _KTabPagerState();
}

class _KTabPagerState extends State<KTabPager> with WidgetsBindingObserver {
  /// Rail height and indicator geometry, straight off the token ramp.
  static const double _railHeight = Space.s12;
  static const double _indicatorWidth = Space.s8;
  static const double _indicatorHeight = Space.s05;

  late final PageController _controller;
  final HorizontalDragClaims _claims = HorizontalDragClaims();
  late final KTabPagerPhysics _physics = KTabPagerPhysics(
    originPage: () => _originPage,
    reducedMotion: () => _reduced,
  );

  /// The page the in-flight drag started from; the rest page otherwise.
  double _originPage = 0;

  /// Where the pager is heading: the last settled or tapped member.
  int _target = 0;

  bool _reduced = false;
  double? _lastPublishedPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = tabPagerInitialIndex(
      tabs: widget.tabs,
      routeParam: widget.routeParam,
      selectedIndex: widget.selectedIndex,
    );
    _target = initial;
    _originPage = initial.toDouble();
    _controller = PageController(initialPage: initial);
    _controller.addListener(_publishPageProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishPageProgress(force: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = KMotion.reduced(context);
  }

  @override
  void didUpdateWidget(KTabPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs.isEmpty) return;
    final oldTabs = <KTabPagerTab>[
      for (final tab in oldWidget.tabs)
        if (tab.visible) tab,
    ];
    final previousId = _target >= 0 && _target < oldTabs.length
        ? oldTabs[_target].id
        : null;
    if (previousId != null && !_tabs.any((tab) => tab.id == previousId)) {
      _target = 0;
      _originPage = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      if (widget.selectedIndex != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSelected(0);
        });
      }
      return;
    }
    // A selection driven from outside — a tap we reported, or a restore — is
    // followed by the page.
    final wanted = widget.selectedIndex.clamp(0, _tabs.length - 1);
    if (wanted != _target) _animateTo(wanted, notify: false);
    if (oldWidget.onPageProgress != widget.onPageProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishPageProgress(force: true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _claims.dispose();
    super.dispose();
  }

  List<KTabPagerTab> get _tabs => <KTabPagerTab>[
    for (final tab in widget.tabs)
      if (tab.visible) tab,
  ];

  int get _length => _tabs.length;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _settleFractionalPage();
  }

  /// The live fractional page, or the rest page before the first layout.
  double get _page {
    if (!_controller.hasClients) return _target.toDouble();
    final position = _controller.position;
    if (!position.hasPixels || !position.hasContentDimensions) {
      return _target.toDouble();
    }
    return _controller.page ?? _target.toDouble();
  }

  void _publishPageProgress({bool force = false}) {
    final callback = widget.onPageProgress;
    if (callback == null || _length == 0) return;
    final page = tabPagerIndicatorPage(page: _page, length: _length);
    if (!force &&
        _lastPublishedPage != null &&
        (page - _lastPublishedPage!).abs() < 0.001) {
      return;
    }
    _lastPublishedPage = page;
    callback(page);
  }

  void _animateTo(int index, {bool notify = true}) {
    if (_length == 0) return;
    final target = index.clamp(0, _length - 1);
    _target = target;
    _originPage = target.toDouble();
    if (_controller.hasClients) {
      unawaited(
        _controller.animateToPage(
          target,
          duration: tabPagerTapDuration(reducedMotion: _reduced),
          curve: _reduced ? KCurves.linear : KCurves.emphasized,
        ),
      );
    }
    if (notify && target != widget.selectedIndex) widget.onSelected(target);
  }

  void _settleFractionalPage() {
    if (!_controller.hasClients || _length < 2) return;
    final page = _page;
    final nearest = page.round().clamp(0, _length - 1);
    if ((page - nearest).abs() <= 0.001) return;
    _animateTo(nearest);
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 0 is the pager's own viewport; anything deeper is a page's list.
    if (notification.depth != 0 || _length == 0) return false;
    if (notification is ScrollStartNotification) {
      // Only a finger moves the origin. A programmatic animation already set it
      // to its destination, and taking the origin from the current page here
      // would make the settle that follows the animation commit a page further.
      if (notification.dragDetails == null) return false;
      // The commit is measured from here, whatever the finger does next.
      _originPage = _page.roundToDouble();
    } else if (notification is ScrollEndNotification) {
      final settled = _page.round().clamp(0, _length - 1);
      _target = settled;
      _originPage = settled.toDouble();
      // Only the settle sets the selection (14.3).
      if (settled != widget.selectedIndex) widget.onSelected(settled);
    }
    return false;
  }

  Widget _buildPage(BuildContext context, int index, double width) {
    final page = _KeepAliveTabPage(
      key: PageStorageKey<String>('k-tab-pager-${_tabs[index].id}'),
      child: widget.builder(context, index),
    );
    if (!_reduced || width <= 0) return page;
    // Reduced motion keeps the drag, drops the travel: each page is translated
    // back by exactly the offset the viewport gave it, so nothing slides, and
    // the change reads as an opacity crossfade over the 90 ms settle (14.10).
    return AnimatedBuilder(
      animation: _controller,
      child: page,
      builder: (context, child) {
        final delta = _page - index;
        final opacity = (1 - delta.abs()).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: opacity <= 0,
          child: Transform.translate(
            offset: Offset(delta * width, 0),
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
    );
  }

  Widget _buildRail(BuildContext context) {
    final colors = context.kc;
    return SizedBox(
      height: _railHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: <Widget>[
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  children: <Widget>[
                    for (final (index, tab) in _tabs.indexed)
                      Expanded(
                        child: _TabLabel(
                          tab: tab,
                          selectionProgress: (1 - (_page - index).abs()).clamp(
                            0.0,
                            1.0,
                          ),
                          onTap: () => _animateTo(index),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: _indicatorHeight,
                  child: AnimatedBuilder(
                    animation: _controller,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accentDefault,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                      child: const SizedBox(
                        width: _indicatorWidth,
                        height: _indicatorHeight,
                      ),
                    ),
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        tabPagerIndicatorOffset(
                          page: _page,
                          length: _length,
                          railWidth: constraints.maxWidth,
                          indicatorWidth: _indicatorWidth,
                        ),
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: child,
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
  }

  @override
  Widget build(BuildContext context) {
    if (_length == 0) return const SizedBox.shrink();
    return KHorizontalDragGuard(
      claims: _claims,
      child: AnimatedBuilder(
        animation: _claims,
        builder: (context, _) {
          final body = NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            // The platform overscroll indicator stretches the content past
            // the edge, so the custom clamp is the only edge affordance.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(overscroll: false, scrollbars: false),
              child: LayoutBuilder(
                builder: (context, constraints) => Listener(
                  onPointerCancel: (_) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _settleFractionalPage();
                    });
                  },
                  child: PageView.builder(
                    controller: _controller,
                    pageSnapping: false,
                    clipBehavior: Clip.hardEdge,
                    physics: _length < 2 || _claims.isHeld
                        ? const NeverScrollableScrollPhysics()
                        : _physics,
                    itemCount: _length,
                    itemBuilder: (context, index) =>
                        _buildPage(context, index, constraints.maxWidth),
                  ),
                ),
              ),
            ),
          );
          if (!widget.showRail) return body;
          return Column(
            children: <Widget>[
              _buildRail(context),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

class _KeepAliveTabPage extends StatefulWidget {
  const _KeepAliveTabPage({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAliveTabPage> createState() => _KeepAliveTabPageState();
}

class _KeepAliveTabPageState extends State<_KeepAliveTabPage>
    with AutomaticKeepAliveClientMixin<_KeepAliveTabPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.tab,
    required this.selectionProgress,
    required this.onTap,
  });

  final KTabPagerTab tab;
  final double selectionProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final selected = selectionProgress >= 0.5;
    final foreground = Color.lerp(
      colors.textTertiary,
      colors.textPrimary,
      selectionProgress,
    )!;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.semanticLabel ?? tab.label,
      excludeSemantics: true,
      child: KPressable(
        enforceMinTapTarget: false,
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.kt.label.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
