import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import 'k_avatar.dart';
import 'k_blurhash_image.dart';

/// A transient top-edge banner for things that happen *while you are looking
/// elsewhere* — a like landing, a message arriving.
///
/// Same [Overlay] strategy as `KToast` (survives route changes, never shifts
/// layout) but anchored to the top edge under the status bar, dressed as
/// floating glass chrome: avatar + verb + entity thumb. Tap deep-links to the
/// thing itself; swipe up or the ✕ dismisses; otherwise it leaves by itself
/// after [dwell].
abstract final class KBanner {
  /// How long the banner stays. Dwell time, not motion — deliberately not a
  /// motion token.
  static const Duration dwell = Duration(seconds: 5);

  static OverlayEntry? _current;
  static Timer? _timer;
  static final GlobalKey<_KBannerHostState> _hostKey =
      GlobalKey<_KBannerHostState>();

  /// Shows a banner. Replaces any banner already on screen.
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    String? avatarUrl,
    String? avatarName,
    IconData? icon,
    Color? iconTint,
    String? thumbUrl,
    String? thumbBlurhash,
    VoidCallback? onTap,
    Duration duration = dwell,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _removeNow();

    final entry = OverlayEntry(
      builder: (overlayContext) => _KBannerHost(
        key: _hostKey,
        title: title,
        message: message,
        avatarUrl: avatarUrl,
        avatarName: avatarName,
        icon: icon,
        iconTint: iconTint,
        thumbUrl: thumbUrl,
        thumbBlurhash: thumbBlurhash,
        onTap: onTap == null
            ? null
            : () {
                onTap();
                _removeNow();
              },
        onDismiss: dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, dismiss);
  }

  /// Animates the current banner out, if any.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    final host = _hostKey.currentState;
    if (host == null) {
      _removeNow();
      return;
    }
    unawaited(host._leave().then((_) => _removeNow()));
  }

  static void _removeNow() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _KBannerHost extends StatefulWidget {
  const _KBannerHost({
    required this.title,
    required this.message,
    required this.avatarUrl,
    required this.avatarName,
    required this.icon,
    required this.iconTint,
    required this.thumbUrl,
    required this.thumbBlurhash,
    required this.onTap,
    required this.onDismiss,
    super.key,
  });

  final String title;
  final String message;
  final String? avatarUrl;
  final String? avatarName;
  final IconData? icon;
  final Color? iconTint;
  final String? thumbUrl;
  final String? thumbBlurhash;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  State<_KBannerHost> createState() => _KBannerHostState();
}

class _KBannerHostState extends State<_KBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.medium,
    reverseDuration: KDurations.fast,
  );

  /// Finger-driven vertical offset while dragging; only ever ≤ 0.
  double _dragOffset = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Runs the exit motion; the caller removes the entry afterwards.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _controller.reverse();
    } on TickerCanceled {
      // Disposed mid-flight; the entry is being removed anyway.
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(-96.0, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -200 || _dragOffset < -Space.s6) {
      widget.onDismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final reduced = KMotion.reduced(context);

    final curved = CurvedAnimation(
      parent: _controller,
      curve: reduced ? Curves_.linear : Curves_.emphasized,
      reverseCurve: Curves_.accelerate,
    );

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.chrome, sigmaY: Blurs.chrome),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Space.s3,
            Space.s3,
            Space.s2,
            Space.s3,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceGlass,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  KAvatar(
                    imageUrl: widget.avatarUrl,
                    name: widget.avatarName ?? widget.title,
                    size: Space.s10,
                  ),
                  if (widget.icon != null)
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
                          widget.icon,
                          size: Space.s3,
                          color: widget.iconTint ?? colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: context.kt.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.s05),
                    Text(
                      widget.message,
                      style: context.kt.callout
                          .copyWith(color: colors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.thumbUrl != null ||
                  widget.thumbBlurhash != null) ...<Widget>[
                const SizedBox(width: Space.s3),
                SizedBox(
                  width: Space.s10,
                  height: Space.s10,
                  child: KBlurhashImage(
                    url: widget.thumbUrl,
                    blurhash: widget.thumbBlurhash,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                ),
              ],
              const SizedBox(width: Space.s1),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s2),
                    child: Icon(
                      Icons.close_rounded,
                      size: Space.s4,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: KlectTheme.shadow(Elevation.mid),
        ),
        child: card,
      ),
    );

    return Positioned(
      // Under the status bar / notch, riding the top edge.
      top: MediaQuery.viewPaddingOf(context).top + Space.s2,
      left: Space.s3,
      right: Space.s3,
      child: Semantics(
        liveRegion: true,
        label: '${widget.title} ${widget.message}',
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Layout.readableMaxWidth),
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: FadeTransition(
                opacity: curved,
                child: reduced
                    ? interactive
                    : SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.6),
                          end: Offset.zero,
                        ).animate(curved),
                        child: interactive,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
