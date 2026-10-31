import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/feedback/interaction_feedback.dart';
import '../../../core/images/k_image_cache.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../data/closeup_providers.dart';

/// The long-press **peek**: like · save · repost · share · report, fanned out
/// around a blown-up preview of the card you are holding.
///
/// This is the third leg of the gesture contract (`docs/DESIGN_SYSTEM.md` §4)
/// and the reason a Surf tile shows no buttons at rest — the most common
/// action is one gesture away, the rest are two, nothing is three.
///
/// When the peek is opened with `gallery: true` (a collection, subcollection
/// or multi-photo item), the preview becomes a swipeable deck of every photo
/// in the set. The finger that opened the peek can scrub through the deck
/// without lifting ([KPeekMenu.hold]); after lifting, a normal swipe pages it.
abstract final class KPeekMenu {
  /// Opens the peek over the whole app.
  ///
  /// Returns when the peek closes. The toggles it fires go through the
  /// optimistic engine, so the underlying card is already correct by the time
  /// the peek has finished dismissing.
  static Future<void> show(
    BuildContext context, {
    required EntityRef entity,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? blurhash,
    double? aspectRatio,
    bool gallery = false,
  }) => Navigator.of(context, rootNavigator: true).push<void>(
    _PeekRoute(
      config: _PeekConfig(
        entity: entity,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        blurhash: blurhash,
        aspectRatio: aspectRatio,
        gallery: gallery,
        scrim: KlectTheme.of(context).colors.surfaceScrim,
      ),
    ),
  );

  /// Opens the peek while the finger that long-pressed is **still down**.
  ///
  /// Pushing a route cancels every pointer the navigator is tracking, which
  /// would kill the held finger. So while the finger is down the peek lives in
  /// a plain overlay entry and follows [KPeekHold.move]; on
  /// [KPeekHold.release] it hands over, frame-for-frame, to the regular peek
  /// route, which owns back-button, barrier and action handling.
  static KPeekHold hold(
    BuildContext context, {
    required EntityRef entity,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? blurhash,
    double? aspectRatio,
    bool gallery = false,
  }) {
    final hold = KPeekHold._(
      navigator: Navigator.of(context, rootNavigator: true),
      config: _PeekConfig(
        entity: entity,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        blurhash: blurhash,
        aspectRatio: aspectRatio,
        gallery: gallery,
        scrim: KlectTheme.of(context).colors.surfaceScrim,
      ),
    ).._open();
    return hold;
  }
}

/// A peek that is being driven by a finger that has not lifted yet.
///
/// Feed it the held pointer's moves with [move] and call [release] when the
/// pointer goes up or is cancelled. Calling [release] more than once is safe.
class KPeekHold {
  KPeekHold._({required this._navigator, required this._config});

  final NavigatorState _navigator;
  final _PeekConfig _config;
  final _HeldDrag _drag = _HeldDrag();
  final GlobalKey<_PeekGalleryState> _galleryKey =
      GlobalKey<_PeekGalleryState>();
  final GlobalKey<_PeekHoldHostState> _hostKey =
      GlobalKey<_PeekHoldHostState>();
  OverlayEntry? _entry;
  bool _released = false;

