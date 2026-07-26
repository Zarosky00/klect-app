import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.g.dart';

export 'tokens.g.dart';

/// The full KLECT type ramp, resolved to real [TextStyle]s.
///
/// Every value is derived from [TypeScale] — nothing here invents a size,
/// a weight or a tracking value.
@immutable
class KlectTextStyles {
  const KlectTextStyles({
    required this.display1,
    required this.display2,
    required this.display3,
    required this.title1,
    required this.title2,
    required this.title3,
    required this.body,
    required this.bodyStrong,
    required this.callout,
    required this.label,
    required this.caption,
    required this.micro,
    required this.count,
  });

  factory KlectTextStyles.forColor(Color color) => KlectTextStyles(
        display1: KlectTypography.style(TypeScale.display1, color),
        display2: KlectTypography.style(TypeScale.display2, color),
        display3: KlectTypography.style(TypeScale.display3, color),
        title1: KlectTypography.style(TypeScale.title1, color),
        title2: KlectTypography.style(TypeScale.title2, color),
        title3: KlectTypography.style(TypeScale.title3, color),
        body: KlectTypography.style(TypeScale.body, color),
        bodyStrong: KlectTypography.style(TypeScale.bodyStrong, color),
        callout: KlectTypography.style(TypeScale.callout, color),
        label: KlectTypography.style(TypeScale.label, color),
        caption: KlectTypography.style(TypeScale.caption, color),
        micro: KlectTypography.style(TypeScale.micro, color),
        count: KlectTypography.style(TypeScale.count, color),
      );

  final TextStyle display1;
  final TextStyle display2;
  final TextStyle display3;
  final TextStyle title1;
  final TextStyle title2;
  final TextStyle title3;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle callout;
  final TextStyle label;

  /// Small, slightly tracked — timestamps and metadata.
  final TextStyle caption;

  /// All-caps eyebrow text.
  final TextStyle micro;

  /// **Tabular figures.** A count that changes width while animating looks broken.
  final TextStyle count;
}

