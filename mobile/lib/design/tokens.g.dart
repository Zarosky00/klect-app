// GENERATED FILE — DO NOT EDIT.
// Source: packages/tokens/tokens.json
// Regenerate: node packages/tokens/build.mjs
// ignore_for_file: constant_identifier_names, unused_field

import 'dart:ui' show Color;
import 'package:flutter/animation.dart' show Cubic, Curve;

/// Every colour the product may use. Implemented once per theme.
/// A raw hex anywhere in the widget tree is a bug — read it from here.
abstract class KlectColors {
  const KlectColors();
  Color get bgBase;
  Color get bgSunken;
  Color get surface1;
  Color get surface2;
  Color get surface3;
  Color get surface4;
  Color get surfaceScrim;
  Color get surfaceGlass;
  Color get borderSubtle;
  Color get borderDefault;
  Color get borderStrong;
  Color get borderFocus;
  Color get textPrimary;
  Color get textSecondary;
  Color get textTertiary;
  Color get textDisabled;
  Color get textInverse;
  Color get textOnAccent;
  Color get accentDefault;
  Color get accentHover;
  Color get accentPress;
  Color get accentSubtle;
  Color get accentRing;
  Color get actionLike;
  Color get actionLikeSubtle;
  Color get actionSave;
  Color get actionSaveSubtle;
  Color get actionRepost;
  Color get actionRepostSubtle;
  Color get actionComment;
  Color get actionCommentSubtle;
  Color get actionShare;
  Color get semanticSuccess;
  Color get semanticWarning;
  Color get semanticDanger;
  Color get semanticDangerSubtle;
  Color get semanticInfo;
  Color get matchLow;
  Color get matchMid;
  Color get matchHigh;
  Color get matchPeak;
  Color get skeletonBase;
  Color get skeletonShimmer;
  bool get isDark;
}

class KlectColorsDark extends KlectColors {
  const KlectColorsDark();
  @override
  bool get isDark => true;
  @override
  Color get bgBase => const Color(0xFF0A0B0E);
  @override
  Color get bgSunken => const Color(0xFF06070A);
  @override
  Color get surface1 => const Color(0xFF101218);
  @override
  Color get surface2 => const Color(0xFF171A22);
  @override
  Color get surface3 => const Color(0xFF1F232D);
  @override
  Color get surface4 => const Color(0xFF282D39);
  @override
  Color get surfaceScrim => const Color(0x99000000);
  @override
  Color get surfaceGlass => const Color(0xC912141A);
  @override
  Color get borderSubtle => const Color(0xFF20242E);
  @override
  Color get borderDefault => const Color(0xFF2A2F3B);
  @override
  Color get borderStrong => const Color(0xFF3A4150);
  @override
  Color get borderFocus => const Color(0xFFBE4450);
  @override
  Color get textPrimary => const Color(0xFFF5F6F8);
  @override
  Color get textSecondary => const Color(0xFFA5ACBA);
  @override
  Color get textTertiary => const Color(0xFF717A8C);
  @override
  Color get textDisabled => const Color(0xFF4A5162);
  @override
  Color get textInverse => const Color(0xFF0A0B0E);
  @override
  Color get textOnAccent => const Color(0xFFFFF6EC);
  @override
  Color get accentDefault => const Color(0xFFA6323F);
  @override
  Color get accentHover => const Color(0xFFBE4450);
  @override
  Color get accentPress => const Color(0xFF8C2A35);
  @override
  Color get accentSubtle => const Color(0x1FA6323F);
  @override
  Color get accentRing => const Color(0x66A6323F);
  @override
  Color get actionLike => const Color(0xFFFF4D6D);
  @override
  Color get actionLikeSubtle => const Color(0x1FFF4D6D);
  @override
  Color get actionSave => const Color(0xFFA6323F);
  @override
  Color get actionSaveSubtle => const Color(0x1FA6323F);
  @override
  Color get actionRepost => const Color(0xFF2DD4A7);
  @override
  Color get actionRepostSubtle => const Color(0x1F2DD4A7);
  @override
  Color get actionComment => const Color(0xFF4C9AFF);
  @override
  Color get actionCommentSubtle => const Color(0x1F4C9AFF);
  @override
  Color get actionShare => const Color(0xFFA5ACBA);
  @override
  Color get semanticSuccess => const Color(0xFF2DD4A7);
  @override
  Color get semanticWarning => const Color(0xFFF0B429);
  @override
  Color get semanticDanger => const Color(0xFFFF5A5F);
  @override
  Color get semanticDangerSubtle => const Color(0x1FFF5A5F);
  @override
  Color get semanticInfo => const Color(0xFF4C9AFF);
  @override
  Color get matchLow => const Color(0xFF6E7688);
  @override
  Color get matchMid => const Color(0xFF4C9AFF);
  @override
  Color get matchHigh => const Color(0xFF2DD4A7);
  @override
  Color get matchPeak => const Color(0xFFBE4450);
  @override
  Color get skeletonBase => const Color(0xFF171A22);
  @override
  Color get skeletonShimmer => const Color(0xFF22262F);
}

