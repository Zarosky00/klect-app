import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/widgets/entity_visual.dart';

/// Shared-element tags for the Library's level-to-level transitions.
///
/// Collection card → collection header → subcollection card → subcollection
/// header → item tile → item header all fly the same cover, because they all
/// ask this for the tag.
abstract final class LibraryHero {
  /// The cover tag for one entity.
  static String cover(EntityType type, String id) =>
      'klect-cover-${type.wire}-$id';
}

/// Navigation shared by every Library card, so the gesture contract is
/// implemented once.
abstract final class LibraryNavigation {
  /// Single tap — drill into the next level down.
  static void open(BuildContext context, EntityType type, String id) =>
      context.push(KlectLinks.pathFor(type, id));

  /// Double tap — escalate the just-opened screen to the immersive viewer.
  static void immersive(BuildContext context, EntityType type, String id) =>
      context.pushReplacement(KlectLinks.immersivePath(type, id));
}

/// Grid metrics, derived from tokens rather than invented.
abstract final class LibraryGrid {
  /// Widest a collection tile may get before the grid adds a column.
  static const double collectionExtent = Space.s24 * 2;

  /// Widest an item tile may get before the grid adds a column.
  static const double itemExtent = Space.s20 * 2;

  /// Height of the caption block under a square cover.
  static const double caption = Space.s12;

  /// Aspect ratio for a square cover plus a caption of [caption] height.
  static double ratioFor(double extent) => extent / (extent + caption);
}

/// The `Anime · JJK` trail.
///
/// Every level of the hierarchy shows where it sits, and every step is tappable
/// so a user can walk back up without the back button.
class LibraryBreadcrumb extends StatelessWidget {
  /// Creates a breadcrumb.
  const LibraryBreadcrumb({required this.steps, super.key, this.current});

  /// Ancestors, outermost first.
  final List<BreadcrumbStep> steps;

  /// The level currently on screen, rendered inert at the end of the trail.
  final String? current;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    if (steps.isEmpty && current == null) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      if (i > 0) children.add(_separator(context));
      children.add(
        KPressable(
          onTap: steps[i].onTap,
          enabled: steps[i].onTap != null,
          enforceMinTapTarget: false,
          semanticLabel: steps[i].label,
          child: Text(
            steps[i].label,
            style: context.kt.caption.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (current != null) {
      if (children.isNotEmpty) children.add(_separator(context));
      children.add(
        Flexible(
          child: Text(
            current!,
            style: context.kt.caption.copyWith(color: colors.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Semantics(
      label: 'Breadcrumb',
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _separator(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s15),
        child: Icon(
          Icons.chevron_right_rounded,
          size: Space.s4,
          color: context.kc.textTertiary,
        ),
      );
}

/// One tappable ancestor in a [LibraryBreadcrumb].
@immutable
class BreadcrumbStep {
  /// Creates a step.
  const BreadcrumbStep({required this.label, this.onTap});

  /// What to render.
  final String label;

  /// Where it goes. Null renders it inert.
  final VoidCallback? onTap;
}

/// The small lock/group glyph that marks anything not fully public.
class VisibilityBadge extends StatelessWidget {
  /// Creates a badge. Renders nothing for a public entity.
  const VisibilityBadge({required this.visibility, super.key, this.dense = false});

  /// The level's own visibility. Null (inherit) shows nothing.
  final EntityVisibility? visibility;

  /// Drops the label and shows the glyph alone.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final value = visibility;
    if (value == null || value == EntityVisibility.public) {
      return const SizedBox.shrink();
    }
    final colors = context.kc;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Space.s1 : Space.s2,
        vertical: Space.sPx,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceScrim,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            EntityVisual.visibilityIcon(value),
            size: Space.s4,
            color: colors.textPrimary,
          ),
          if (!dense) ...<Widget>[
            const SizedBox(width: Space.s1),
            Text(
              value.label,
              style: context.kt.micro.copyWith(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet `12 groups · 84 items` line.
class MetaLine extends StatelessWidget {
  /// Creates a meta line from already-counted parts.
  const MetaLine({required this.parts, super.key, this.style});

  /// Pre-formatted fragments; empty ones are dropped.
  final List<String> parts;

  /// Overrides the caption style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final visible = <String>[
      for (final part in parts)
        if (part.isNotEmpty) part,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Text(
      visible.join(' · '),
      style: style ??
          context.kt.caption.copyWith(color: context.kc.textTertiary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// `1 item` / `12 items`, without an off-by-one plural.
String plural(int count, String singular, [String? pluralForm]) =>
    '$count ${count == 1 ? singular : (pluralForm ?? '${singular}s')}';