  void _open() {
    final overlay = _navigator.overlay;
    if (overlay == null) {
      _released = true;
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => _PeekHoldHost(key: _hostKey, hold: this),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Forwards one move of the held pointer. Horizontal travel scrubs the
  /// gallery.
  void move(PointerMoveEvent event) {
    if (_released) return;
    _drag.add(event);
  }

  /// The held finger lifted (or was cancelled): hand over to the peek route.
  void release() {
    if (_released) return;
    _released = true;
    _drag.finished = true;
    // Deferred so the navigator has finished processing the pointer-up
    // before the push; otherwise the push "cancels" a pointer mid-release.
    scheduleMicrotask(_handOff);
  }

  void _handOff() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;

    final progress = _hostKey.currentState?.progress ?? 1;
    final snapshot = _galleryKey.currentState?.snapshot();
    if (_navigator.mounted) {
      unawaited(
        _navigator.push<void>(
          _PeekRoute(
            config: _config,
            initialProgress: progress,
            handoff: snapshot,
          ),
        ),
      );
    }

    // The route's entries are inserted *below* this entry, so for exactly one
    // frame both paint the same picture; then the overlay copy goes away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      entry
        ..remove()
        ..dispose();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Everything the peek needs to render, shared by the overlay and the route.
class _PeekConfig {
  const _PeekConfig({
    required this.entity,
    required this.scrim,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
    this.gallery = false,
  });

  final EntityRef entity;
  final Color scrim;
  final String? title;
  final String? subtitle;
  final String? imageUrl;
  final String? blurhash;
  final double? aspectRatio;
  final bool gallery;
}

/// Accumulated horizontal travel of the held finger.
class _HeldDrag extends ChangeNotifier {
  double dx = 0;
  bool finished = false;
  VelocityTracker? _tracker;

  void add(PointerMoveEvent event) {
    dx += event.delta.dx;
    (_tracker ??= VelocityTracker.withKind(
      event.kind,
    )).addPosition(event.timeStamp, event.position);
    notifyListeners();
  }

  /// Horizontal release velocity in logical pixels per second.
  double get velocity => _tracker?.getVelocity().pixelsPerSecond.dx ?? 0;
}

/// Gallery state carried from the held overlay into the route.
class _GalleryHandoff {
  const _GalleryHandoff({required this.position, required this.velocity});

  /// Fractional page the deck was showing.
  final double position;

  /// Pages per second the finger was travelling at when it lifted.
  final double velocity;
}

/// The peek while the finger is down. Mirrors [_PeekRoute]'s barrier and
/// entrance so the handoff is invisible, and swallows every other pointer so
/// nothing underneath reacts.
class _PeekHoldHost extends StatefulWidget {
  const _PeekHoldHost({required this.hold, super.key});

  final KPeekHold hold;

  @override
  State<_PeekHoldHost> createState() => _PeekHoldHostState();
}

class _PeekHoldHostState extends State<_PeekHoldHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.medium,
  );
  late final CurvedAnimation _barrier = CurvedAnimation(
    parent: _controller,
    curve: _PeekRoute.barrierEase,
  );

  /// Entrance progress, so the route can continue from the same frame.
  double get progress => _controller.value;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _barrier.dispose();
    _controller.dispose();
    // Children (the gallery) have already detached their listeners.
    widget.hold._drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.hold._config;
    return AbsorbPointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedBuilder(
            animation: _barrier,
            builder: (context, _) => ColoredBox(
              color: Color.lerp(
                config.scrim.withValues(alpha: 0),
                config.scrim,
                _barrier.value,
              )!,
            ),
          ),
          _PeekBody(
            config: config,
            animation: _controller,
            held: widget.hold._drag,
            galleryKey: widget.hold._galleryKey,
          ),
        ],
      ),
    );
  }
}

class _PeekRoute extends PopupRoute<void> {
  _PeekRoute({required this.config, this.initialProgress = 0, this.handoff});

  /// Barrier fade curve, shared with the held overlay so the two match.
  static const Curve barrierEase = KCurves.standard;

  final _PeekConfig config;

  /// Where the entrance starts — non-zero when taking over from a hold.
  final double initialProgress;

  /// Gallery position/velocity inherited from a hold.
  final _GalleryHandoff? handoff;

  @override
  Color get barrierColor => config.scrim;

  @override
  Curve get barrierCurve => barrierEase;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss quick actions';

  @override
  Duration get transitionDuration => KDurations.medium;

  @override
  Duration get reverseTransitionDuration => KDurations.fast;

  @override
  AnimationController createAnimationController() =>
      super.createAnimationController()
        ..value = initialProgress.clamp(0.0, 1.0);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _PeekBody(config: config, animation: animation, handoff: handoff);
}