/// Turns [TypeScale] steps into [TextStyle]s, wiring Fraunces + Instrument Sans.
///
/// Both families ship as **bundled variable TTFs** (see `fonts:` in
/// pubspec.yaml) — no runtime fetch, no Roboto first paint, and widget tests
/// need no network shim.
abstract final class KlectTypography {
  /// Nearest static [FontWeight] for a token weight.
  ///
  /// The *rendered* weight comes from the variable-font axis in [style]; this
  /// rounded value rides along only so fallback fonts and bold-synthesis
  /// heuristics degrade sensibly.
  static FontWeight weight(int w) {
    final index = ((w / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }

  /// Resolves one [TypeStep] into a concrete style in [color].
  ///
  /// Token weights (450/550/650) are **exact** variable-font positions via
  /// [FontVariation] — never rounded to the static hundreds. Fraunces also
  /// carries an optical-size axis (9–144); pinning `opsz` to the rendered size
  /// is what gives display type its editorial bite.
  static TextStyle style(TypeStep step, Color color) {
    return TextStyle(
      color: color,
      fontFamily: step.family,
      fontSize: step.size,
      height: step.heightFactor,
      fontWeight: weight(step.weight),
      fontVariations: <FontVariation>[
        FontVariation.weight(step.weight.toDouble()),
        if (step.family == Fonts.display)
          FontVariation.opticalSize(step.size.clamp(9.0, 144.0).toDouble()),
      ],
      letterSpacing: step.tracking,
      fontFeatures:
          step.tabular ? const <FontFeature>[FontFeature.tabularFigures()] : null,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }
}

/// Semantic theme surface. Widgets read **this**, never raw [ThemeData] slots,
/// so `colors.actionLike` stays the single name for "the like colour".
///
/// Read it with `context.k`, `context.kc` (colours) or `context.kt` (type).
@immutable
class KlectTheme extends ThemeExtension<KlectTheme> {
  const KlectTheme({required this.colors, required this.text});

  /// Every colour the product may use, for the active brightness.
  final KlectColors colors;

  /// The resolved type ramp, already coloured `textPrimary`.
  final KlectTextStyles text;

  static const KlectTheme _fallback = KlectTheme(
    colors: KlectColorsDark(),
    text: KlectTextStyles(
      display1: TextStyle(),
      display2: TextStyle(),
      display3: TextStyle(),
      title1: TextStyle(),
      title2: TextStyle(),
      title3: TextStyle(),
      body: TextStyle(),
      bodyStrong: TextStyle(),
      callout: TextStyle(),
      label: TextStyle(),
      caption: TextStyle(),
      micro: TextStyle(),
      count: TextStyle(),
    ),
  );

  /// Never throws: if a widget is pumped without a [Theme] ancestor it still
  /// gets the dark token set rather than a null crash.
  static KlectTheme of(BuildContext context) {
    return Theme.of(context).extension<KlectTheme>() ?? _fallback;
  }

  /// Shadows for one elevation step. Depth comes from surface, not shadow —
  /// this exists for floating chrome only.
  static List<BoxShadow> shadow(ShadowSpec spec) {
    if (spec.blur == 0 && spec.spread == 0) return const <BoxShadow>[];
    return <BoxShadow>[
      BoxShadow(
        offset: Offset(0, spec.y),
        blurRadius: spec.blur,
        spreadRadius: spec.spread,
        color: spec.color,
      ),
    ];
  }

  @override
  KlectTheme copyWith({KlectColors? colors, KlectTextStyles? text}) =>
      KlectTheme(colors: colors ?? this.colors, text: text ?? this.text);

  /// The two themes are discrete token sets, not interpolable ramps, so we
  /// snap at the midpoint instead of producing off-token intermediate colours.
  @override
  KlectTheme lerp(ThemeExtension<KlectTheme>? other, double t) {
    if (other is! KlectTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Ergonomic access to the semantic tokens.
extension KlectThemeContext on BuildContext {
  /// The semantic theme (colours + type).
  KlectTheme get k => KlectTheme.of(this);

  /// Semantic colours.
  KlectColors get kc => KlectTheme.of(this).colors;

  /// The type ramp.
  KlectTextStyles get kt => KlectTheme.of(this).text;
}

/// Builds the whole [ThemeData] from tokens — dark and light.
abstract final class KlectThemeData {
  /// The dark theme. This is the product's default: a private gallery at night.
  static ThemeData dark() => _build(const KlectColorsDark(), Brightness.dark);

  /// The light theme, same tokens, light ramp.
  static ThemeData light() => _build(const KlectColorsLight(), Brightness.light);

  static ThemeData _build(KlectColors c, Brightness brightness) {
    final text = KlectTextStyles.forColor(c.textPrimary);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accentDefault,
      onPrimary: c.textOnAccent,
      primaryContainer: c.accentSubtle,
      onPrimaryContainer: c.accentDefault,
      secondary: c.actionRepost,
      onSecondary: c.textInverse,
      secondaryContainer: c.actionRepostSubtle,
      onSecondaryContainer: c.actionRepost,
      tertiary: c.actionComment,
      onTertiary: c.textInverse,
      tertiaryContainer: c.actionCommentSubtle,
      onTertiaryContainer: c.actionComment,
      error: c.semanticDanger,
      onError: c.textInverse,
      errorContainer: c.semanticDangerSubtle,
      onErrorContainer: c.semanticDanger,
      surface: c.surface1,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.bgSunken,
      surfaceContainerLow: c.bgBase,
      surfaceContainer: c.surface1,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.surface3,
      surfaceTint: c.accentDefault,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderDefault,
      outlineVariant: c.borderSubtle,
      shadow: Elevation.high.color,
      scrim: c.surfaceScrim,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.textInverse,
      inversePrimary: c.accentPress,
    );

    final textTheme = TextTheme(
      displayLarge: text.display1,
      displayMedium: text.display2,
      displaySmall: text.display3,
      headlineLarge: text.display3,
      headlineMedium: text.title1,
      headlineSmall: text.title2,
      titleLarge: text.title1,
      titleMedium: text.title2,
      titleSmall: text.title3,
      bodyLarge: text.body,
      bodyMedium: text.body,
      bodySmall: text.caption,
      labelLarge: text.label,
      labelMedium: text.caption,
      labelSmall: text.micro,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bgBase,
      canvasColor: c.bgBase,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerTheme: DividerThemeData(
        color: c.borderSubtle,
        thickness: Strokes.hairline,
        space: Strokes.hairline,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: Space.s6),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgBase,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: Elevation.none.y,
        scrolledUnderElevation: Elevation.none.y,
        centerTitle: false,
        toolbarHeight: Layout.topBarHeight,
        titleTextStyle: text.title2,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface1,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface1,
        modalBarrierColor: c.surfaceScrim,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.s2xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.title2,
        contentTextStyle: text.body.copyWith(color: c.textSecondary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.xl)),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: Elevation.none.y,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface3,
        contentTextStyle: text.callout,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        hintStyle: text.body.copyWith(color: c.textTertiary),
        labelStyle: text.label.copyWith(color: c.textSecondary),
        errorStyle: text.caption.copyWith(color: c.semanticDanger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.borderDefault, width: Strokes.thin),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.borderSubtle, width: Strokes.thin),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.borderFocus, width: Strokes.focus),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.semanticDanger, width: Strokes.thin),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.semanticDanger, width: Strokes.focus),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accentDefault,
        linearTrackColor: c.surface3,
        circularTrackColor: c.surface3,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accentDefault,
        inactiveTrackColor: c.surface3,
        thumbColor: c.accentDefault,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.textOnAccent
              : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accentDefault
              : c.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.borderSubtle),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surface4,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        textStyle: text.caption,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceGlass,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSubtle,
        height: Layout.bottomBarHeight,
        labelTextStyle: WidgetStateProperty.all(text.micro),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.textPrimary
                : c.textTertiary,
            size: Space.s6,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[
        KlectTheme(colors: c, text: text),
      ],
    );
  }
}