class KlectColorsLight extends KlectColors {
  const KlectColorsLight();
  @override
  bool get isDark => false;
  @override
  Color get bgBase => const Color(0xFFFBFBFC);
  @override
  Color get bgSunken => const Color(0xFFF2F3F5);
  @override
  Color get surface1 => const Color(0xFFFFFFFF);
  @override
  Color get surface2 => const Color(0xFFF7F8FA);
  @override
  Color get surface3 => const Color(0xFFF0F1F4);
  @override
  Color get surface4 => const Color(0xFFE7E9EE);
  @override
  Color get surfaceScrim => const Color(0x800A0B0E);
  @override
  Color get surfaceGlass => const Color(0xCCFFFFFF);
  @override
  Color get borderSubtle => const Color(0xFFEBECF0);
  @override
  Color get borderDefault => const Color(0xFFDFE1E6);
  @override
  Color get borderStrong => const Color(0xFFC1C7D0);
  @override
  Color get borderFocus => const Color(0xFF7C2531);
  @override
  Color get textPrimary => const Color(0xFF0F1116);
  @override
  Color get textSecondary => const Color(0xFF525A69);
  @override
  Color get textTertiary => const Color(0xFF6B7485);
  @override
  Color get textDisabled => const Color(0xFFA9B0BD);
  @override
  Color get textInverse => const Color(0xFFFFFFFF);
  @override
  Color get textOnAccent => const Color(0xFFFFF6EC);
  @override
  Color get accentDefault => const Color(0xFF7C2531);
  @override
  Color get accentHover => const Color(0xFF6E1F2A);
  @override
  Color get accentPress => const Color(0xFF591923);
  @override
  Color get accentSubtle => const Color(0x147C2531);
  @override
  Color get accentRing => const Color(0x597C2531);
  @override
  Color get actionLike => const Color(0xFFE01B47);
  @override
  Color get actionLikeSubtle => const Color(0x14E01B47);
  @override
  Color get actionSave => const Color(0xFF7C2531);
  @override
  Color get actionSaveSubtle => const Color(0x147C2531);
  @override
  Color get actionRepost => const Color(0xFF0C8465);
  @override
  Color get actionRepostSubtle => const Color(0x140C8465);
  @override
  Color get actionComment => const Color(0xFF0B5CD5);
  @override
  Color get actionCommentSubtle => const Color(0x140B5CD5);
  @override
  Color get actionShare => const Color(0xFF525A69);
  @override
  Color get semanticSuccess => const Color(0xFF0C8465);
  @override
  Color get semanticWarning => const Color(0xFF976C06);
  @override
  Color get semanticDanger => const Color(0xFFD91E22);
  @override
  Color get semanticDangerSubtle => const Color(0x14D91E22);
  @override
  Color get semanticInfo => const Color(0xFF0B5CD5);
  @override
  Color get matchLow => const Color(0xFF6B7485);
  @override
  Color get matchMid => const Color(0xFF0B5CD5);
  @override
  Color get matchHigh => const Color(0xFF0C8465);
  @override
  Color get matchPeak => const Color(0xFF7C2531);
  @override
  Color get skeletonBase => const Color(0xFFF0F1F4);
  @override
  Color get skeletonShimmer => const Color(0xFFE7E9EE);
}