class _PeekAction {
  const _PeekAction({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
}

class _PeekBody extends ConsumerWidget {
  const _PeekBody({
    required this.config,
    required this.animation,
    this.held,
    this.galleryKey,
    this.handoff,
  });

  final _PeekConfig config;
  final Animation<double> animation;
  final _HeldDrag? held;
  final GlobalKey<_PeekGalleryState>? galleryKey;
  final _GalleryHandoff? handoff;

  /// How far the outermost action sits below the middle one. A fan, not a row.
  static const double _arcDepth = Space.s5;

  /// Fraction of the entrance each action's spring is offset by.
  static const double _stagger = 0.08;

  void _share(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      KShareSheet.show(
        navigator.context,
        entityType: config.entity.type,
        entityId: config.entity.id,
        title: config.title,
      ),
    );
  }

  void _report(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      KReportSheet.showForEntity(
        navigator.context,
        type: config.entity.type,
        entityId: config.entity.id,
        subjectLabel: config.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final entity = config.entity;
    final title = config.title;
    final subtitle = config.subtitle;
    final social = ref.watch(interactionProvider(entity));
    final controller = ref.read(interactionProvider(entity).notifier);
    final reduced = KMotion.reduced(context);

    void close() => Navigator.of(context).pop();

    final actions = <_PeekAction>[
      _PeekAction(
        icon: Icons.favorite_border_rounded,
        activeIcon: Icons.favorite_rounded,
        label: social.liked ? 'Liked' : 'Like',
        color: colors.actionLike,
        active: social.liked,
        onTap: () {
          unawaited(controller.toggleLike());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.bookmark_border_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: social.saved ? 'Saved' : 'Save',
        color: colors.actionSave,
        active: social.saved,
        onTap: () {
          unawaited(controller.toggleSave());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.repeat_rounded,
        activeIcon: Icons.repeat_on_rounded,
        label: social.reposted ? 'Reposted' : 'Repost',
        color: colors.actionRepost,
        active: social.reposted,
        onTap: () {
          unawaited(controller.toggleRepost());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.ios_share_rounded,
        activeIcon: Icons.ios_share_rounded,
        label: 'Share',
        color: colors.actionShare,
        onTap: () => _share(context),
      ),
      _PeekAction(
        icon: Icons.flag_outlined,
        activeIcon: Icons.flag_rounded,
        label: 'Report',
        color: colors.semanticDanger,
        onTap: () => _report(context),
      ),
    ];

    final curved = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.emphasized,
      reverseCurve: KCurves.accelerate,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        triggerInteractionTapFeedback(context);
        close();
      },
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.sheet, sigmaY: Blurs.sheet),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: curved,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Layout.readableMaxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _PeekPreview(
                      animation: curved,
                      reduced: reduced,
                      child: _PeekGallery(
                        key: galleryKey,
                        config: config,
                        held: held,
                        handoff: handoff,
                      ),
                    ),
                    if (title != null) ...<Widget>[
                      const SizedBox(height: Space.s4),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s6,
                        ),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.title3,
                        ),
                      ),
                    ],
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: Space.s1),
                      Text(
                        subtitle,
                        style: text.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.s8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (var index = 0; index < actions.length; index++)
                            _PeekActionButton(
                              action: actions[index],
                              animation: animation,
                              reduced: reduced,
                              arcOffset: _arcOffsetFor(index, actions.length),
                              delay: index * _stagger,
                            ),
                        ],
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
  }

  /// A shallow parabola: the middle action sits highest.
  static double _arcOffsetFor(int index, int count) {
    if (count <= 1) return 0;
    final t = index / (count - 1) * 2 - 1;
    return _arcDepth * t * t;
  }
}

/// The preview's entrance: it grows out of the held card with an overshoot.
class _PeekPreview extends StatelessWidget {
  const _PeekPreview({
    required this.animation,
    required this.reduced,
    required this.child,
  });

  final Animation<double> animation;
  final bool reduced;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduced) return child;
    return ScaleTransition(
      scale: Tween<double>(
        begin: KMotion.pressScale,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: KCurves.overshoot)),
      child: child,
    );
  }
}

/// One photo in the peek deck.
class _PeekPhoto {
  const _PeekPhoto({this.url, this.blurhash, this.label});

  final String? url;
  final String? blurhash;
  final String? label;
}

