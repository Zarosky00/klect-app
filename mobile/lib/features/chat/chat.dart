/// KLECT chat, in one import.
///
/// What other features usually want from here:
///  * `StartDm.open(context, ref, userId: …)` — the only correct way to begin
///    a conversation. It calls `start_dm`, which enforces the recipient's
///    `allow_messages_from`, and turns a refusal into human copy.
///  * `IncomingCallOverlay` — wrap the tab shell with it and a call rings
///    wherever the user is.
///  * `unreadMessageCountProvider` — the inbox badge.
///  * `MessagesAction` — the badged app-bar entry point to the inbox.
library;

export 'call_screen.dart';
export 'calls/call_config.dart';
export 'calls/call_controller.dart';
export 'calls/call_permissions.dart';
export 'calls/incoming_call_controller.dart';
export 'chat_api.dart';
export 'chat_models.dart';
export 'conversation_screen.dart';
export 'group_errors.dart';
export 'group_info_screen.dart';
export 'inbox_controller.dart';
export 'messages_screen.dart';
export 'new_group_screen.dart';
export 'start_dm.dart';
export 'thread_controller.dart';
export 'widgets/incoming_call_overlay.dart';
export 'widgets/messages_action.dart';
