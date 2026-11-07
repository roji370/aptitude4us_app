import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aptitude4us_academy/utils/community_merge.dart';
import 'package:aptitude4us_academy/models/community_chat_message.dart';

void main() {
  const currentUid = 'user-1';
  const adminUid = 'admin-1';
  const otherUid = 'user-2';

  final t0 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0));
  final t1 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 1));
  final t2 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 2));
  final t3 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 3));
  final t4 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 4));
  final t5 = Timestamp.fromDate(DateTime(2026, 1, 1, 10, 5));

  CommunityChatMessage msg({
    required String id,
    required Timestamp timestamp,
    String senderId = adminUid,
    String senderName = 'Admin',
    String text = 'hello',
    String status = 'sent',
    bool isPending = false,
  }) {
    return CommunityChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      receiverId: 'COMMUNITY',
      text: text,
      timestamp: timestamp,
      status: status,
      type: 'text',
      isPending: isPending,
    );
  }

  group('mergeCommunitySnapshot', () {
    test('identical snapshot → no changes', () {
      final existing = [
        msg(id: 'a', timestamp: t2),
        msg(id: 'b', timestamp: t1),
        msg(id: 'c', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'a', timestamp: t2),
        msg(id: 'b', timestamp: t1),
        msg(id: 'c', timestamp: t0),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.changed, isFalse);
      expect(result.wasReplaced, isFalse);
      expect(result.newIncomingIds, isEmpty);
      expect(result.newOwnIds, isEmpty);
      // Returns the same reference when nothing changed.
      expect(identical(result.messages, existing), isTrue);
    });

    test('edit in place', () {
      final existing = [
        msg(id: 'a', timestamp: t1, text: 'original'),
        msg(id: 'b', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'a', timestamp: t1, text: 'edited'),
        msg(id: 'b', timestamp: t0),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.changed, isTrue);
      expect(result.messages.firstWhere((m) => m.id == 'a').text, 'edited');
      expect(result.newIncomingIds, isEmpty,
          reason: 'edits are not new incoming');
    });

    test('pending → confirmed transition', () {
      final existing = [
        msg(
          id: 'a',
          timestamp: t1,
          senderId: currentUid,
          isPending: true,
          status: 'sending',
        ),
      ];
      final snapshot = [
        msg(
          id: 'a',
          timestamp: t1,
          senderId: currentUid,
          isPending: false,
          status: 'sent',
        ),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.changed, isTrue);
      expect(result.messages.first.isPending, isFalse);
      expect(result.messages.first.status, 'sent');
      expect(result.newOwnIds, isEmpty,
          reason: 'confirmed copy is not a new message');
    });

    test('three new messages arrive in order', () {
      final existing = [
        msg(id: 'old-1', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'new-3', timestamp: t3, senderId: otherUid),
        msg(id: 'new-2', timestamp: t2, senderId: otherUid),
        msg(id: 'new-1', timestamp: t1, senderId: otherUid),
        msg(id: 'old-1', timestamp: t0),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.changed, isTrue);
      expect(result.wasReplaced, isFalse);
      // Order should be new-3, new-2, new-1, old-1 (timestamp desc).
      final ids = result.messages.map((m) => m.id).toList();
      expect(ids, ['new-3', 'new-2', 'new-1', 'old-1']);
      expect(result.newIncomingIds, {'new-3', 'new-2', 'new-1'});
    });

    test('own pending messages pinned at front', () {
      final existing = [
        msg(
          id: 'pending-1',
          timestamp: t3,
          senderId: currentUid,
          isPending: true,
        ),
        msg(id: 'msg-1', timestamp: t2, senderId: adminUid),
        msg(id: 'msg-2', timestamp: t1, senderId: adminUid),
      ];
      // Snapshot doesn't include the pending message yet.
      final snapshot = [
        msg(id: 'msg-1', timestamp: t2, senderId: adminUid),
        msg(id: 'msg-2', timestamp: t1, senderId: adminUid),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      // Pending should be pinned at front.
      expect(result.messages.first.id, 'pending-1');
      expect(result.messages.first.isPending, isTrue);
    });

    test('no-overlap → full replace', () {
      final existing = [
        msg(id: 'old-2', timestamp: t1),
        msg(id: 'old-1', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'new-3', timestamp: t4, senderId: adminUid),
        msg(id: 'new-2', timestamp: t3, senderId: adminUid),
        msg(id: 'new-1', timestamp: t2, senderId: adminUid),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isTrue);
      expect(result.changed, isTrue);
      final ids = result.messages.map((m) => m.id).toList();
      expect(ids, ['new-3', 'new-2', 'new-1']);
      // Old messages should be gone.
      expect(result.messages.any((m) => m.id == 'old-1'), isFalse);
      expect(result.newIncomingIds, {'new-3', 'new-2', 'new-1'});
    });

    test('same timestamp tie-break by id desc', () {
      final existing = <CommunityChatMessage>[];
      final snapshot = [
        msg(id: 'bbb', timestamp: t1),
        msg(id: 'aaa', timestamp: t1),
        msg(id: 'ccc', timestamp: t1),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      final ids = result.messages.map((m) => m.id).toList();
      expect(ids, ['ccc', 'bbb', 'aaa']);
    });

    test('window slide — missing ids are kept', () {
      // 3 existing messages, snapshot only contains 2 (oldest dropped
      // due to window slide from limit).
      final existing = [
        msg(id: 'c', timestamp: t2),
        msg(id: 'b', timestamp: t1),
        msg(id: 'a', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'new-1', timestamp: t3, senderId: otherUid),
        msg(id: 'c', timestamp: t2),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      // 'b' and 'a' should still be in the list — never remove on slide.
      final ids = result.messages.map((m) => m.id).toList();
      expect(ids.contains('a'), isTrue);
      expect(ids.contains('b'), isTrue);
      expect(ids.contains('new-1'), isTrue);
      expect(result.messages.length, 4);
    });

    test('pending messages are never cached (filterForCache)', () {
      final messages = [
        msg(
          id: 'pending-1',
          timestamp: t3,
          senderId: currentUid,
          isPending: true,
        ),
        msg(id: 'msg-3', timestamp: t2),
        msg(id: 'msg-2', timestamp: t1),
        msg(id: 'msg-1', timestamp: t0),
      ];

      final cached = filterForCache(messages);
      expect(cached.any((m) => m.isPending), isFalse);
      expect(cached.length, 3);
    });

    test('does not mutate the input existing list', () {
      final existing = [
        msg(id: 'a', timestamp: t1),
        msg(id: 'b', timestamp: t0),
      ];
      final originalLength = existing.length;

      final snapshot = [
        msg(id: 'new-1', timestamp: t2, senderId: otherUid),
        msg(id: 'a', timestamp: t1),
        msg(id: 'b', timestamp: t0),
      ];

      mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(existing.length, originalLength,
          reason: 'existing list must not be mutated');
    });

    test('own messages are not counted as new incoming', () {
      final existing = [
        msg(id: 'old-1', timestamp: t0),
      ];
      final snapshot = [
        msg(
          id: 'my-msg',
          timestamp: t1,
          senderId: currentUid,
          senderName: 'Me',
        ),
        msg(id: 'old-1', timestamp: t0),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.newIncomingIds, isEmpty);
      expect(result.newOwnIds, {'my-msg'});
    });

    test('alsoKnown prevents no-overlap replace', () {
      // Existing has one message, snapshot has no overlap with existing,
      // but alsoKnown contains one of the snapshot ids.
      final existing = [
        msg(id: 'old-1', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'known-in-pending', timestamp: t2, senderId: otherUid),
        msg(id: 'new-1', timestamp: t1, senderId: otherUid),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
        alsoKnown: {'known-in-pending'},
      );

      expect(result.wasReplaced, isFalse,
          reason: 'overlap found via alsoKnown');
      // All three messages should be present.
      expect(result.messages.length, 3);
    });

    test('no-overlap replace preserves pending messages', () {
      // Existing has old stale messages + a pending send.
      final existing = [
        msg(
          id: 'pending-mine',
          timestamp: t5,
          senderId: currentUid,
          isPending: true,
        ),
        msg(id: 'old-2', timestamp: t1),
        msg(id: 'old-1', timestamp: t0),
      ];
      final snapshot = [
        msg(id: 'new-3', timestamp: t4, senderId: adminUid),
        msg(id: 'new-2', timestamp: t3, senderId: adminUid),
        msg(id: 'new-1', timestamp: t2, senderId: adminUid),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isTrue);
      // Pending should survive.
      expect(result.messages.first.id, 'pending-mine');
      // Old stale messages should be gone.
      expect(result.messages.any((m) => m.id == 'old-1'), isFalse);
      final ids = result.messages.map((m) => m.id).toList();
      expect(ids, ['pending-mine', 'new-3', 'new-2', 'new-1']);
    });

    test(
        'existing is ONLY pending messages with unrelated snapshot → normal merge, not replace',
        () {
      // User opens empty chat, sends first message (pending), then an
      // admin message arrives at the same time.
      final existing = [
        msg(
          id: 'pending-mine',
          timestamp: t2,
          senderId: currentUid,
          isPending: true,
        ),
      ];
      final snapshot = [
        msg(id: 'broadcast-1', timestamp: t3, senderId: adminUid),
      ];

      final result = mergeCommunitySnapshot(
        existing: existing,
        snapshot: snapshot,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isFalse,
          reason: 'existing is all pending, no stale cache');
      // Both messages should be present.
      expect(result.messages.length, 2);
      // Pending pinned at front.
      expect(result.messages.first.id, 'pending-mine');
      expect(result.messages.last.id, 'broadcast-1');
      expect(result.newIncomingIds, {'broadcast-1'});
    });

    test('filterForCache respects maxItems', () {
      final messages = List.generate(
        50,
        (i) => msg(id: 'msg-$i', timestamp: Timestamp.fromDate(
          DateTime(2026, 1, 1, 10, i),
        )),
      );

      final cached = filterForCache(messages, maxItems: 30);
      expect(cached.length, 30);
    });
  });
}

