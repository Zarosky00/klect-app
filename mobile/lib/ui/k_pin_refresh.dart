import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings.dart';
import '../design/motion.dart';
import '../design/theme.dart';

/// Pull-to-refresh for the two feeds, in the manner of Pinterest's home feed.
///
/// Instead of a spinner disc dropping over the content, the feed itself is
/// pulled down on a rubber band and three dots grow out of the gap above it:
///
///  * **pulling**: the dots emerge from one point and spread into a triangle
///    as the feed comes down, turning a third of a turn on the way. Crossing
///    the threshold completes the triangle (and ticks, if haptics are on);
///  * **refreshing**: the feed springs to a resting gap and the triangle
///    spins, each dot breathing in turn while the colour cycles;
///  * **done**: the dots shrink away and the feed glides back up.
///
/// The dot geometry and the spin/breath/colour ratios follow Pinterest's
/// open-source Gestalt spinner. Every size, colour and duration is a Klect
/// token.
///
/// Wrap the scrolling feed area only, not the tabs above it. Any vertical
/// scrollable underneath can drive it, so a pager of lists works. Give those
/// lists [physics], so the top edge reports the pull and empty or error
/// states can be pulled too.
class KPinRefresh extends ConsumerStatefulWidget {
  /// Wraps [child] in the pull.
  const KPinRefresh({
    required this.onRefresh,
    required this.label,
    required this.child,
    super.key,
    this.busy = false,
  });

  /// Reloads the feed. The dots stay until it completes.
  final Future<void> Function() onRefresh;

  /// What is being refreshed, for screen readers, e.g. `Surf`.
  final String label;

  /// The feed.
  final Widget child;

  /// Whether a refresh started somewhere else (e.g. a tab double tap), so the
  /// same dots show for it.
  final bool busy;

  /// Scroll physics for the feed's lists: clamp at the edges on every
  /// platform, so the pull moves the whole feed instead of bouncing the list,
  /// and always accept a drag, even when the content is shorter than the
  /// viewport.
  static const ScrollPhysics physics = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  @override
  ConsumerState<KPinRefresh> createState() => _KPinRefreshState();
}

enum _Mode { idle, pulling, armed, refreshing, done }

