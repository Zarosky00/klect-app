import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/feedback/interaction_feedback.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import 'k_avatar.dart';
import 'k_blurhash_image.dart';
import 'k_pressable.dart';

/// One action offered inside a [NotificationBannerData] — follow back, accept a
/// call, decline a call.
///
/// [onActivate] owns the work; the banner leaves once it completes, showing
/// [confirmedLabel] in place of [label] first where one is supplied. A failure
/// keeps the banner up and restarts its dwell period, so the user can retry.
@immutable
class NotificationBannerAction {
  /// Creates an action.
  const NotificationBannerAction({
    required this.label,
    required this.semanticLabel,
    required this.onActivate,
    this.confirmedLabel,
  });

  /// Rendered copy — "Follow back", "Accept", "Decline".
  final String label;

  /// What a screen reader announces.
  final String semanticLabel;

  /// The work. The banner leaves when it completes.
  final Future<void> Function() onActivate;

  /// Replaces [label] once [onActivate] succeeds — "Following".
  final String? confirmedLabel;
}

/// Everything the banner needs, resolved *before* the overlay is inserted.
///
/// Replaces the loose parameter list the old `KBanner.show` carried: the
/// presenter does the resolving (actor, copy, glyph, thumbnail) and the banner
/// does nothing but render and animate, so nothing inside the overlay can go
/// looking for data mid-flight.
@immutable
class NotificationBannerData {
  /// Creates a view model.
  const NotificationBannerData({
    required this.notificationId,
    required this.title,
    required this.message,
    required this.glyph,
    required this.glyphTint,
    this.avatarUrl,
    this.avatarLabel,
    this.thumbUrl,
    this.thumbBlurhash,
    this.actions = const <NotificationBannerAction>[],
    this.onTap,
    this.compact = false,
  });

  /// The `notifications` row id, used by the presenter for dedupe.
  final String notificationId;

  /// One line, ellipsised beyond it.
  final String title;

  /// At most two lines, ellipsised beyond them.
  final String message;

  /// The category glyph badged onto the avatar.
  final IconData glyph;

  /// The category's action colour, or the accent fallback.
  final Color glyphTint;

  /// Absolute avatar URL; absent or unloadable falls back to [avatarLabel].
  final String? avatarUrl;

  /// Actor label the initials placeholder is built from.
  final String? avatarLabel;

  /// Square entity thumbnail.
  final String? thumbUrl;

  /// Blurhash rendered until [thumbUrl] decodes.
  final String? thumbBlurhash;

  /// Follow-back / accept / decline, rendered under the message line.
  final List<NotificationBannerAction> actions;

  /// Deep-links to the thing the notification is about.
  final VoidCallback? onTap;

  /// Uses the shared minimal follow-feedback presentation.
  final bool compact;

  /// True where a thumbnail area should be reserved at all.
  bool get hasThumb => thumbUrl != null || thumbBlurhash != null;
}

/// Rendered card width for an [availableWidth], derived rather than assumed.
///
/// The card is clamped to [Layout.readableMaxWidth] and falls back to the
/// available width minus a [Space.s3] gutter on each side below that
/// (Requirement 1.9). Never negative, however narrow the viewport gets.
double notificationBannerCardWidth(double availableWidth) {
  const gutters = Space.s3 * 2;
  final fitted = math.min(Layout.readableMaxWidth, availableWidth - gutters);
  return fitted < 0 ? 0 : fitted;
}

/// Where the card sits, measured from the top of the overlay.
///
/// Below the status-bar/notch inset by one [Space.s2] (Requirement 1.9).
double notificationBannerTopOffset(double statusBarInset) =>
    statusBarInset + Space.s2;

/// The finger-driven translation for a run of vertical drag [deltas].
///
/// A 1:1 follow clamped to `[-Drags.bannerLimit, 0]`: the banner never travels
/// further up than the token drag limit and never below its rest position
/// (Requirement 2.2).
double notificationBannerDragTranslation(Iterable<double> deltas) {
  var offset = 0.0;
  for (final delta in deltas) {
    offset = (offset + delta).clamp(-Drags.bannerLimit, 0.0);
  }
  return offset;
}

