import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'data/closeup_providers.dart';
import 'widgets/surf_tile.dart';

/// One photo, with its URL already resolved.
class _Shot {
  const _Shot(this.media, this.url);

  final ImmersiveMedia media;
  final String url;
}

/// **Immersive** — the double-tap destination.
///
/// Fullscreen, always dark, always the photograph: pinch to zoom, pan when
/// zoomed, swipe between every image in the set, and swipe down to dismiss
/// with the picture tracking the finger. Chrome auto-hides after two seconds
/// and returns on a tap.
///
/// Screen readers get "Photo 2 of 5" plus the image's `alt_text` on open and
/// on every page change, which is the accessibility floor from
/// `docs/DESIGN_SYSTEM.md` §6.
class ImmersiveScreen extends ConsumerStatefulWidget {
  /// Creates the viewer.
  const ImmersiveScreen({
    required this.entityType,
    required this.entityId,
    this.initialIndex = 0,
    super.key,
  });

  /// Which entity's photos to show.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  /// Which photo to open on.
  final int initialIndex;

  @override
  ConsumerState<ImmersiveScreen> createState() => _ImmersiveScreenState();
}

class _ImmersiveScreenState extends ConsumerState<ImmersiveScreen>
    with SingleTickerProviderStateMixin {
  /// How long chrome stays before it fades out. A dwell time from the design
  /// spec ("chrome auto-hides after 2s"), not a motion token.
  static const Duration _chromeDwell = Duration(seconds: 2);

  /// Fraction of the screen a drag must cover to dismiss on release.
  static const double _dismissFraction = 0.18;

  /// Fling speed (logical px/s) that dismisses regardless of travel.
  static const double _flingVelocity = 700;

  /// How much the photo shrinks at the point of dismissal.
  static const double _dismissScale = 0.25;

  /// The viewer is a dark room whatever the rest of the app is doing, so the
  /// whole subtree runs on the dark token set. Built once — `ThemeData` is not
  /// cheap and the chrome rebuilds on every page change.
  static final ThemeData _darkTheme = KlectThemeData.dark();

  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late final AnimationController _drag =
      AnimationController.unbounded(vsync: this);

  Timer? _chromeTimer;
  bool _chromeVisible = true;
  bool _chromeWasVisible = true;
  bool _closing = false;
  bool _announcedFirst = false;
  int _index = 0;

  EntityRef get _entity => EntityRef(widget.entityType, widget.entityId);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
    _restartChromeTimer();
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _drag.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _restartChromeTimer() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(_chromeDwell, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _showChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _restartChromeTimer();
  }

  void _hideChrome() {
    _chromeTimer?.cancel();
    if (_chromeVisible) setState(() => _chromeVisible = false);
  }

  void _announce(int index, int total, String? alt) {
    if (!mounted) return;
    final label = alt == null || alt.isEmpty
        ? 'Photo ${index + 1} of $total'
        : 'Photo ${index + 1} of $total. $alt';
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        label,
        Directionality.of(context),
      ),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _drag.value += details.delta.dy;
    _hideChrome();
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final height = MediaQuery.sizeOf(context).height;
    if (_drag.value.abs() > height * _dismissFraction ||
        velocity.abs() > _flingVelocity) {
      _close();
      return;
    }
    // Velocity carry: the photo keeps the finger's momentum into the spring.
    _drag.animateWith(
      SpringSimulation(
        KMotion.spring(Springs.sheet),
        _drag.value,
        0,
        velocity,
      ),
    );
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/surf');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: _darkTheme,
        child: Builder(builder: _buildScaffold),
      );

  Widget _buildScaffold(BuildContext context) {
    final async = ref.watch(closeupProvider(_entity));
    final closeup = async.value;
    final api = ref.watch(klectApiProvider);

    // Post photos live in post_media (0018), outside the closeup payload.
    final postMedia = widget.entityType == EntityType.post
        ? ref.watch(postMediaProvider(widget.entityId)).value
        : null;
    final shots = <_Shot>[
      if (closeup != null)
        for (final photo in widget.entityType == EntityType.post
            ? (postMedia ?? const <ImmersiveMedia>[])
            : immersiveMediaOf(closeup))
          if (api.publicUrl(photo.path) case final String url)
            _Shot(photo, url),
    ];

    return Scaffold(
      backgroundColor: context.kc.bgSunken,
      body: closeup == null
          ? (async.hasError
              ? KErrorState(
                  error: async.error,
                  onRetry: () => ref.invalidate(closeupProvider(_entity)),
                )
              : Center(
                  child: SizedBox(
                    width: Space.s8,
                    height: Space.s8,
                    child: CircularProgressIndicator(
                      strokeWidth: Strokes.thick,
                      color: context.kc.accentDefault,
                    ),
                  ),
                ))
          : shots.isEmpty
              ? KEmptyState(
                  title: 'Nothing to show',
                  message: '${closeup.title} has no photos yet.',
                  icon: Icons.image_not_supported_outlined,
                  actionLabel: 'Back',
                  onAction: _close,
                )
              : _viewer(context, closeup, shots),
    );
  }

  Widget _viewer(BuildContext context, Closeup closeup, List<_Shot> shots) {
    final total = shots.length;
    final index = _index.clamp(0, total - 1);
    final current = shots[index];

    if (!_announcedFirst) {
      _announcedFirst = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _announce(index, total, current.media.altText),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Listener(
          // A raw pointer listener never joins the gesture arena, so chrome
          // reappears on touch-down with zero delay even though photo_view
          // owns a double-tap recogniser underneath.
          onPointerDown: (_) {
            _chromeWasVisible = _chromeVisible;
            _showChrome();
          },
          child: GestureDetector(
            // photo_view's gallery scopes its own recogniser to the horizontal
            // axis, so a single-pointer *vertical* drag on an unzoomed photo
            // falls through to here — which is exactly the dismiss gesture.
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _drag,
              builder: (context, child) {
                final height = MediaQuery.sizeOf(context).height;
                final progress = height <= 0
                    ? 0.0
                    : (_drag.value.abs() / height).clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(0, _drag.value),
                  child: Transform.scale(
                    scale: 1 - progress * _dismissScale,
                    child: child,
                  ),
                );
              },
              child: PhotoViewGallery.builder(
                itemCount: total,
                pageController: _pages,
                backgroundDecoration:
                    BoxDecoration(color: context.kc.bgSunken),
                onPageChanged: (next) {
                  setState(() => _index = next);
                  _announce(next, total, shots[next].media.altText);
                  _showChrome();
                },
                loadingBuilder: (context, event) =>
                    _Placeholder(blurhash: current.media.blurhash),
                builder: (context, position) {
                  final shot = shots[position];
                  return PhotoViewGalleryPageOptions(
                    imageProvider: CachedNetworkImageProvider(shot.url),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: shot.media.altText,
                    heroAttributes: position == 0
                        ? PhotoViewHeroAttributes(
                            tag: surfCoverHeroTag(
                              widget.entityType,
                              widget.entityId,
                            ),
                          )
                        : null,
                    onTapUp: (tapContext, details, value) {
                      if (_chromeWasVisible) {
                        _hideChrome();
                      } else {
                        _showChrome();
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
        _Chrome(
          visible: _chromeVisible,
          entity: _entity,
          title: closeup.title,
          index: index,
          total: total,
          altText: current.media.altText,
          onClose: _close,
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.blurhash});

  final String? blurhash;

  @override
  Widget build(BuildContext context) {
    final hash = blurhash;
    if (hash == null || hash.length < 6) return const SizedBox.expand();
    return Image(
      image: BlurHashImage(hash),
      fit: BoxFit.contain,
      errorBuilder: (context, _, _) => const SizedBox.expand(),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.entity,
    required this.title,
    required this.index,
    required this.total,
    required this.altText,
    required this.onClose,
  });

  final bool visible;
  final EntityRef entity;
  final String title;
  final int index;
  final int total;
  final String? altText;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final padding = MediaQuery.paddingOf(context);
    final alt = altText;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: KMotion.duration(context, KDurations.fast),
        curve: KCurves.standard,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  Space.s4,
                  padding.top + Space.s2,
                  Space.s4,
                  Space.s3,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      colors.surfaceScrim,
                      colors.surfaceScrim.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    KIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Close',
                      color: colors.textPrimary,
                      onPressed: onClose,
                    ),
                    const Spacer(),
                    Text(
                      '${index + 1} of $total',
                      style: text.count.copyWith(color: colors.textPrimary),
                    ),
                    const Spacer(),
                    const SizedBox(width: Layout.tapTargetMin),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  Space.s5,
                  Space.s6,
                  Space.s5,
                  padding.bottom + Space.s5,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      colors.surfaceScrim,
                      colors.surfaceScrim.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.title3,
                    ),
                    if (alt != null && alt.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Space.s1),
                      Text(
                        alt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            text.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Space.s3),
                    KActionBar(entity: entity, live: true, shareTitle: title),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