/// The preview image — and, for multi-photo entities, a swipeable deck.
///
/// Position is a single fractional page value held in an unbounded
/// controller: fingers write it directly, releases settle it with a spring
/// (`docs/DESIGN_SYSTEM.md` §3 — the finger drives a spring, never a curve).
/// Neighbours sit tucked behind the current photo, turned slightly away, so
/// the deck reads as a stack you can flick through.
class _PeekGallery extends ConsumerStatefulWidget {
  const _PeekGallery({
    required this.config,
    super.key,
    this.held,
    this.handoff,
  });

  final _PeekConfig config;

  /// Present while the opening finger is still down.
  final _HeldDrag? held;

  /// Present when taking over from a hold.
  final _GalleryHandoff? handoff;

  @override
  ConsumerState<_PeekGallery> createState() => _PeekGalleryState();
}

class _PeekGalleryState extends ConsumerState<_PeekGallery>
    with SingleTickerProviderStateMixin {
  /// A held finger moves one page per this fraction of the preview width, so
  /// a thumb sweep reaches a few photos without lifting.
  static const double _heldTravel = 0.45;

  /// How far past either end a drag can stretch, in pages.
  static const double _maxOverscroll = 0.3;

  /// How far a release velocity projects the resting page, in seconds.
  static const double _projection = 0.18;

  /// Perspective depth for the neighbour tilt.
  static const double _perspective = 0.0012;

  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.handoff?.position ?? 0,
  );

  List<_PeekPhoto> _photos = const <_PeekPhoto>[];
  final Set<String> _precached = <String>{};
  double _extent = 1;
  double _raw = 0;
  double _heldAnchor = 0;
  double _heldAnchorDx = 0;
  late int _index = (widget.handoff?.position ?? 0).round();

  int get _count => math.max(_photos.length, 1);
  bool get _interactive => widget.config.gallery;

  @override
  void initState() {
    super.initState();
    _position.addListener(_onPosition);
    final held = widget.held;
    if (held != null && _interactive) {
      _heldAnchor = _position.value;
      _heldAnchorDx = held.dx;
      held.addListener(_onHeld);
    }
    final handoff = widget.handoff;
    if (handoff != null) {
      // Let the first layout measure the box before the spring starts.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settle(handoff.velocity);
      });
    }
  }

  @override
  void dispose() {
    widget.held?.removeListener(_onHeld);
    _position.dispose();
    super.dispose();
  }

  /// What the route should continue from.
  _GalleryHandoff snapshot() {
    final held = widget.held;
    final pxPerSecond = held?.velocity ?? 0;
    final velocity = held == null
        ? 0.0
        : (-pxPerSecond / (_extent * _heldTravel)).clamp(-8.0, 8.0);
    return _GalleryHandoff(position: _position.value, velocity: velocity);
  }

  // ── input ────────────────────────────────────────────────────────────────

  void _onHeld() {
    final held = widget.held!;
    if (held.finished) return;
    final travel = (held.dx - _heldAnchorDx) / (_extent * _heldTravel);
    _position.value = _rubber(_heldAnchor - travel);
  }

  void _onDragStart(DragStartDetails _) {
    _position.stop();
    _raw = _position.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _raw -= (details.primaryDelta ?? 0) / _extent;
    _position.value = _rubber(_raw);
  }

  void _onDragEnd(DragEndDetails details) =>
      _settle(-(details.primaryVelocity ?? 0) / _extent);

  void _goTo(int index) {
    _position.stop();
    _raw = _position.value;
    _settleTo(index.clamp(0, _count - 1).toDouble(), 0);
  }

  double _rubber(double raw) {
    final max = (_count - 1).toDouble();
    double band(double over) => _maxOverscroll * over / (over + 1);
    if (raw < 0) return -band(-raw);
    if (raw > max) return max + band(raw - max);
    return raw;
  }

  void _settle(double velocity) {
    final max = (_count - 1).toDouble();
    final current = _position.value;
    final nearest = current.roundToDouble();
    // A flick moves at most one photo from where the finger let go.
    final target = (current + velocity * _projection)
        .roundToDouble()
        .clamp(nearest - 1, nearest + 1)
        .clamp(0.0, max)
        .toDouble();
    _settleTo(target, velocity);
  }

  void _settleTo(double target, double velocity) {
    if (KMotion.reduced(context)) {
      unawaited(
        _position.animateTo(
          target,
          duration: KMotion.duration(context, KDurations.fast),
          curve: KCurves.standard,
        ),
      );
      return;
    }
    unawaited(
      _position.animateWith(
        SpringSimulation(
          KMotion.spring(Springs.snappy),
          _position.value,
          target,
          velocity,
        ),
      ),
    );
  }

  void _onPosition() {
    final index = _position.value.round().clamp(0, _count - 1);
    if (index == _index) return;
    // Rebuilds the semantics value; the deck itself repaints per tick.
    setState(() => _index = index);
    triggerInteractionTapFeedback(context);
    _precacheAround(index);
  }

  // ── data ─────────────────────────────────────────────────────────────────

  List<_PeekPhoto> _resolvePhotos() {
    final config = widget.config;
    final cover = _PeekPhoto(
      url: config.imageUrl,
      blurhash: config.blurhash,
      label: config.title,
    );
    if (!_interactive) return <_PeekPhoto>[cover];

    final api = ref.watch(klectApiProvider);
    final entity = config.entity;
    final media = entity.type == EntityType.post
        ? ref.watch(postMediaProvider(entity.id)).value
        : switch (ref.watch(closeupProvider(entity)).value) {
            final closeup? => immersiveMediaOf(closeup),
            null => null,
          };

    final out = <_PeekPhoto>[];
    final seen = <String>{};
    final coverUrl = config.imageUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      seen.add(coverUrl);
      out.add(cover);
    }
    for (final m in media ?? const <ImmersiveMedia>[]) {
      final url = api.publicUrl(m.path);
      if (url == null || url.isEmpty || !seen.add(url)) continue;
      out.add(_PeekPhoto(url: url, blurhash: m.blurhash, label: m.altText));
    }
    return out.isEmpty ? <_PeekPhoto>[cover] : out;
  }

  void _precacheAround(int index) {
    for (final i in <int>[index + 1, index - 1, index + 2]) {
      if (i < 0 || i >= _photos.length) continue;
      final url = _photos[i].url;
      if (url == null || !_precached.add(url)) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(url, cacheManager: KImageCache.instance),
          context,
        ),
      );
    }
  }

  // ── render ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final photos = _resolvePhotos();
    final grew = photos.length != _photos.length;
    _photos = photos;
    if (grew && photos.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheAround(_index);
      });
    }

    final screen = MediaQuery.sizeOf(context);
    final reduced = KMotion.reduced(context);
    final aspect = widget.config.aspectRatio ?? Aspect.cover;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(
          constraints.maxWidth,
          screen.width - Space.s20,
        );
        final maxHeight = screen.height / 2;
        var width = maxWidth;
        var height = width / aspect;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * aspect;
        }
        _extent = math.max(width, 1);

        final deck = AnimatedBuilder(
          animation: _position,
          builder: (context, _) => _buildDeck(width, height, reduced),
        );

        if (!_interactive) return deck;

        final multiple = _count > 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              label: multiple ? 'Photo ${_index + 1} of $_count' : null,
              onIncrease: multiple && _index < _count - 1
                  ? () => _goTo(_index + 1)
                  : null,
              onDecrease: multiple && _index > 0
                  ? () => _goTo(_index - 1)
                  : null,
              child: GestureDetector(
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: () => _settle(0),
                child: deck,
              ),
            ),
            // Reserved even before the photos load so nothing below jumps.
            SizedBox(
              height: Space.s8,
              child: AnimatedOpacity(
                opacity: multiple ? 1 : 0,
                duration: KMotion.duration(context, KDurations.base),
                curve: KCurves.standard,
                child: AnimatedBuilder(
                  animation: _position,
                  builder: (context, _) => _Indicator(
                    count: _count,
                    position: _position.value,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeck(double width, double height, bool reduced) {
    final position = _position.value;
    final visible = <int>[
      for (var i = 0; i < _photos.length; i++)
        if ((i - position).abs() < 2) i,
    ]..sort((a, b) => (b - position).abs().compareTo((a - position).abs()));

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final i in visible)
            KeyedSubtree(
              key: ValueKey<int>(i),
              child: _page(i, i - position, width, height, reduced),
            ),
        ],
      ),
    );
  }

  Widget _page(
    int index,
    double delta,
    double width,
    double height,
    bool reduced,
  ) {
    final colors = context.kc;
    final photo = _photos[index];
    final distance = delta.abs();
    final near = math.min(distance, 1.0);
    final label = photo.label;
    final showLabel =
        index > 0 &&
        label != null &&
        label.isNotEmpty &&
        label != widget.config.title;

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: KlectTheme.shadow(Elevation.high),
        color: colors.surface2,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          KBlurhashImage(
            url: photo.url,
            blurhash: photo.blurhash,
            semanticLabel: photo.label,
            borderRadius: BorderRadius.circular(Radii.xl),
          ),
          if (showLabel)
            Positioned(
              left: Space.s3,
              bottom: Space.s3,
              right: Space.s3,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Opacity(
                  opacity: 1 - near,
                  child: _GlassLabel(text: label),
                ),
              ),
            ),
          // Depth: photos behind the current one sink into the backdrop.
          if (distance > 0.001)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  color: colors.bgBase.withValues(alpha: 0.5 * near),
                ),
              ),
            ),
        ],
      ),
    );

    if (reduced) {
      return Positioned.fill(
        child: Transform.translate(
          offset: Offset(delta * (width + Space.s4), 0),
          child: card,
        ),
      );
    }

    final scale = 1 - 0.12 * math.min(distance, 1.5);
    final tilt = -delta.clamp(-1.5, 1.5) * 0.42;
    card = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, _perspective)
        ..rotateY(tilt),
      child: card,
    );
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(delta * width * 0.56, 0),
        child: Transform.scale(scale: scale, child: card),
      ),
    );
  }
}