/// Whether a released drag commits to a dismissal.
///
/// True on an upward release velocity of at least [Drags.flingVelocityMin] or
/// an upward translation of at least [Drags.commitFraction] of the *measured*
/// [cardHeight]; false otherwise, in which case the banner returns to rest and
/// restarts its dwell from full (Requirements 2.3, 2.4).
bool notificationBannerDragCommits({
  required double translation,
  required double velocity,
  required double cardHeight,
}) {
  if (velocity <= -Drags.flingVelocityMin) return true;
  if (cardHeight <= 0) return false;
  return -translation >= cardHeight * Drags.commitFraction;
}

/// A transient top-edge banner for things that happen *while you are looking
/// elsewhere* — a like landing, a message arriving.
///
/// Same [Overlay] strategy as `KToast` (survives route changes, never shifts
/// layout) but anchored to the top edge under the status bar, dressed as
/// floating glass chrome: avatar + verb + entity thumb. Tap deep-links to the
/// thing itself; swipe up or the ✕ dismisses; otherwise it leaves by itself
/// after [Dwell.banner].
///
/// Exactly one entry is ever mounted. A notification arriving while an entry is
/// up — including while it is animating in or out — is *dropped*, never queued:
/// the Alert Center already has it (Requirements 2.8, 2.9).
abstract final class KNotificationBanner {
  static OverlayEntry? _current;
  static final GlobalKey<_KNotificationBannerHostState> _hostKey =
      GlobalKey<_KNotificationBannerHostState>();

  /// True while an entry is mounted, enter or exit animation included.
  static bool get isMounted => _current != null;

  /// Shows [data].
  ///
  /// Returns false — and renders nothing — when an entry is already mounted or
  /// an exit animation is still in flight, or when no root overlay is reachable
  /// from [context].
  static bool show(BuildContext context, NotificationBannerData data) {
    if (_current != null) return false;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;

    final entry = OverlayEntry(
      builder: (_) => _KNotificationBannerHost(
        key: _hostKey,
        data: data,
        onDismiss: dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
    return true;
  }

  /// Animates the current banner out, if any, then removes the entry.
  static void dismiss() {
    final host = _hostKey.currentState;
    if (host == null) {
      _removeNow();
      return;
    }
    // A second dismiss while the exit is running would remove the entry
    // mid-animation; the in-flight leave already owns the removal.
    if (host._leaving) return;
    unawaited(host._leave().then((_) => _removeNow()));
  }

  static void _removeNow() {
    _current?.remove();
    _current = null;
  }

  /// Test-only: forgets the tracked entry so one test's overlay cannot leak
  /// into the next.
  @visibleForTesting
  static void debugClear() {
    if (_current?.mounted ?? false) _current!.remove();
    _current = null;
  }
}

class _KNotificationBannerHost extends StatefulWidget {
  const _KNotificationBannerHost({
    required this.data,
    required this.onDismiss,
    super.key,
  });

  final NotificationBannerData data;
  final VoidCallback onDismiss;

  @override
  State<_KNotificationBannerHost> createState() =>
      _KNotificationBannerHostState();
}

class _KNotificationBannerHostState extends State<_KNotificationBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.medium,
    reverseDuration: KDurations.fast,
  );

  /// Measures the rendered card, so the 40 % commit threshold is taken from
  /// what is on screen rather than from a guessed height.
  final GlobalKey _cardKey = GlobalKey();

  /// Finger-driven vertical offset while dragging; only ever ≤ 0.
  double _dragOffset = 0;
  bool _dragging = false;
  bool _leaving = false;
  bool _entered = false;
  Timer? _dwellTimer;
  int? _busyAction;
  final Set<int> _confirmed = <int>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion removes the travel, not the confirmation: both directions
    // collapse to a 90ms opacity fade (Requirement 2.7).
    final reduced = KMotion.reduced(context);
    _controller
      ..duration = reduced ? KDurations.instant : KDurations.medium
      ..reverseDuration = reduced ? KDurations.instant : KDurations.fast;
    if (!_entered) {
      _entered = true;
      unawaited(_enter());
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Enters, then starts the dwell — the 5 s is measured from the moment the
  /// banner is fully on screen (Requirement 2.5).
  Future<void> _enter() async {
    try {
      await _controller.forward();
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    _restartDwell();
  }

  void _restartDwell() {
    _dwellTimer?.cancel();
    if (_leaving) return;
    _dwellTimer = Timer(Dwell.banner, widget.onDismiss);
  }

  void _suspendDwell() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
  }

  /// Runs the exit motion; the caller removes the entry afterwards.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _suspendDwell();
    try {
      await _controller.reverse();
    } on TickerCanceled {
      // Disposed mid-flight; the entry is being removed anyway.
    }
  }

