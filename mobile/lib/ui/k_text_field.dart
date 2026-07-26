import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme.dart';

/// The product's text input.
///
/// The focus ring is the oxblood `border.focus` at [Strokes.focus] and is always
/// visible on keyboard navigation — never `outline: none`.
class KTextField extends StatelessWidget {
  /// Creates a text field.
  const KTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
  });

  /// External controller.
  final TextEditingController? controller;

  /// Label above the field.
  final String? label;

  /// Placeholder.
  final String? hint;

  /// Helper text below the field.
  final String? helper;

  /// Error text; also switches the border to `semantic.danger`.
  final String? errorText;

  /// Leading glyph.
  final IconData? prefixIcon;

  /// Trailing widget — a visibility toggle, a counter, a spinner.
  final Widget? suffix;

  /// Password mode.
  final bool obscureText;

  /// Soft keyboard type.
  final TextInputType? keyboardType;

  /// Return-key action.
  final TextInputAction? textInputAction;

  /// Autofill hints, e.g. `[AutofillHints.email]`.
  final Iterable<String>? autofillHints;

  /// Maximum lines. Null grows without limit.
  final int? maxLines;

  /// Minimum lines.
  final int? minLines;

  /// Character cap.
  final int? maxLength;

  /// Disabled fields render at `opacity.disabled`.
  final bool enabled;

  /// Focus on first build.
  final bool autofocus;

  /// Input formatters, e.g. the username slug filter.
  final List<TextInputFormatter>? inputFormatters;

  /// Change callback.
  final ValueChanged<String>? onChanged;

  /// Submit callback.
  final ValueChanged<String>? onSubmitted;

  /// External focus node.
  final FocusNode? focusNode;

  /// Capitalisation behaviour.
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!, style: text.label.copyWith(color: colors.textSecondary)),
          const SizedBox(height: Space.s15),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          maxLines: obscureText ? 1 : maxLines,
          minLines: minLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textCapitalization: textCapitalization,
          cursorColor: colors.accentDefault,
          style: text.body,
          buildCounter: (
            context, {
            required int currentLength,
            required bool isFocused,
            required int? maxLength,
          }) =>
              null,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, size: Space.s5, color: colors.textTertiary),
            suffixIcon: suffix,
          ),
        ),
        if (helper != null && errorText == null) ...<Widget>[
          const SizedBox(height: Space.s15),
          Text(helper!, style: text.caption.copyWith(color: colors.textTertiary)),
        ],
      ],
    );
  }
}