/// Dots that stretch toward the photo you are on, tracking the finger
/// continuously. Long sets switch to a plain "3 / 12" counter.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.count, required this.position});

  static const int _maxDots = 8;

  final int count;
  final double position;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    if (count > _maxDots) {
      final index = position.round().clamp(0, count - 1);
      return Center(
        child: Text(
          '${index + 1} / $count',
          style: context.kt.caption.copyWith(color: colors.textSecondary),
        ),
      );
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < count; i++)
            Builder(
              builder: (context) {
                final t = (1 - (i - position).abs()).clamp(0.0, 1.0);
                return Container(
                  width: Space.s15 + (Space.s4 - Space.s15) * t,
                  height: Space.s15,
                  margin: const EdgeInsets.symmetric(horizontal: Space.s05),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.full),
                    color: Color.lerp(
                      colors.textTertiary,
                      colors.textPrimary,
                      t,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The name of a child photo (a subcollection, an item) over its image.
class _GlassLabel extends StatelessWidget {
  const _GlassLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s25,
        vertical: Space.s1,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.kt.caption.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

class _PeekActionButton extends StatelessWidget {
  const _PeekActionButton({
    required this.action,
    required this.animation,
    required this.reduced,
    required this.arcOffset,
    required this.delay,
  });

  final _PeekAction action;
  final Animation<double> animation;
  final bool reduced;
  final double arcOffset;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = action.active ? action.color : colors.textPrimary;

    final button = KPressable(
      onTap: action.onTap,
      semanticLabel: action.label,
      enforceMinTapTarget: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: Layout.tapTargetMin,
            height: Layout.tapTargetMin,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: action.active ? action.color : colors.surface3,
              border: Border.all(
                color: action.active ? action.color : colors.borderDefault,
                width: Strokes.thin,
              ),
            ),
            child: Icon(
              action.active ? action.activeIcon : action.icon,
              size: Space.s5,
              color: action.active ? colors.textOnAccent : tint,
            ),
          ),
          const SizedBox(height: Space.s15),
          Text(
            action.label,
            style: context.kt.micro.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );

    if (reduced) {
      return FadeTransition(opacity: animation, child: button);
    }

    final start = delay.clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: KCurves.overshoot),
      reverseCurve: KCurves.accelerate,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, arcOffset - (1 - curve.value) * Space.s8),
          child: Transform.scale(scale: curve.value, child: child),
        ),
      ),
      child: button,
    );
  }
}
