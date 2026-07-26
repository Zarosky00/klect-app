import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/theme.dart';
import '../../../router.dart';
import '../../../ui/ui.dart';
import '../inbox_controller.dart';

/// The Messages entry point for the feed app bars — a chat-bubble action that
/// pushes the inbox, wearing the same unread badge as the Alerts tab.
///
/// The count is [unreadMessageCountProvider], which derives from the live
/// inbox ([chatInboxProvider]): watching it here spins the inbox's realtime
/// bindings up with the shell, so the badge updates the moment a message
/// arrives or another device reads a thread — no polling, no extra queries.
class MessagesAction extends ConsumerWidget {
  /// Creates the action.
  const MessagesAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final unread = ref.watch(unreadMessageCountProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        KIconButton(
          icon: Icons.chat_bubble_outline_rounded,
          semanticLabel:
              unread > 0 ? 'Messages, $unread unread' : 'Messages',
          onPressed: () => context.push(Routes.messages),
        ),
        if (unread > 0)
          // The badge is decoration on the button: it must neither swallow
          // taps nor announce itself twice, so it ignores pointers and stays
          // out of the semantics tree (the button's label already carries it).
          Positioned(
            // The glyph sits inset from the 44pt tap target —
            // (tapTargetMin − glyph) / 2 + the button's s25 padding = 12 —
            // so these offsets land the badge at the same −s15/−s1 overhang
            // past the glyph's corner as the tab badge in the shell.
            right: Space.s15,
            top: Space.s2,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s1,
                    vertical: Space.s05,
                  ),
                  constraints: const BoxConstraints(minWidth: Space.s4),
                  decoration: BoxDecoration(
                    color: colors.actionLike,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style:
                        context.kt.micro.copyWith(color: colors.textInverse),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
