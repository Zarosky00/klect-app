import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_button.dart';

/// A yes/no dialog for anything irreversible.
abstract final class KConfirmDialog {
  /// Asks the user to confirm. Resolves true only on an explicit yes.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: KlectTheme.of(context).colors.surfaceScrim,
      builder: (dialogContext) => _KConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }
}

class _KConfirmDialog extends StatelessWidget {
  const _KConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Dialog(
      backgroundColor: colors.surface2,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(Space.s6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.xl)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: context.kt.title2),
            if (message != null) ...<Widget>[
              const SizedBox(height: Space.s2),
              Text(
                message!,
                style: context.kt.body.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: Space.s6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                KButton(
                  label: cancelLabel,
                  variant: KButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: Space.s2),
                KButton(
                  label: confirmLabel,
                  variant: destructive
                      ? KButtonVariant.danger
                      : KButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
