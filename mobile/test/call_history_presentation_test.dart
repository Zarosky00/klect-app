import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/chat/chat_models.dart';
import 'package:klect/features/chat/widgets/message_bubble.dart';

void main() {
  ChatMessage event({
    required CallStatus status,
    required String caller,
    CallKind kind = CallKind.audio,
    int? duration,
    String? endReason,
  }) => ChatMessage(
    message: const MessageModel(
      id: 'message-1',
      conversationId: 'conversation-1',
      kind: MessageKind.callEvent,
      callId: 'call-1',
    ),
    call: CallModel(
      id: 'call-1',
      conversationId: 'conversation-1',
      createdBy: caller,
      kind: kind,
      status: status,
      durationSeconds: duration,
      endReason: endReason,
    ),
  );

  test('outgoing calls name the peer and include duration', () {
    final result = CallEventPresentation.fromMessage(
      event(status: CallStatus.ended, caller: 'me', duration: 94),
      viewerId: 'me',
      peerName: 'Akash',
    );
    expect(result.primary, 'You called Akash');
    expect(result.secondary, 'Audio • 1:34');
    expect(result.alert, isFalse);
  });

  test('incoming video calls are viewer-relative', () {
    final result = CallEventPresentation.fromMessage(
      event(status: CallStatus.missed, caller: 'akash', kind: CallKind.video),
      viewerId: 'me',
      peerName: 'Akash',
    );
    expect(result.primary, 'Akash called you');
    expect(result.secondary, 'Video • Missed');
    expect(result.video, isTrue);
    expect(result.alert, isTrue);
  });

  test('declined, failed, busy and cancelled outcomes stay distinct', () {
    CallEventPresentation present(CallStatus status, {String? reason}) =>
        CallEventPresentation.fromMessage(
          event(status: status, caller: 'me', endReason: reason),
          viewerId: 'me',
          peerName: 'Akash',
        );

    expect(present(CallStatus.declined).secondary, contains('Declined'));
    expect(present(CallStatus.failed).secondary, contains('Failed'));
    expect(
      present(CallStatus.ended, reason: 'participant_busy').secondary,
      contains('Busy'),
    );
    expect(
      present(CallStatus.ended, reason: 'caller_cancelled').secondary,
      contains('Cancelled'),
    );
  });

  test('legacy rows preserve their stored outcome copy', () {
    const legacy = ChatMessage(
      message: MessageModel(
        id: 'legacy',
        conversationId: 'conversation-1',
        authorId: 'akash',
        body: 'Missed video call',
        kind: MessageKind.callEvent,
      ),
    );
    final result = CallEventPresentation.fromMessage(
      legacy,
      viewerId: 'me',
      peerName: 'Akash',
    );
    expect(result.primary, 'Akash called you');
    expect(result.secondary, 'Audio • Missed video call');
    expect(result.alert, isTrue);
  });
}
