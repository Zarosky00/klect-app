import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';

/// What a toast is telling the user.
enum KToastKind {
  /// Plain acknowledgement.
  neutral,

  /// It worked.
  success,

  /// Heads up.
  warning,

  /// It failed.
  error,
}

/// Transient, non-blocking feedback.
///
/// Rides in the [Overlay] rather than the Scaffold so it survives route
/// changes and never shifts layout.
abstract final class KToast {
  /// How long a toast stays on screen. Dwell time, not motion — deliberately
  /// not a motion token.
  static const Duration dwell = Duration(seconds: 3);

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Shows [message]. Replaces any toast already on screen.
  static void show(
    BuildContext context,
    String message, {
    KToastKind kind = KToastKind.neutral,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = dwell,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    final entry = OverlayEntry(
      builder: (overlayContext) => _KToastHost(
        message: message,
        kind: kind,
        icon: icon,
        actionLabel: actionLabel,
        onAction: () {
          onAction?.call();
          dismiss();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, dismiss);
  }

  /// Shorthand for a success toast.
  static void success(BuildContext context, String message) =>
      show(context, message,
          kind: KToastKind.success, icon: Icons.check_rounded);

  /// Shorthand for an error toast.
  static void error(BuildContext context, String message) => show(
        context,
        message,
        kind: KToastKind.error,
        icon: Icons.error_outline_rounded,
      );

  /// Removes the current toast, if any.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _KToastHost extends StatefulWidget {
  const _KToastHost({
    required this.message,
    required this.kind,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final KToastKind kind;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  State<_KToastHost> createState() => _KToastHostState();
}

class _KToastHostState extends State<_KToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.medium,
    reverseDuration: KDurations.fast,
  );

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

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final reduced = KMotion.reduced(context);

    final accent = switch (widget.kind) {
      KToastKind.neutral => colors.textPrimary,
      KToastKind.success => colors.semanticSuccess,
      KToastKind.warning => colors.semanticWarning,
      KToastKind.error => colors.semanticDanger,
    };

    final curved = CurvedAnimation(
      parent: _controller,
      curve: reduced ? Curves_.linear : Curves_.emphasized,
      reverseCurve: Curves_.accelerate,
    );

    final card = Container(
      constraints: const BoxConstraints(maxWidth: Layout.readableMaxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      decoration: BoxDecoration(
        color: colors.surface3,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderDefault, width: Strokes.thin),
        boxShadow: KlectTheme.shadow(Elevation.mid),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.icon != null) ...<Widget>[
            Icon(widget.icon, size: Space.s5, color: accent),
            const SizedBox(width: Space.s3),
          ],
          Flexible(
            child: Text(
              widget.message,
              style: context.kt.callout.copyWith(color: colors.textPrimary),
            ),
          ),
          if (widget.actionLabel != null) ...<Widget>[
            const SizedBox(width: Space.s4),
            GestureDetector(
              onTap: widget.onAction,
              child: Text(
                widget.actionLabel!,
                style: context.kt.label.copyWith(color: colors.accentDefault),
              ),
            ),
          ],
        ],
      ),
    );

    return Positioned(
      left: Space.s4,
      right: Space.s4,
      bottom: Space.s20,
      child: IgnorePointer(
        ignoring: widget.actionLabel == null,
        child: Center(
          child: FadeTransition(
            opacity: curved,
            child: reduced
                ? card
                : SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(curved),
                    child: card,
                  ),
          ),
        ),
      ),
    );
  }
}
