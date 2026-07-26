import '../../core/api/api_error.dart';

/// The stable snake_case error texts `0017_group_chats.sql` raises, mapped to
/// human copy — the same convention `StartDm` applies to `start_dm`.
const Map<String, String> _groupErrorCopy = <String, String>{
  'title_required': 'Give the group a name first.',
  'title_too_long': 'Group names max out at 80 characters.',
  'group_needs_members': 'Pick at least one person to start a group.',
  'group_full': 'This group is full — 64 people besides the owner is the cap.',
  'not_group': 'That conversation is not a group.',
  'not_admin': 'Only group admins can do that.',
  'not_member': 'That person is not in this group any more.',
  'not_owner': 'Only the group owner can do that.',
  'cannot_remove_owner': 'The owner cannot be removed. Ask them to leave.',
  'cannot_demote_owner':
      'Transfer ownership to someone else before stepping down.',
};

/// Turns a group-RPC failure into a sentence a person can act on.
///
/// Unknown messages fall back to the normal [KlectError] toast path, and a
/// database that does not have the group RPCs yet (migration `0017` not
/// applied) degrades to one honest line instead of a PostgREST stack trace.
String groupErrorCopy(KlectError error) {
  final mapped = _groupErrorCopy[error.message.trim()];
  if (mapped != null) return mapped;
  if (error.kind == KlectErrorKind.network) {
    return 'You are offline — that change never reached the group.';
  }
  // PGRST202 is PostgREST's "no such function": the 0017 migration has not
  // been applied to this database yet.
  if (error.code == 'PGRST202') {
    return 'Group chats are not available right now. Try again soon.';
  }
  return error.message;
}
