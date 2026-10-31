import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../design/motion.dart';
import '../../../ui/ui.dart';
import 'peek_menu.dart';

/// **The gesture contract, as a wrapper.**
///
/// Wrap any card — a Surf tile, a Pulse attachment, a profile grid cell — in
/// this and it gets all three gestures from `docs/DESIGN_SYSTEM.md` §4 with
/// the correct feel:
///
/// | gesture | result |
/// |---|---|
/// | single tap | **Closeup**, opened on the first tap-up with no delay |
/// | double tap | **Immersive**, escalated by replacing the closeup route |
/// | long press | **Peek** — the radial like/save/repost/share/report fan |
///
/// The no-delay part is the whole point: [KGestureRegion] fires `onTap`
/// immediately and *optimistically* pushes the closeup, then escalates to the
/// immersive viewer with `pushReplacement` if a second tap lands inside the
/// window. A naive `GestureDetector(onTap:, onDoubleTap:)` would charge every
/// single tap ~260ms for the privilege, and that is what makes an app feel
/// cheap.
class KEntityGestureCard extends StatefulWidget {
  /// Wraps [child] in the gesture contract for [entity].
  const KEntityGestureCard({
    required this.entity,
    required this.child,
    super.key,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
    this.immersiveIndex = 0,
    this.enabled = true,
    this.pressFeedback = true,
    this.peekGallery = false,
    this.onOpen,
    this.onImmersive,
    this.onSettled,
  });

  /// What the card is about.
  final EntityRef entity;

  /// The card itself.
  final Widget child;

  /// Headline, used by the peek and by screen readers.
  final String? title;

  /// Secondary line shown under the peek preview.
  final String? subtitle;

  /// Already-resolved cover URL, for the peek preview.
  final String? imageUrl;

  /// Blurhash of [imageUrl].
  final String? blurhash;

  /// Cover aspect ratio, so the peek preview reserves the right box.
  final double? aspectRatio;

  /// Which photo the immersive viewer should open on.
  final int immersiveIndex;

  /// When false the card is inert.
  final bool enabled;

  /// Adds the press-scale affordance. Turn it off inside an already-pressable
  /// parent.
  final bool pressFeedback;

  /// Turns the long-press preview into a swipeable deck of every photo in
  /// the set. The holding finger can scrub it without lifting. Use it for
  /// collections, subcollections and multi-photo items.
  final bool peekGallery;

  /// Overrides "open the closeup" — e.g. a screen that shows the detail
  /// inline instead of pushing a route.
  final VoidCallback? onOpen;

  /// Overrides the immersive route transition, primarily for inline hosts.
  final VoidCallback? onImmersive;

  /// Fires when the double-tap window closes with no second tap, i.e. the
  /// single tap is now definitive.
  final VoidCallback? onSettled;

  @override
  State<KEntityGestureCard> createState() => _KEntityGestureCardState();
}

class _KEntityGestureCardState extends State<KEntityGestureCard> {
  /// Pointers currently down on the card, in arrival order.
  final List<int> _pointers = <int>[];

  /// The peek being driven by a finger that has not lifted yet.
  KPeekHold? _hold;
  int? _holdPointer;

  @override
  void dispose() {
    _endHold();
    super.dispose();
  }

  void _open() {
    final override = widget.onOpen;
    if (override != null) {
      override();
      return;
    }
    context.push(KlectLinks.closeupPath(widget.entity.type, widget.entity.id));
  }

  void _escalate() {
    final override = widget.onImmersive;
    if (override != null) {
      override();
      return;
    }
    // The closeup was already pushed by the first tap; swap it for the
    // immersive viewer so `back` returns to the grid, not to a closeup the
    // user never asked for.
    context.pushReplacement(
      '${KlectLinks.immersivePath(widget.entity.type, widget.entity.id)}'
      '?i=${widget.immersiveIndex}',
    );
  }

  void _peek() {
    final w = widget;
    if (_pointers.isEmpty) {
      // Accessibility long-press: no finger to follow, open the route.
      unawaited(
        KPeekMenu.show(
          context,
          entity: w.entity,
          title: w.title,
          subtitle: w.subtitle,
          imageUrl: w.imageUrl,
          blurhash: w.blurhash,
          aspectRatio: w.aspectRatio,
          gallery: w.peekGallery,
        ),
      );
      return;
    }
    _endHold();
    _holdPointer = _pointers.last;
    _hold = KPeekMenu.hold(
      context,
      entity: w.entity,
      title: w.title,
      subtitle: w.subtitle,
      imageUrl: w.imageUrl,
      blurhash: w.blurhash,
      aspectRatio: w.aspectRatio,
      gallery: w.peekGallery,
    );
  }

  void _endHold() {
    _hold?.release();
    _hold = null;
    _holdPointer = null;
  }

  void _pointerGone(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (event.pointer == _holdPointer) _endHold();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final content = widget.pressFeedback
        ? KPressFeedback(child: child)
        : child;
    // Raw pointer events, outside the gesture arena: once the long-press has
    // won, the same finger keeps steering the peek until it lifts.
    return Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerMove: (event) {
        if (event.pointer == _holdPointer) _hold?.move(event);
      },
      onPointerUp: _pointerGone,
      onPointerCancel: _pointerGone,
      child: KGestureRegion(
        enabled: widget.enabled,
        semanticLabel: widget.title,
        onTap: _open,
        onDoubleTap: _escalate,
        onTapSettled: widget.onSettled,
        onLongPress: _peek,
        child: content,
      ),
    );
  }
}

/// Press-scale feedback that cannot interfere with the gesture contract.
///
/// It listens to raw pointer events instead of joining the gesture arena, so
/// it never competes with the tap / double-tap / long-press resolver above it
/// or with the scrollable underneath. Movement past the touch slop cancels the
/// press, so starting a scroll on a card does not leave it stuck small.
class KPressFeedback extends StatefulWidget {
  /// Wraps [child] in press feedback.
  const KPressFeedback({required this.child, super.key});

  /// What to render.
  final Widget child;

  @override
  State<KPressFeedback> createState() => _KPressFeedbackState();
}

class _KPressFeedbackState extends State<KPressFeedback> {
  Offset? _origin;
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = KMotion.reduced(context);
    return Listener(
      onPointerDown: (event) {
        _origin = event.position;
        _set(true);
      },
      onPointerMove: (event) {
        final origin = _origin;
        if (origin == null) return;
        if ((event.position - origin).distance > kTouchSlop) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !reduced ? KMotion.pressScale : 1,
        duration: KMotion.duration(context, KDurations.fast),
        curve: KCurves.emphasized,
        child: widget.child,
      ),
    );
  }
}
