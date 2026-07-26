import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'chat_api.dart';

/// Opening a DM, with `allow_messages_from` surfaced as human copy.
///
/// `start_dm` is the only place that decides whether a conversation may exist —
/// it enforces the recipient's `allow_messages_from` server-side and raises.
/// Every entry point into chat (a profile, a match, a share sheet) goes through
/// here so that refusal reads like a product decision rather than a stack
/// trace.
abstract final class StartDm {
  /// Opens (or reuses) the DM with [userId] and navigates to it.
  ///
  /// Returns the conversation id, or null when the DM could not be opened —
  /// in which case the user has already been told why.
  static Future<String?> open(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
    String? displayName,
  }) async {
    final id =
        await start(context, ref, userId: userId, displayName: displayName);
    if (id == null || !context.mounted) return id;
    unawaited(context.push('${Routes.messages}/$id'));
    return id;
  }

  /// Opens (or reuses) the DM with [userId] without navigating.
  static Future<String?> start(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
    String? displayName,
  }) async {
    try {
      return await ref.read(chatApiProvider).startDm(userId);
    } on KlectError catch (error) {
      if (!context.mounted) return null;
      KToast.show(
        context,
        _copyFor(error, displayName),
        kind: KToastKind.warning,
        icon: _iconFor(error),
      );
      return null;
    }
  }

  static String _copyFor(KlectError error, String? displayName) {
    final who = displayName ?? 'This person';
    return switch (error.kind) {
      KlectErrorKind.messagesBlocked =>
        '$who only accepts messages from people they have chosen.',
      KlectErrorKind.forbidden =>
        'You cannot message $who.',
      KlectErrorKind.suspended =>
        'Your account is suspended, so you cannot start conversations.',
      KlectErrorKind.notFound => 'That account no longer exists.',
      KlectErrorKind.auth => 'Sign in to send a message.',
      KlectErrorKind.network =>
        'You are offline — we could not open that conversation.',
      _ => 'That conversation could not be opened. Try once more.',
    };
  }

  static IconData _iconFor(KlectError error) => switch (error.kind) {
        KlectErrorKind.messagesBlocked => Icons.forum_outlined,
        KlectErrorKind.network => Icons.wifi_off_rounded,
        KlectErrorKind.suspended => Icons.gavel_rounded,
        _ => Icons.error_outline_rounded,
      };
}