  double get _cardHeight {
    final size = _cardKey.currentContext?.size;
    return size?.height ?? 0;
  }

  void _onDragStart(DragStartDetails details) {
    if (_leaving) return;
    // The dwell is suspended for the whole drag (Requirement 2.2).
    _suspendDwell();
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_leaving) return;
    setState(() {
      _dragOffset = notificationBannerDragTranslation(<double>[
        _dragOffset,
        details.delta.dy,
      ]);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_leaving) return;
    final commits = notificationBannerDragCommits(
      translation: _dragOffset,
      velocity: details.primaryVelocity ?? 0,
      cardHeight: _cardHeight,
    );
    if (commits) {
      setState(() => _dragging = false);
      widget.onDismiss();
      return;
    }
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
    // Returning to rest earns a full dwell again (Requirement 2.4).
    _restartDwell();
  }

  void _onTap() {
    // One activation, one effect: a card tap while an action is in flight would
    // navigate on top of the work the action is doing.
    if (_leaving || _busyAction != null) return;
    final onTap = widget.data.onTap;
    if (onTap == null) return;
    triggerInteractionTapFeedback(context);
    onTap();
    widget.onDismiss();
  }

  Future<void> _activate(int index, NotificationBannerAction action) async {
    if (_leaving || _busyAction != null) return;
    _suspendDwell();
    setState(() => _busyAction = index);
    try {
      await action.onActivate();
    } on Object {
      // Keep the banner up so the action can be retried.
      if (!mounted) return;
      setState(() => _busyAction = null);
      _restartDwell();
      return;
    }
    if (!mounted) return;
    setState(() {
      _busyAction = null;
      if (action.confirmedLabel != null) _confirmed.add(index);
    });
    widget.onDismiss();
  }

