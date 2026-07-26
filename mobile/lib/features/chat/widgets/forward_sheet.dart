import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'conversation_picker.dart';

/// Pick one or more conversations to forward a message into.
///
/// A thin verb over [ConversationPicker] — forwarding and sharing an entity
/// to a friend are the same multi-select inbox picker.
abstract final class ForwardSheet {
  /// Opens the picker and resolves with the chosen conversations, or null.
  static Future<List<ChatInboxEntry>?> show(BuildContext context) =>
      ConversationPicker.show(
        context,
        title: 'Forward to',
        verb: 'Forward',
        icon: Icons.forward_rounded,
      );
}