class _KPinRefreshState extends ConsumerState<KPinRefresh>
    with TickerProviderStateMixin {
  /// The spinner's box. Gestalt's small spinner is 32.
  static const double _size = Space.s8;

  /// How far the feed must come down before a release refreshes.
  static const double _trigger = Space.s20;

  /// The gap the feed rests at while the refresh runs.
  static const double _hold = Space.s16;

  /// The rubber band's reach: the feed approaches this but never passes it.
  static const double _reach = Space.s24 + Space.s8;

  /// The shortest time the dots spin, so a cache-fast reload still reads as
  /// a refresh instead of a flicker.
  static const Duration _minimumSpin = KDurations.deliberate;

  late final AnimationController _offset;
  late final AnimationController _intro;
  late final AnimationController _outro;
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  _Mode _mode = _Mode.idle;
  double _drag = 0;
  bool _external = false;
  final Stopwatch _spun = Stopwatch();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController.unbounded(vsync: this);
    _intro = AnimationController(vsync: this, duration: KDurations.slow);
    _outro = AnimationController(vsync: this, duration: KDurations.base);
    _ticker = createTicker(
      (elapsed) => _clock.value =
          elapsed.inMicroseconds / Duration.microsecondsPerSecond,
    );
  }

  @override
  void didUpdateWidget(KPinRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    final started = !oldWidget.busy && widget.busy;
    final ended = oldWidget.busy && !widget.busy;
    if (!started && !ended) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (started && _mode == _Mode.idle) {
        _external = true;
        _startRefresh(fromPull: false);
      } else if (ended && _external && _mode == _Mode.refreshing) {
        unawaited(_finish());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticker.dispose();
    _offset.dispose();
    _intro.dispose();
    _outro.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _setMode(_Mode mode) {
    if (_mode == mode || !mounted) return;
    setState(() => _mode = mode);
  }

  // ── The pull ─────────────────────────────────────────────────────────────

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    switch (_mode) {
      case _Mode.refreshing:
      case _Mode.done:
        return false;
      case _Mode.idle:
        if (notification is OverscrollNotification &&
            notification.dragDetails != null &&
            notification.overscroll < 0 &&
            notification.metrics.extentBefore == 0) {
          _offset.stop();
          _intro.stop();
          _drag = 0;
          _setMode(_Mode.pulling);
          _pull(-notification.overscroll);
        }
      case _Mode.pulling:
      case _Mode.armed:
        if (notification is OverscrollNotification) {
          if (notification.dragDetails != null && notification.overscroll < 0) {
            _pull(-notification.overscroll);
          }
        } else if (notification is ScrollUpdateNotification) {
          if (notification.dragDetails == null) {
            _release();
          } else if ((notification.scrollDelta ?? 0) > 0) {
            // Pushing back up gives the gap back before the list scrolls on.
            _pull(-notification.scrollDelta!);
          }
        } else if (notification is ScrollEndNotification) {
          _release();
        }
    }
    return false;
  }

  void _pull(double delta) {
    _drag = math.max(0, _drag + delta);
    final offset = _reach * (1 - math.exp(-_drag / _reach));
    _offset.value = offset;
    _intro.value = (offset / _trigger).clamp(0.0, 1.0);
    if (offset >= _trigger && _mode == _Mode.pulling) {
      _setMode(_Mode.armed);
      _tick();
    } else if (offset < _trigger && _mode == _Mode.armed) {
      _setMode(_Mode.pulling);
    }
  }

  void _tick() {
    if (!ref.read(appSettingsProvider).hapticsEnabled) return;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  }

  void _release() {
    if (_mode == _Mode.armed) {
      _startRefresh(fromPull: true);
      return;
    }
    _drag = 0;
    _setMode(_Mode.idle);
    // The finger let go: the feed returns on a spring.
    _spring(0, Springs.gentle);
    unawaited(
      _intro.animateTo(
        0,
        duration: KMotion.duration(context, KDurations.base),
        curve: KMotion.curve(context, KCurves.standard),
      ),
    );
  }

  // ── The refresh ──────────────────────────────────────────────────────────

  void _startRefresh({required bool fromPull}) {
    _drag = 0;
    _setMode(_Mode.refreshing);
    _outro.value = 0;
    _clock.value = 0;
    _spun
      ..reset()
      ..start();
    if (!_ticker.isActive) unawaited(_ticker.start());
    if (fromPull) {
      _spring(_hold, Springs.snappy);
    } else {
      unawaited(
        _offset.animateTo(
          _hold,
          duration: KMotion.duration(context, KDurations.medium),
          curve: KMotion.curve(context, KCurves.emphasized),
        ),
      );
    }
    unawaited(
      _intro.animateTo(
        1,
        duration: KMotion.duration(context, KDurations.slow),
        curve: KMotion.curve(context, KCurves.emphasized),
      ),
    );
    if (!fromPull) return;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await widget.onRefresh();
    } on Object {
      // The feed shows its own error state; the dots only need to stop.
    }
    await _finish();
  }

  Future<void> _finish() async {
    final remaining = _minimumSpin - _spun.elapsed;
    if (remaining > Duration.zero) {
      final wait = Completer<void>();
      _timer = Timer(remaining, wait.complete);
      await wait.future;
    }
    if (!mounted) return;
    _external = false;
    _setMode(_Mode.done);
    await _outro.animateTo(
      1,
      duration: KMotion.duration(context, KDurations.base),
      curve: KMotion.curve(context, KCurves.accelerate),
    );
    if (!mounted) return;
    await _offset.animateTo(
      0,
      duration: KMotion.duration(context, KDurations.medium),
      curve: KMotion.curve(context, KCurves.emphasized),
    );
    if (!mounted) return;
    _ticker.stop();
    _spun.stop();
    _intro.value = 0;
    _outro.value = 0;
    _setMode(_Mode.idle);
  }

  void _spring(double target, SpringSpec spec) {
    if (KMotion.reduced(context)) {
      _offset.value = target;
      return;
    }
    unawaited(
      _offset.animateWith(
        SpringSimulation(KMotion.spring(spec), _offset.value, target, 0),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final reduced = KMotion.reduced(context);
    final spinning = _mode == _Mode.refreshing || _mode == _Mode.done;

    return NotificationListener<OverscrollIndicatorNotification>(
      // The feed itself moves on a pull, so Android's stretch or glow at the
      // top edge would be a second, competing response.
      onNotification: (notification) {
        if (notification.leading) notification.disallowIndicator();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _layers(context, colors, reduced, spinning),
      ),
    );
  }

  Widget _layers(
    BuildContext context,
    KlectColors colors,
    bool reduced,
    bool spinning,
  ) {
    return ClipRect(
      child: Stack(
        children: <Widget>[
          AnimatedBuilder(
            animation: _offset,
            child: widget.child,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, math.max(0, _offset.value)),
              child: child,
            ),
          ),
          AnimatedBuilder(
            animation: _offset,
            builder: (context, child) {
              final gap = math.max(0.0, _offset.value);
              return Positioned(
                top: (gap - _size) / 2,
                left: 0,
                right: 0,
                height: _size,
                child: gap <= 0 ? const SizedBox.shrink() : child!,
              );
            },
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                label: spinning ? 'Refreshing ${widget.label}' : null,
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(_size),
                    painter: _DotsPainter(
                      repaint: Listenable.merge(<Listenable>[
                        _clock,
                        _intro,
                        _outro,
                      ]),
                      clock: _clock,
                      intro: _intro,
                      outro: _outro,
                      spinning: spinning,
                      reduced: reduced,
                      palette: <Color>[
                        colors.accentHover,
                        colors.textPrimary,
                        colors.textTertiary,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots in a triangle, after Pinterest's Gestalt spinner (a 56-unit
/// box with dots of radius 8 at (28,12), (14,36) and (42,36)).
class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required Listenable repaint,
    required this.clock,
    required this.intro,
    required this.outro,
    required this.spinning,
    required this.reduced,
    required this.palette,
  }) : super(repaint: repaint);

  final ValueListenable<double> clock;
  final Animation<double> intro;
  final Animation<double> outro;
  final bool spinning;
  final bool reduced;
  final List<Color> palette;

  /// Gestalt's box, and each dot's centre relative to the box centre.
  static const double _box = 56;
  static const double _radius = 8;
  static const List<Offset> _dots = <Offset>[
    Offset(0, -16),
    Offset(-14, 8),
    Offset(14, 8),
  ];

  /// One revolution in seconds. A looping indicator is not a transition, so
  /// this is two deliberate beats rather than one (Gestalt uses about 1s).
  static final double _revolution =
      (KDurations.deliberate * 2).inMicroseconds /
      Duration.microsecondsPerSecond;

  /// Gestalt's ratios to the spin: each dot breathes at 0.8 of a revolution,
  /// staggered by an eighth, and the colour cycles at 1.8.
  static final double _breath = _revolution * 0.8;
  static final double _cycle = _revolution * 1.8;

  /// The pull turns the triangle a third of a turn, which maps it onto
  /// itself, so the spin starts from the same pose.
  static const double _pullTurn = 2 * math.pi / 3;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / _box;
    final t = clock.value;
    final grow = intro.value;
    final shrink = 1 - outro.value;
    if (grow <= 0 || shrink <= 0) return;

    final spin = spinning && !reduced ? t / _revolution * 2 * math.pi : 0.0;
    final rotation = _pullTurn * Curves_.decelerate.transform(grow) + spin;
    final colour = spinning ? _colourAt(t) : palette.first;

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(rotation);
    for (var i = 0; i < _dots.length; i++) {
      // Each dot emerges from the centre a beat after the one before it.
      final start = i * 0.2;
      final emerge = Curves_.emphasized.transform(
        ((grow - start) / (1 - start - 0.2)).clamp(0.0, 1.0),
      );
      if (emerge <= 0) continue;
      final breathe = spinning && !reduced ? _breatheAt(t, i) : 1.0;
      final scale = emerge * breathe * shrink;
      canvas.drawCircle(
        _dots[i] * unit * emerge,
        _radius * unit * scale,
        Paint()..color = colour,
      );
    }
    canvas.restore();
  }

  /// 1 → 0.666 → 1, linear, like Gestalt's `scale` keyframes.
  double _breatheAt(double t, int index) {
    final phase = ((t - index * _breath / 8) / _breath) % 1;
    return 1 - (1 - 0.666) * (1 - (2 * phase - 1).abs());
  }

  Color _colourAt(double t) {
    final phase = (t / _cycle) % 1 * palette.length;
    final from = phase.floor() % palette.length;
    final to = (from + 1) % palette.length;
    return Color.lerp(palette[from], palette[to], phase - phase.floor())!;
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.spinning != spinning ||
      old.reduced != reduced ||
      !listEquals(old.palette, palette);
}