  /// Splits digit runs onto the tabular-figure style so a count never changes
  /// glyph width as it changes value (Requirement 1.7).
  List<InlineSpan> _tabularSpans(String text, TextStyle base) {
    final tabular = base.copyWith(fontFeatures: context.kt.count.fontFeatures);
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var bufferIsDigits = false;
    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: bufferIsDigits ? tabular : base,
        ),
      );
      buffer.clear();
    }

    for (final rune in text.characters) {
      final isDigit =
          rune.length == 1 &&
          rune.codeUnitAt(0) >= 0x30 &&
          rune.codeUnitAt(0) <= 0x39;
      if (isDigit != bufferIsDigits) {
        flush();
        bufferIsDigits = isDigit;
      }
      buffer.write(rune);
    }
    flush();
    return spans;
  }

  Widget _line(String text, TextStyle style, int maxLines) => Text.rich(
    TextSpan(children: _tabularSpans(text, style)),
    style: style.copyWith(decoration: TextDecoration.none),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );

  Widget _compactLine(NotificationBannerData data, Color foreground) =>
      Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              children: _tabularSpans(
                data.title,
                context.kt.bodyStrong.copyWith(
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              children: _tabularSpans(
                data.message,
                context.kt.body.copyWith(
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final data = widget.data;
    final reduced = KMotion.reduced(context);
    final scheme = Theme.of(context).colorScheme;

    final curved = CurvedAnimation(
      parent: _controller,
      curve: reduced ? Curves_.linear : Curves_.emphasized,
      reverseCurve: reduced ? Curves_.linear : Curves_.accelerate,
    );

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
        child: Container(
          padding: data.compact
              ? const EdgeInsets.symmetric(
                  horizontal: Space.s3,
                  vertical: Space.s2,
                )
              : const EdgeInsets.fromLTRB(
                  Space.s3,
                  Space.s3,
                  Space.s2,
                  Space.s3,
                ),
          decoration: BoxDecoration(
            color: data.compact ? scheme.inverseSurface : colors.surfaceGlass,
            borderRadius: BorderRadius.circular(
              data.compact ? Radii.xl : Radii.lg,
            ),
            border: Border.all(
              color: data.compact ? Colors.transparent : colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (data.compact) ...<Widget>[
                KAvatar(
                  imageUrl: data.avatarUrl,
                  name: data.avatarLabel ?? data.title,
                  size: Space.s10,
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _compactLine(data, scheme.onInverseSurface),
                      if (data.actions.length > 1) ...<Widget>[
                        const SizedBox(height: Space.s2),
                        Wrap(
                          spacing: Space.s2,
                          runSpacing: Space.s1,
                          children: <Widget>[
                            for (final (index, action) in data.actions.indexed)
                              _BannerActionButton(
                                action: action,
                                confirmed: _confirmed.contains(index),
                                enabled: !_leaving && _busyAction == null,
                                onActivate: () =>
                                    unawaited(_activate(index, action)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (data.actions.length == 1) ...<Widget>[
                  const SizedBox(width: Space.s2),
                  _BannerActionButton(
                    action: data.actions.single,
                    confirmed: _confirmed.contains(0),
                    enabled: !_leaving && _busyAction == null,
                    onActivate: () =>
                        unawaited(_activate(0, data.actions.single)),
                  ),
                ],
              ],
              if (!data.compact) ...<Widget>[
                // 1 — actor avatar, category glyph badged on it.
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    KAvatar(
                      imageUrl: data.avatarUrl,
                      name: data.avatarLabel ?? data.title,
                      size: Space.s10,
                    ),
                    Positioned(
                      right: -Space.s1,
                      bottom: -Space.s1,
                      child: Container(
                        padding: const EdgeInsets.all(Space.s05),
                        decoration: BoxDecoration(
                          color: colors.surface3,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          data.glyph,
                          size: Space.s3,
                          color: data.glyphTint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: Space.s3),
                // 2 — title, message, actions.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _line(data.title, context.kt.bodyStrong, 1),
                      const SizedBox(height: Space.s05),
                      _line(
                        data.message,
                        context.kt.callout.copyWith(
                          color: colors.textSecondary,
                        ),
                        2,
                      ),
                      if (data.actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Space.s2),
                        Wrap(
                          spacing: Space.s2,
                          runSpacing: Space.s1,
                          children: <Widget>[
                            for (final (index, action) in data.actions.indexed)
                              _BannerActionButton(
                                action: action,
                                confirmed: _confirmed.contains(index),
                                enabled: !_leaving && _busyAction == null,
                                onActivate: () =>
                                    unawaited(_activate(index, action)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // 3 — optional square entity thumb.
                if (data.hasThumb) ...<Widget>[
                  const SizedBox(width: Space.s3),
                  SizedBox(
                    width: Space.s10,
                    height: Space.s10,
                    child: KBlurhashImage(
                      url: data.thumbUrl,
                      blurhash: data.thumbBlurhash,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                  ),
                ],
                // 4 — dismiss.
                const SizedBox(width: Space.s1),
                KPressable(
                  semanticLabel: 'Dismiss',
                  onTap: _leaving ? null : widget.onDismiss,
                  child: Icon(
                    Icons.close_rounded,
                    size: Space.s4,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: data.onTap == null ? null : _onTap,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: DecoratedBox(
        key: _cardKey,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: KlectTheme.shadow(Elevation.mid),
        ),
        child: card,
      ),
    );

    final animated = FadeTransition(
      opacity: curved,
      child: reduced
          ? interactive
          : SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(curved),
              child: interactive,
            ),
    );

    return Positioned(
      // Under the status bar / notch, riding the top edge.
      top: notificationBannerTopOffset(MediaQuery.viewPaddingOf(context).top),
      left: 0,
      right: 0,
      child: Semantics(
        liveRegion: true,
        label: '${data.title} ${data.message}',
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SizedBox(
              width: notificationBannerCardWidth(constraints.maxWidth),
              // Zero while the finger is down so the follow is exactly 1:1;
              // a settle back to rest once it lifts (Requirement 2.4).
              child: AnimatedContainer(
                duration: _dragging
                    ? Duration.zero
                    : KMotion.duration(context, KDurations.base),
                curve: Curves_.emphasized,
                transform: Matrix4.translationValues(0, _dragOffset, 0),
                child: animated,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerActionButton extends StatelessWidget {
  const _BannerActionButton({
    required this.action,
    required this.confirmed,
    required this.enabled,
    required this.onActivate,
  });

  final NotificationBannerAction action;
  final bool confirmed;
  final bool enabled;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final label = confirmed
        ? (action.confirmedLabel ?? action.label)
        : action.label;
    return KPressable(
      semanticLabel: action.semanticLabel,
      enabled: enabled && !confirmed,
      onTap: onActivate,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s3,
          vertical: Space.s1,
        ),
        decoration: BoxDecoration(
          color: confirmed ? colors.surface3 : colors.accentDefault,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Text(
          label,
          style: context.kt.micro.copyWith(
            color: confirmed ? colors.textSecondary : colors.textOnAccent,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
