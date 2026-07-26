import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api/api_error.dart';
import '../core/links.dart';
import '../core/models/models.dart';
import '../design/theme.dart';
import '../features/chat/chat_api.dart';
import '../features/chat/widgets/conversation_picker.dart';
import 'k_pressable.dart';
import 'k_sheet.dart';
import 'k_toast.dart';

/// **The one share chooser.** Every share entry point in the app — the action
/// bar, the peek, the quick-actions sheet, the closeup overflow — opens this
/// sheet: [Send to a friend | Copy link | Share via system].
///
/// "Send to a friend" reuses the inbox picker and fires the existing
/// `entity_share` message shape, which works for every entity level —
/// posts included.
abstract final class KShareSheet {
  /// Opens the chooser for one entity and runs whichever action was picked.
  static Future<void> show(
    BuildContext context, {
    required EntityType entityType,
    required String entityId,
    String? title,
  }) async {
    final choice = await KSheet.show<_ShareChoice>(
      context: context,
      title: 'Share',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ShareOption(
            icon: Icons.send_rounded,
            label: 'Send to a friend',
            detail: 'Drop it into a conversation as a rich card.',
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.friend),
          ),
          _ShareOption(
            icon: Icons.link_rounded,
            label: 'Copy link',
            detail: 'The same link the web app uses.',
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.copy),
          ),
          _ShareOption(
            icon: Icons.ios_share_rounded,
            label: 'Share via system',
            detail: 'Hand it to any app on this phone.',
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.system),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    final url = KlectLinks.urlFor(entityType, entityId);
    switch (choice) {
      case _ShareChoice.friend:
        await _sendToFriend(context, entityType, entityId);
      case _ShareChoice.copy:
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        KToast.show(
          context,
          'Link copied.',
          kind: KToastKind.success,
          icon: Icons.link_rounded,
        );
      case _ShareChoice.system:
        await SharePlus.instance.share(
          ShareParams(
            text: title == null ? url : '$title\n$url',
            subject: title,
          ),
        );
    }
  }

  static Future<void> _sendToFriend(
    BuildContext context,
    EntityType entityType,
    String entityId,
  ) async {
    final picked = await ConversationPicker.show(context);
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final api = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatApiProvider);
    var sent = 0;
    KlectError? failure;
    for (final entry in picked) {
      try {
        await api.sendMessage(
          conversationId: entry.id,
          sharedEntityType: entityType,
          sharedEntityId: entityId,
        );
        sent++;
      } on KlectError catch (error) {
        failure = error;
      }
    }

    if (!context.mounted) return;
    if (sent == 0) {
      KToast.error(context, failure?.message ?? KlectError.fallbackMessage);
    } else {
      KToast.success(
        context,
        sent > 1 ? 'Sent to $sent conversations' : 'Sent',
      );
    }
  }
}

/// What the chooser resolved to.
enum _ShareChoice { friend, copy, system }

/// One row of the share chooser.
class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Container(
              width: Space.s10,
              height: Space.s10,
              decoration: BoxDecoration(
                color: colors.accentSubtle,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, size: Space.s5, color: colors.actionShare),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: context.kt.bodyStrong),
                  Text(
                    detail,
                    style: context.kt.caption.copyWith(
                      color: colors.textTertiary,
                    ),
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
