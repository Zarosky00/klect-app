import '../../core/api/api_error.dart';

/// Human copy for every stable identifier emitted by chat, call, group and
/// notification-preference RPCs.
const Map<String, String> stableChatErrorCopy = <String, String>{
  'calls_unavailable': 'Calls are not available right now.',
  'calls_not_allowed': 'Calls are not allowed in this conversation.',
  'not_allowed': 'You do not have permission to do that.',
  'blocked':
      'This call cannot start because one account has blocked the other.',
  'busy': 'You are already in another call.',
  'participant_busy': 'That person is already in another call.',
  'conversation_busy': 'A call is already active in this conversation.',
  'not_dm_member': 'Calls are only available to conversation members.',
  'call_not_found': 'That call no longer exists.',
  'call_not_ringing': 'That call is no longer ringing.',
  'call_expired': 'That call has expired.',
  'caller_cannot_answer': 'The person who started a call cannot answer it.',
  'not_call_participant': 'This call is not available to your account.',
  'title_required': 'Give the group a name first.',
  'title_too_long': 'Group names max out at 60 characters.',
  'description_too_long': 'Group descriptions max out at 500 characters.',
  'group_needs_members': 'Pick at least one person to start a group.',
  'group_full': 'This group is full.',
  'not_group': 'That conversation is not a group.',
  'not_admin': 'Only group admins can do that.',
  'not_member': 'That person is not in this conversation any more.',
  'not_owner': 'Only the group owner can do that.',
  'owner_required': 'Only the group owner can do that.',
  'group_policy_denied': 'Your group role does not allow that.',
  'invite_invalid': 'That invite code is invalid or has been replaced.',
  'bad_invite': 'Paste a valid invite code and try again.',
  'request_not_found': 'That join request is no longer waiting.',
  'blocked_member': 'This group includes someone you have blocked.',
  'group_not_found': 'That group is no longer available.',
  'cannot_remove_owner': 'The owner cannot be removed. Ask them to leave.',
  'cannot_demote_owner':
      'Transfer ownership to someone else before stepping down.',
  'not_message_author': 'Only the author can delete that message for everyone.',
  'message_not_found': 'That message no longer exists.',
  'auth_required': 'Sign in again to save that change.',
  'bad_notification_preferences':
      'Those notification settings could not be saved.',
};

/// Maps a stable server [identifier] and safely degrades unknown identifiers.
String stableErrorIdentifierCopy(String identifier) =>
    stableChatErrorCopy[identifier.trim()] ??
    'That did not work. Try once more.';

/// Turns any API failure into the same copy used throughout chat.
String chatErrorCopy(Object error) {
  final normalized = error is KlectError ? error : KlectError.from(error);
  final mapped = stableChatErrorCopy[normalized.raw.trim()];
  if (mapped != null) return mapped;
  if (normalized.kind == KlectErrorKind.network) {
    return 'You are offline. Check your connection and try again.';
  }
  if (normalized.code == 'PGRST202') {
    return 'This feature is not available right now. Try again soon.';
  }
  return 'That did not work. Try once more.';
}

/// Backwards-compatible name used by the existing group surfaces.
String groupErrorCopy(KlectError error) => chatErrorCopy(error);
