import 'package:flutter/material.dart';

import '../core/api/api_error.dart';
import '../design/theme.dart';
import 'k_empty_state.dart';

/// Every error state offers a retry. There are no dead ends.
///
/// Give it a [KlectError] and it picks the right words for the failure —
/// offline reads differently from "you can no longer interact with this".
class KErrorState extends StatelessWidget {
  /// Creates an error state.
  const KErrorState({
    super.key,
    this.error,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.compact = false,
  });

  /// The failure, if it was normalised.
  final Object? error;

  /// Overrides the derived headline.
  final String? title;

  /// Overrides the derived sentence.
  final String? message;

  /// Retry handler.
  final VoidCallback? onRetry;

  /// Retry button label.
  final String retryLabel;

  /// Tighter spacing.
  final bool compact;

  ({String title, String message, IconData icon}) get _copy {
    final normalised = error == null ? null : KlectError.from(error!);
    return switch (normalised?.kind) {
      KlectErrorKind.network => (
          title: 'You are offline',
          message: 'We will pick this up the moment you are back. '
              'Anything you tapped is saved.',
          icon: Icons.wifi_off_rounded,
        ),
      KlectErrorKind.forbidden => (
          title: 'Not available',
          message: 'This is no longer visible to you.',
          icon: Icons.lock_outline_rounded,
        ),
      KlectErrorKind.suspended => (
          title: 'Account suspended',
          message: normalised?.message ??
              'Your account is suspended, so this action was refused.',
          icon: Icons.gavel_rounded,
        ),
      KlectErrorKind.notFound => (
          title: 'Gone',
          message: 'Whatever was here has been removed.',
          icon: Icons.search_off_rounded,
        ),
      KlectErrorKind.messagesBlocked => (
          title: 'Messages closed',
          message: 'This person is not accepting messages.',
          icon: Icons.forum_outlined,
        ),
      _ => (
          title: 'Something broke',
          message: normalised?.message ?? 'That did not work. Try once more.',
          icon: Icons.error_outline_rounded,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return KEmptyState(
      title: title ?? copy.title,
      message: message ?? copy.message,
      icon: copy.icon,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
      compact: compact,
    );
  }
}

/// A one-line inline error for use inside a list or a form.
class KInlineError extends StatelessWidget {
  /// Creates an inline error.
  const KInlineError({required this.message, super.key, this.onRetry});

  /// What went wrong.
  final String message;

  /// Retry handler.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      decoration: BoxDecoration(
        color: colors.semanticDangerSubtle,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.semanticDanger, width: Strokes.thin),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: Space.s5,
            color: colors.semanticDanger,
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(
              message,
              style: context.kt.callout.copyWith(color: colors.semanticDanger),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: context.kt.label.copyWith(color: colors.semanticDanger),
              ),
            ),
        ],
      ),
    );
  }
}
