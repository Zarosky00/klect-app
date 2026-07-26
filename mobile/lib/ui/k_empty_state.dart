import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_button.dart';

/// Display-serif headline + one sentence + one action.
///
/// Never an illustration-only dead end: an empty state always offers the next
/// move.
class KEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const KEmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  /// The headline, rendered in Instrument Serif.
  final String title;

  /// One sentence of explanation.
  final String? message;

  /// A quiet glyph above the headline.
  final IconData? icon;

  /// Primary action label.
  final String? actionLabel;

  /// Primary action.
  final VoidCallback? onAction;

  /// Secondary action label.
  final String? secondaryActionLabel;

  /// Secondary action.
  final VoidCallback? onSecondaryAction;

  /// Tighter spacing for use inside a sheet or a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.readableMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Space.s6,
            vertical: compact ? Space.s6 : Space.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: Space.s10, color: colors.textTertiary),
                const SizedBox(height: Space.s5),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact ? text.display3 : text.display2,
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: Space.s3),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.body.copyWith(color: colors.textSecondary),
                ),
              ],
              if (actionLabel != null) ...<Widget>[
                const SizedBox(height: Space.s6),
                KButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ],
              if (secondaryActionLabel != null) ...<Widget>[
                const SizedBox(height: Space.s2),
                KButton(
                  label: secondaryActionLabel!,
                  variant: KButtonVariant.ghost,
                  onPressed: onSecondaryAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
