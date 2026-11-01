import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feedback/interaction_feedback.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../ui/ui.dart';
import '../../surf/surf.dart';

/// What a long press on a Pulse photo acts on: the entity that owns the
/// photo, plus the copy shown under the peek preview.
@immutable
class PulsePeekTarget {
  /// Creates a peek target.
  const PulsePeekTarget({required this.entity, this.title, this.subtitle});

  /// Like / save / repost / share / report apply to this entity.
  final EntityRef entity;

  /// Headline under the preview.
  final String? title;

  /// Secondary line under the headline.
  final String? subtitle;
}

/// Gives one Pulse photo the long-press peek.
///
/// In Pulse the peek belongs to **photographs only**. Holding a row's text,
/// byline or action bar does nothing special; holding a photo blows that
/// exact photo up with the like / save / repost / share / report fan.
///
/// Only a long-press recognizer joins the gesture arena here, so a plain tap
/// on the photo still reaches whatever row or card hosts it.
class PulsePeekableMedia extends StatelessWidget {
  /// Wraps [child] (the rendered photo) in the peek gesture.
  const PulsePeekableMedia({
    required this.peek,
    required this.child,
    super.key,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
  });

  /// What the peek acts on. Null leaves [child] inert to long presses.
  final PulsePeekTarget? peek;

  /// The photo.
  final Widget child;

  /// Resolved URL of the photo, previewed at full size in the peek.
  final String? imageUrl;

  /// Blurhash of [imageUrl].
  final String? blurhash;

  /// Intrinsic ratio, so the preview reserves the right box.
  final double? aspectRatio;

  void _open(BuildContext context, PulsePeekTarget target) {
    triggerInteractionTapFeedback(context);
    unawaited(
      KPeekMenu.show(
        context,
        entity: target.entity,
        title: target.title,
        subtitle: target.subtitle,
        imageUrl: imageUrl,
        blurhash: blurhash,
        aspectRatio: aspectRatio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = peek;
    if (target == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _open(context, target),
      child: child,
    );
  }
}

/// A Surf collection, shelf or thing embedded in a Pulse row.
///
/// The card is its own target inside the row: a tap opens the entity's Surf
/// closeup and a double tap escalates to the immersive viewer, exactly like a
/// Surf tile. Unlike a Surf tile, holding the card's text does nothing — the
/// peek lives on the card's photos ([PulsePeekableMedia]).
class PulseSurfCard extends StatelessWidget {
  /// Wraps [child] for [entity].
  const PulseSurfCard({
    required this.entity,
    required this.child,
    super.key,
    this.semanticLabel,
  });

  /// The embedded Surf entity.
  final EntityRef entity;

  /// The rendered card.
  final Widget child;

  /// Announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => KGestureRegion(
    semanticLabel: semanticLabel,
    onTap: () => unawaited(
      context.push(KlectLinks.closeupPath(entity.type, entity.id)),
    ),
    // The closeup was already pushed by the first tap; swap it for the
    // immersive viewer so back returns to Pulse.
    onDoubleTap: () => context.pushReplacement(
      '${KlectLinks.immersivePath(entity.type, entity.id)}?i=0',
    ),
    child: KPressFeedback(child: child),
  );
}
