import 'package:flutter/material.dart';

import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// The bottom commit bar shared by the three create forms.
///
/// One primary action, pinned, always reachable with a thumb — and an optional
/// note above it for the thing the user needs to know before they commit.
class CreateSaveBar extends StatelessWidget {
  /// Creates a save bar.
  const CreateSaveBar({
    required this.label,
    required this.onSave,
    super.key,
    this.busy = false,
    this.enabled = true,
    this.note,
    this.progress,
  });

  /// Button label.
  final String label;

  /// Commit handler.
  final Future<void> Function() onSave;

  /// Shows a spinner and blocks input.
  final bool busy;

  /// Whether the form is complete enough to commit.
  final bool enabled;

  /// A line of context above the button.
  final String? note;

  /// Determinate upload progress, drawn as a hairline above the bar.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (progress != null)
              LinearProgressIndicator(
                value: progress,
                minHeight: Strokes.thick,
                backgroundColor: colors.surface3,
                color: colors.accentDefault,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s3,
                Space.s4,
                Space.s3,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (note != null) ...<Widget>[
                    Text(
                      note!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Space.s2),
                  ],
                  KButton(
                    label: label,
                    size: KButtonSize.large,
                    expand: true,
                    busy: busy,
                    onPressed: enabled && !busy ? onSave : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
