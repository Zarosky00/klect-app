import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/features/chat/chat_models.dart';
import 'package:klect/features/chat/conversation_screen.dart';
import 'package:klect/features/chat/thread_controller.dart';
import 'package:klect/features/chat/widgets/chat_composer.dart';

void main() {
  for (final width in <double>[320, 360, 412]) {
    testWidgets(
      'reply text stays above a large keyboard at ${width.toInt()}px',
      (tester) async {
        tester.view
          ..physicalSize = Size(width, 640)
          ..devicePixelRatio = 1
          ..viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);

        const reply = ChatMessage(
          message: MessageModel(
            id: 'reply-1',
            conversationId: 'conversation-1',
            body: 'The original message',
            author: Profile(
              id: 'author-1',
              username: 'aria',
              displayName: 'Aria',
            ),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatThreadProvider(
                'conversation-1',
              ).overrideWith(() => _FakeChatThreadController('conversation-1')),
            ],
            child: MaterialApp(
              theme: KlectThemeData.dark(),
              home: const Scaffold(
                resizeToAvoidBottomInset: false,
                body: ConversationKeyboardInset(
                  child: Column(
                    children: <Widget>[
                      Expanded(child: SizedBox.expand()),
                      ChatComposer(
                        conversationId: 'conversation-1',
                        replyTo: reply,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.showKeyboard(
          find.byKey(const ValueKey<String>('chat-composer-field')),
        );
        await tester.enterText(
          find.byType(TextField),
          'This draft remains visible',
        );
        await tester.pumpAndSettle();

        final field = tester.getRect(
          find.byKey(const ValueKey<String>('chat-composer-field')),
        );
        final contextBanner = tester.getRect(
          find.byKey(const ValueKey<String>('chat-context-banner')),
        );
        expect(contextBanner.top, greaterThanOrEqualTo(0));
        expect(field.bottom, lessThanOrEqualTo(340));
        expect(find.text('This draft remains visible'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _FakeChatThreadController extends ChatThreadController {
  _FakeChatThreadController(super.conversationId);

  @override
  ChatThreadState build() => const ChatThreadState();

  @override
  void notifyTyping() {}
}
