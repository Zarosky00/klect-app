import 'package:flutter/widgets.dart';

import 'tokens.g.dart';

/// The generated [Durations] token class under a name that cannot collide
/// with Material's own `Durations`.
///
/// Any file that imports `package:flutter/material.dart` must use this alias —
/// `KDurations.fast` — because the two names would otherwise be ambiguous.
typedef KDurations = Durations;

/// The generated [Curves_] token class under a friendlier name.
typedef KCurves = Curves_;

/// Motion helpers. Every value here comes from `tokens.g.dart`.
///
/// The two rules from `docs/DESIGN_SYSTEM.md` §3:
///   1. anything the finger drives is a spring, anything the system drives is a curve;
///   2. nothing exceeds 480ms.
abstract final class KMotion {
  /// Press feedback scale, from `docs/DESIGN_SYSTEM.md` §3 ("scale 0.97,
  /// snappy spring, no opacity change").
  ///
  /// It is declared here rather than in a widget so there is still exactly one
  /// place to change it; it belongs in `packages/tokens/tokens.json` the next
  /// time that file is regenerated.
  static const double pressScale = 0.97;

  /// Like/save burst overshoot, from `docs/DESIGN_SYSTEM.md` §3 ("icon
  /// overshoots to 1.25 then settles"). Same caveat as [pressScale].
  static const double burstOvershoot = 1.25;

  /// How long a second tap may arrive and still escalate to immersive.
  ///
  /// The single tap has *already* started the closeup by then — see
  /// `KGestureRegion` — so this window costs the user nothing.
  static const Duration doubleTapWindow = Durations.medium;

  /// Converts a token [SpringSpec] into the physics description Flutter wants.
  static SpringDescription spring(SpringSpec spec) => SpringDescription(
        mass: spec.mass,
        stiffness: spec.stiffness,
        damping: spec.damping,
      );

  /// True when the platform asks us to remove animation travel.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Collapses any duration to [Durations.instant] under reduced motion.
  ///
  /// Reduced motion removes *travel*, never *confirmation* — so we shorten
  /// rather than disable.
  static Duration duration(BuildContext context, Duration d) =>
      reduced(context) ? Durations.instant : d;

  /// Under reduced motion every curve becomes linear so nothing overshoots.
  static Curve curve(BuildContext context, Curve c) =>
      reduced(context) ? Curves_.linear : c;

  /// Stagger delay for the item at [index] in a grid or list, capped at
  /// [Stagger.max] so a long list never feels slow at the bottom.
  static Duration staggerDelay(int index, {bool grid = true}) {
    final step = grid ? Stagger.grid : Stagger.list;
    final capped = index < Stagger.max ? index : Stagger.max;
    return Duration(milliseconds: step * capped);
  }
}
