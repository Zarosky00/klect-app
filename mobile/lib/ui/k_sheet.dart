import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';

/// Bottom sheets.
///
/// Opens on the `emphasized` curve at `medium`, closes faster on `accelerate`,
/// and is draggable with velocity carry (Flutter's own sheet drag physics).
/// Everything rarer than the one action bar lives in here.
abstract final class KSheet {
  /// Presents [builder] in a KLECT sheet and resolves with its result.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    bool showHandle = true,
    bool isDismissible = true,
    bool enableDrag = true,
    bool isScrollControlled = true,
    bool useSafeArea = true,
    double? maxHeightFraction,
  }) {
    final colors = KlectTheme.of(context).colors;
    final reduced = KMotion.reduced(context);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      barrierColor: colors.surfaceScrim,
      elevation: Elevation.none.y,
      constraints: maxHeightFraction == null
          ? null
          : BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * maxHeightFraction,
            ),
      sheetAnimationStyle: AnimationStyle(
        curve: reduced ? Curves_.linear : Curves_.emphasized,
        duration: reduced ? KDurations.instant : KDurations.medium,
        reverseCurve: reduced ? Curves_.linear : Curves_.accelerate,
        reverseDuration: reduced ? KDurations.instant : KDurations.base,
      ),
      builder: (sheetContext) => KSheetShell(
        title: title,
        showHandle: showHandle,
        child: Builder(builder: builder),
      ),
    );
  }
}

/// The chrome of a sheet: grabber, optional title, rounded surface.
///
/// Use it directly when you need a sheet inside your own route rather than via
/// [KSheet.show].
class KSheetShell extends StatelessWidget {
  /// Wraps [child] in sheet chrome.
  const KSheetShell({
    required this.child,
    super.key,
    this.title,
    this.trailing,
    this.showHandle = true,
    this.padding,
  });

  /// Sheet content.
  final Widget child;

  /// Optional title row.
  final String? title;

  /// A control on the title row, e.g. "Done".
  final Widget? trailing;

  /// Draws the drag grabber.
  final bool showHandle;

  /// Overrides the content padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.s2xl),
        ),
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
        boxShadow: KlectTheme.shadow(Elevation.high),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showHandle)
              Padding(
                padding: const EdgeInsets.only(top: Space.s25),
                child: Center(
                  child: Container(
                    width: Space.s10,
                    height: Space.s1,
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                  ),
                ),
              ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s5,
                  Space.s4,
                  Space.s5,
                  Space.s2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(title!, style: context.kt.title2)),
                    ?trailing,
                  ],
                ),
              ),
            Flexible(
              child: Padding(
                padding: padding ??
                    const EdgeInsets.fromLTRB(
                      Space.s5,
                      Space.s2,
                      Space.s5,
                      Space.s5,
                    ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
