import 'package:supabase_flutter/supabase_flutter.dart';

/// The failure modes `docs/BACKEND_API.md` §5 asks the client to handle
/// explicitly, plus the transport cases the offline queue needs to recognise.
enum KlectErrorKind {
  /// No connection / DNS / timeout. The action is queued, not rolled back.
  network,

  /// `42501` — the content became invisible or the viewer is blocked.
  /// Refresh the card; do **not** retry.
  forbidden,

  /// Every write RPC raises this for a suspended account.
  suspended,

  /// `start_dm` refused because of the recipient's `allow_messages_from`.
  messagesBlocked,

  /// Unique violation on `follows` / `likes` — already applied, treat as
  /// success.
  duplicate,

  /// The row is gone.
  notFound,

  /// Bad credentials, expired session, weak password…
  auth,

  /// Object storage rejected the upload.
  storage,

  /// Anything else.
  unknown,
}

/// A normalised error the UI can switch on.
class KlectError implements Exception {
  /// Creates a normalised error.
  const KlectError(
    this.kind,
    this.message, {
    this.code,
    this.cause,
    this.detail,
  });

  /// Normalises anything thrown by the Supabase SDK.
  factory KlectError.from(Object error) {
    if (error is KlectError) return error;

    if (error is PostgrestException) {
      final message = error.message;
      if (_looksLikeNetwork(message)) {
        return KlectError(
          KlectErrorKind.network,
          'You appear to be offline.',
          code: error.code,
          cause: error,
          detail: message,
        );
      }
      if (message.toLowerCase().contains('account suspended')) {
        return KlectError(
          KlectErrorKind.suspended,
          'Your account is suspended.',
          code: error.code,
          cause: error,
        );
      }
      if (message.toLowerCase().contains('not accepting messages')) {
        return KlectError(
          KlectErrorKind.messagesBlocked,
          'This person is not accepting messages.',
          code: error.code,
          cause: error,
        );
      }
      return switch (error.code) {
        '42501' => KlectError(
          KlectErrorKind.forbidden,
          'You can no longer interact with this.',
          code: error.code,
          cause: error,
        ),
        '23505' => KlectError(
          KlectErrorKind.duplicate,
          'Already applied.',
          code: error.code,
          cause: error,
        ),
        'PGRST116' => KlectError(
          KlectErrorKind.notFound,
          'That is no longer here.',
          code: error.code,
          cause: error,
        ),
        // Never surface raw Postgres text to a person. The raw message stays
        // on [detail] so mappers (create_post, group RPCs) and logs keep the
        // stable snake_case texts they match on.
        _ => KlectError(
          KlectErrorKind.unknown,
          fallbackMessage,
          code: error.code,
          cause: error,
          detail: message,
        ),
      };
    }

    if (error is AuthException) {
      return KlectError(
        KlectErrorKind.auth,
        error.message,
        code: error.statusCode,
        cause: error,
      );
    }

    if (error is StorageException) {
      return KlectError(
        KlectErrorKind.storage,
        error.message,
        code: error.statusCode,
        cause: error,
      );
    }

    // Everything the SDK does not wrap in a typed exception reached us before
    // the server answered: no socket, no DNS, or a timeout.
    return KlectError(
      KlectErrorKind.network,
      'You appear to be offline.',
      cause: error,
      detail: error.toString(),
    );
  }

  /// The generic copy shown when a failure has no better human sentence.
  static const String fallbackMessage =
      'Something went wrong — please try again.';

  /// Which failure this is.
  final KlectErrorKind kind;

  /// Message safe to show a user.
  final String message;

  /// Postgres/HTTP code when there was one.
  final String? code;

  /// The original error, for logging.
  final Object? cause;

  /// The raw server/SDK text, for debugging and for mappers that match the
  /// backend's stable snake_case error texts. Never shown to a user as-is.
  final String? detail;

  /// The text to match RPC error contracts against: the raw detail when the
  /// message was replaced by generic copy, the message otherwise.
  String get raw => detail ?? message;

  /// True when retrying later is the right move (the offline queue's cue).
  bool get isRetryable => kind == KlectErrorKind.network;

  /// True when the optimistic delta must be rolled back immediately.
  bool get requiresRollback =>
      kind == KlectErrorKind.forbidden ||
      kind == KlectErrorKind.suspended ||
      kind == KlectErrorKind.notFound;

  static bool _looksLikeNetwork(String message) {
    final m = message.toLowerCase();
    return m.contains('failed host lookup') ||
        m.contains('socketexception') ||
        m.contains('clientexception') ||
        m.contains('connection closed') ||
        m.contains('connection refused') ||
        m.contains('connection reset') ||
        m.contains('network is unreachable') ||
        m.contains('timed out');
  }

  @override
  String toString() =>
      'KlectError(${kind.name}, $message, code: $code'
      '${detail == null ? '' : ', detail: $detail'})';
}
