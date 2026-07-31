import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/chat/chat_models.dart';

/// A stored row exactly as `delete_message_for_everyone` returns it: same id,
/// same author, same reply target, same created timestamp, empty body, no
/// attachments, `deleted_at` set.
Map<String, dynamic> _tombstoneRow() => <String, dynamic>{
  'id': 'msg-1',
  'conversation_id': 'conv-1',
  'author_id': 'user-1',
  'body': '',
  'kind': 'text',
  'attachments': <Map<String, dynamic>>[],
  'reply_to_id': 'msg-0',
  'created_at': '2026-07-28T10:00:00.000Z',
  'deleted_at': '2026-07-28T10:05:00.000Z',
};

Map<String, dynamic> _liveRow() => <String, dynamic>{
  'id': 'msg-2',
  'conversation_id': 'conv-1',
  'author_id': 'user-1',
  'body': 'still here',
  'kind': 'text',
  'attachments': <Map<String, dynamic>>[
    <String, dynamic>{'storage_path': 'user-1/conv-1/a.jpg'},
  ],
  'created_at': '2026-07-28T10:01:00.000Z',
};

void main() {
  group('tombstone derivation', () {
    test('a deleted row is a tombstone that keeps its identity', () {
      final message = ChatMessage.fromJson(_tombstoneRow());

      expect(message.isTombstone, isTrue);
      expect(message.isDeleted, isTrue);
      expect(message.id, 'msg-1');
      expect(message.authorId, 'user-1');
      expect(message.message.replyToId, 'msg-0');
      expect(
        message.createdAt,
        DateTime.parse('2026-07-28T10:00:00.000Z').toLocal(),
      );
      expect(message.hasText, isFalse);
      expect(message.attachments, isEmpty);
    });

    test('a live row is not a tombstone', () {
      final message = ChatMessage.fromJson(_liveRow());

      expect(message.isTombstone, isFalse);
      expect(message.hasText, isTrue);
      expect(message.attachments, hasLength(1));
    });

    test('a null deleted_at leaves MessageModel.isTombstone false', () {
      expect(MessageModel.fromJson(_liveRow()).isTombstone, isFalse);
      expect(MessageModel.fromJson(_tombstoneRow()).isTombstone, isTrue);
    });
  });

  group('optimistic tombstone', () {
    test('clears the body and every attachment while keeping identity', () {
      final live = MessageModel.fromJson(_liveRow());
      final at = DateTime.parse('2026-07-28T10:06:00.000Z');

      final tombstone = live.tombstoned(at: at);

      expect(tombstone.isTombstone, isTrue);
      expect(tombstone.deletedAt, at);
      expect(tombstone.body, '');
      expect(tombstone.attachments, isEmpty);
      // Identity and ordering survive exactly as the RPC leaves them.
      expect(tombstone.id, live.id);
      expect(tombstone.conversationId, live.conversationId);
      expect(tombstone.authorId, live.authorId);
      expect(tombstone.replyToId, live.replyToId);
      expect(tombstone.kind, live.kind);
      expect(tombstone.createdAt, live.createdAt);
    });

    test('a repeat keeps the first deleted_at', () {
      final first = MessageModel.fromJson(_liveRow()).tombstoned(
        at: DateTime.parse('2026-07-28T10:06:00.000Z'),
      );

      final second = first.tombstoned(
        at: DateTime.parse('2026-07-28T11:00:00.000Z'),
      );

      expect(second.deletedAt, first.deletedAt);
    });

    test('rolling back restores the original body and attachment set', () {
      final before = ChatMessage.fromJson(_liveRow());

      // The optimistic tombstone never mutates what was captured, so the
      // restore is the captured object itself (11.12).
      final optimistic = before.copyWith(message: before.message.tombstoned());

      expect(optimistic.isTombstone, isTrue);
      expect(before.isTombstone, isFalse);
      expect(before.message.body, 'still here');
      expect(before.attachments, hasLength(1));
      expect(
        before.attachments.single.storagePath,
        'user-1/conv-1/a.jpg',
      );
    });

    test('a hidden message stays hidden once tombstoned', () {
      final hidden = MessageModel.fromJson(_liveRow()).copyWith(
        hiddenForMe: true,
      );

      expect(hidden.tombstoned().hiddenForMe, isTrue);
    });
  });

  group('hiddenForMe', () {
    test('a row parsed off the wire is never hidden', () {
      expect(ChatMessage.fromJson(_liveRow()).hiddenForMe, isFalse);
      expect(ChatMessage.fromJson(_tombstoneRow()).hiddenForMe, isFalse);
    });

    test('copyWith stamps the flag onto the wrapped row', () {
      final hidden = ChatMessage.fromJson(_liveRow()).copyWith(
        hiddenForMe: true,
      );

      expect(hidden.hiddenForMe, isTrue);
      expect(hidden.message.hiddenForMe, isTrue);
      // Nothing else moves.
      expect(hidden.id, 'msg-2');
      expect(hidden.message.body, 'still here');
      expect(hidden.attachments, hasLength(1));
    });

    test('an omitted flag survives an unrelated copyWith', () {
      final hidden = ChatMessage.fromJson(_liveRow()).copyWith(
        hiddenForMe: true,
      );

      expect(hidden.copyWith(pending: true).hiddenForMe, isTrue);
      expect(hidden.copyWith(hiddenForMe: false).hiddenForMe, isFalse);
    });

    test('a hidden message that is later tombstoned stays hidden', () {
      final hidden = ChatMessage.fromJson(_liveRow()).copyWith(
        hiddenForMe: true,
      );
      final tombstoned = hidden.copyWith(
        message: MessageModel.fromJson(_tombstoneRow()),
        hiddenForMe: true,
      );

      expect(tombstoned.isTombstone, isTrue);
      expect(tombstoned.hiddenForMe, isTrue);
    });
  });
}