/// 4pt grid. Values outside this ramp are not permitted.
abstract final class Space {
  static const double s0 = 0.0;
  static const double s1 = 4.0;
  static const double s2 = 8.0;
  static const double s3 = 12.0;
  static const double s4 = 16.0;
  static const double s5 = 20.0;
  static const double s6 = 24.0;
  static const double s7 = 28.0;
  static const double s8 = 32.0;
  static const double s10 = 40.0;
  static const double s12 = 48.0;
  static const double s14 = 56.0;
  static const double s16 = 64.0;
  static const double s20 = 80.0;
  static const double s24 = 96.0;
  static const double sPx = 1.0;
  static const double s05 = 2.0;
  static const double s15 = 6.0;
  static const double s25 = 10.0;
}

abstract final class Radii {
  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double s2xl = 28.0;
  static const double s3xl = 36.0;
  static const double full = 999.0;
}

abstract final class Strokes {
  static const double hairline = 0.5;
  static const double thin = 1.0;
  static const double thick = 2.0;
  static const double focus = 2.0;
}

/// Immutable description of one step on the type scale.
class TypeStep {
  const TypeStep(this.size, this.height, this.weight, this.family, this.tracking, {this.tabular = false});
  final double size;
  final double height;      // absolute line-height in logical px
  final int weight;
  final String family;
  final double tracking;
  final bool tabular;
  /// Flutter wants a unitless multiplier for TextStyle.height.
  double get heightFactor => height / size;
}

abstract final class Fonts {
  static const String display = 'Fraunces';
  static const String sans = 'Instrument Sans';
  static const String mono = 'JetBrains Mono';
}

abstract final class TypeScale {
  static const TypeStep display1 = TypeStep(44.0, 48.0, 400, Fonts.display, -0.60);
  static const TypeStep display2 = TypeStep(34.0, 40.0, 400, Fonts.display, -0.40);
  static const TypeStep display3 = TypeStep(27.0, 34.0, 400, Fonts.display, -0.20);
  static const TypeStep title1 = TypeStep(22.0, 28.0, 650, Fonts.sans, -0.30);
  static const TypeStep title2 = TypeStep(19.0, 25.0, 650, Fonts.sans, -0.20);
  static const TypeStep title3 = TypeStep(17.0, 23.0, 600, Fonts.sans, -0.10);
  static const TypeStep body = TypeStep(15.0, 22.0, 400, Fonts.sans, 0.00);
  static const TypeStep bodyStrong = TypeStep(15.0, 22.0, 550, Fonts.sans, 0.00);
  static const TypeStep callout = TypeStep(14.0, 20.0, 450, Fonts.sans, 0.00);
  static const TypeStep label = TypeStep(13.0, 18.0, 550, Fonts.sans, 0.10);
  static const TypeStep caption = TypeStep(12.0, 16.0, 450, Fonts.sans, 0.15);
  static const TypeStep micro = TypeStep(11.0, 14.0, 600, Fonts.sans, 0.40);
  static const TypeStep count = TypeStep(13.0, 18.0, 600, Fonts.sans, 0.00, tabular: true);
  static const TypeStep input = TypeStep(16.0, 22.0, 400, Fonts.sans, 0.00);
}

class ShadowSpec {
  const ShadowSpec(this.y, this.blur, this.spread, this.color);
  final double y; final double blur; final double spread; final Color color;
}

abstract final class Elevation {
  static const ShadowSpec none = ShadowSpec(0.0, 0.0, 0.0, Color(0x00000000));
  static const ShadowSpec low = ShadowSpec(1.0, 3.0, 0.0, Color(0x1F000000));
  static const ShadowSpec mid = ShadowSpec(4.0, 14.0, -2.0, Color(0x33000000));
  static const ShadowSpec high = ShadowSpec(12.0, 32.0, -6.0, Color(0x47000000));
  static const ShadowSpec glow = ShadowSpec(0.0, 24.0, -4.0, Color(0x33A6323F));
}

abstract final class Durations {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration deliberate = Duration(milliseconds: 480);
}

abstract final class Curves_ {
  static const Curve standard = Cubic(0.200, 0.000, 0.000, 1.000);
  static const Curve decelerate = Cubic(0.050, 0.700, 0.100, 1.000);
  static const Curve accelerate = Cubic(0.300, 0.000, 0.800, 0.150);
  static const Curve emphasized = Cubic(0.160, 1.000, 0.300, 1.000);
  static const Curve overshoot = Cubic(0.340, 1.560, 0.640, 1.000);
  static const Curve linear = Cubic(0.000, 0.000, 1.000, 1.000);
}

class SpringSpec {
  const SpringSpec(this.stiffness, this.damping, this.mass);
  final double stiffness; final double damping; final double mass;
}

abstract final class Springs {
  static const SpringSpec snappy = SpringSpec(420.0, 32.0, 1.0);
  static const SpringSpec gentle = SpringSpec(220.0, 26.0, 1.0);
  static const SpringSpec bouncy = SpringSpec(380.0, 20.0, 1.0);
  static const SpringSpec sheet = SpringSpec(300.0, 30.0, 1.0);
}

abstract final class Stagger {
  static const int grid = 26;
  static const int list = 34;
  static const int max = 8;
}

/// How long a transient surface stays before it dismisses itself.
/// A dwell period is not an animation, so the 480ms animation ceiling
/// from `docs/DESIGN_SYSTEM.md` does not apply here.
abstract final class Dwell {
  static const Duration banner = Duration(milliseconds: 5000);
}

/// Finger-driven commit thresholds. Distances are logical pixels,
/// velocities logical pixels per second, fractions are of the dragged extent.
abstract final class Drags {
  static const double bannerLimit = 96.0;
  static const double commitFraction = 0.4;
  static const double pageCommitFraction = 0.25;
  static const double flingVelocityMin = 400.0;
  static const double overscrollMax = 32.0;
}

/// How long an async placeholder may wait before it gives up.
/// Network budget, not motion.
abstract final class Timeouts {
  static const Duration thumbnail = Duration(milliseconds: 2000);
}

abstract final class Breakpoints {
  static const double xs = 0.0;
  static const double sm = 480.0;
  static const double md = 768.0;
  static const double lg = 1024.0;
  static const double xl = 1280.0;
  static const double s2xl = 1600.0;
}

abstract final class Layout {
  static const double masonryGutter = 10.0;
  static const double contentMaxWidth = 1320.0;
  static const double readableMaxWidth = 680.0;
  static const double tapTargetMin = 44.0;
  static const double bottomBarHeight = 60.0;
  static const double topBarHeight = 52.0;
  static const double callPillHeight = 48.0;
  /// Masonry column count for a given viewport width. Mobile and web
  /// resolve this identically so a shared link looks like the same product.
  static int masonryColumns(double width) {
    if (width >= 1600.0) return 6;
    if (width >= 1280.0) return 5;
    if (width >= 1024.0) return 4;
    if (width >= 768.0) return 3;
    if (width >= 480.0) return 2;
    if (width >= 0.0) return 2;
    return 2;
  }
}

abstract final class Opacities {
  static const double disabled = 0.38;
  static const double pressed = 0.72;
  static const double hover = 0.86;
  static const double veil = 0.6;
  static const double ghost = 0.08;
}

abstract final class Blurs {
  static const double chrome = 24.0;
  static const double sheet = 32.0;
  static const double spoiler = 40.0;
}

abstract final class Aspect {
  static const double gridMin = 0.62;
  static const double gridMax = 1.60;
  static const double cover = 1.00;
  static const double banner = 3.00;
}

abstract final class ZIndex {
  static const int base = 0;
  static const int raised = 10;
  static const int sticky = 100;
  static const int chrome = 200;
  static const int sheet = 300;
  static const int modal = 400;
  static const int toast = 500;
  static const int immersive = 600;
}
