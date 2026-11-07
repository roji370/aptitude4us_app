import 'package:flutter_test/flutter_test.dart';
import 'package:aptitude4us_academy/utils/chat_merge.dart';

/// Helper to build a message map for testing.
Map<String, dynamic> msg({
  required String id,
  String? clientId,
  required DateTime timestamp,
  String senderId = 'admin',
}) {
  return {
    'id': id,
    if (clientId != null) 'clientId': clientId,
    'timestamp': timestamp,
    'senderId': senderId,
  };
}

void main() {
  const currentUid = 'user-1';
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);
  final t1 = DateTime(2026, 1, 1, 12, 0, 1);
  final t2 = DateTime(2026, 1, 1, 12, 0, 2);
  final t3 = DateTime(2026, 1, 1, 12, 0, 3);
  final t4 = DateTime(2026, 1, 1, 12, 0, 4);
  final t5 = DateTime(2026, 1, 1, 12, 0, 5);

  group('mergeFetchedPage', () {
    test('temp bubble and server copy share a clientId', () {
      // Existing: a temp bubble from the user.
      final existing = [
        msg(
          id: 'temp-c-123',
          clientId: 'c-123',
          timestamp: t2,
          senderId: currentUid,
        ),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
        msg(id: 'msg-0', timestamp: t0, senderId: 'admin'),
      ];

      // Fetched: the server copy with the real id + same clientId, plus msg-1.
      final fetched = [
        msg(
          id: 'real-id-for-123',
          clientId: 'c-123',
          timestamp: t2,
          senderId: currentUid,
        ),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      // The temp bubble should be replaced by the server copy.
      expect(result.messages.any((m) => m['id'] == 'temp-c-123'), isFalse,
          reason: 'temp bubble should be gone');
      expect(result.messages.any((m) => m['id'] == 'real-id-for-123'), isTrue,
          reason: 'server copy should be present');

      // The server copy should carry the clientId for stable key.
      final serverCopy =
          result.messages.firstWhere((m) => m['id'] == 'real-id-for-123');
      expect(serverCopy['clientId'], 'c-123');

      // msg-0 (from older page) should still be there.
      expect(result.messages.any((m) => m['id'] == 'msg-0'), isTrue,
          reason: 'older page messages should be preserved');

      // No new incoming keys (this was our own message).
      expect(result.newIncomingKeys, isEmpty);
      expect(result.wasReplaced, isFalse);
    });

    test('no overlap between fetched and existing → full replace', () {
      // Existing: old messages from a stale cache.
      final existing = [
        msg(id: 'old-3', timestamp: t2, senderId: 'admin'),
        msg(id: 'old-2', timestamp: t1, senderId: 'admin'),
        msg(id: 'old-1', timestamp: t0, senderId: 'admin'),
      ];

      // Fetched: completely new messages, no ids overlap.
      final fetched = [
        msg(id: 'new-3', timestamp: t5, senderId: 'admin'),
        msg(id: 'new-2', timestamp: t4, senderId: 'admin'),
        msg(id: 'new-1', timestamp: t3, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isTrue,
          reason: 'should replace when no overlap');
      // Old messages should be gone.
      expect(result.messages.any((m) => m['id'] == 'old-1'), isFalse);
      // New messages should be present, sorted desc.
      expect(result.messages.map((m) => m['id']).toList(),
          ['new-3', 'new-2', 'new-1']);
      // All are incoming (from admin).
      expect(result.newIncomingKeys, hasLength(3));
    });

    test('three new messages in one refresh, order preserved', () {
      // Existing: some messages.
      final existing = [
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
        msg(id: 'msg-0', timestamp: t0, senderId: 'admin'),
      ];

      // Fetched: 3 new + 1 existing overlap (msg-2).
      final fetched = [
        msg(id: 'msg-5', timestamp: t5, senderId: 'admin'),
        msg(id: 'msg-4', timestamp: t4, senderId: 'admin'),
        msg(id: 'msg-3', timestamp: t3, senderId: 'admin'),
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isFalse);
      // Should have all 6 messages, sorted desc.
      final ids = result.messages.map((m) => m['id']).toList();
      expect(ids, ['msg-5', 'msg-4', 'msg-3', 'msg-2', 'msg-1', 'msg-0']);

      // 3 new incoming keys.
      expect(result.newIncomingKeys, hasLength(3));
      expect(result.newIncomingKeys, containsAll(['msg-5', 'msg-4', 'msg-3']));
    });

    test('fetched list identical to existing → no changes', () {
      final existing = [
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
        msg(id: 'msg-0', timestamp: t0, senderId: 'admin'),
      ];

      final fetched = [
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
        msg(id: 'msg-0', timestamp: t0, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isFalse);
      expect(result.newIncomingKeys, isEmpty);
      expect(result.messages.length, 3);
      expect(result.messages.map((m) => m['id']).toList(),
          ['msg-2', 'msg-1', 'msg-0']);
    });

    test('same timestamp, different ids — sorted by id desc', () {
      // Two messages at the exact same timestamp.
      final existing = [
        msg(id: 'aaa', timestamp: t1, senderId: 'admin'),
      ];

      final fetched = [
        msg(id: 'zzz', timestamp: t1, senderId: 'admin'),
        msg(id: 'aaa', timestamp: t1, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isFalse);
      // 'zzz' > 'aaa' so zzz comes first in desc order.
      final ids = result.messages.map((m) => m['id']).toList();
      expect(ids, ['zzz', 'aaa']);
    });

    test('temp-* bubbles pinned at front of sorted list', () {
      final existing = [
        msg(
          id: 'temp-c-abc',
          clientId: 'c-abc',
          timestamp: t3,
          senderId: currentUid,
        ),
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      // Fetched: one new message at t4 (newer than the temp), plus msg-2.
      final fetched = [
        msg(id: 'msg-3', timestamp: t4, senderId: 'admin'),
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      // temp should be pinned at front even though msg-3 has a later timestamp.
      expect(result.messages.first['id'], 'temp-c-abc',
          reason: 'temp-* should be pinned at front');
      // Then msg-3, msg-2, msg-1.
      final ids = result.messages.map((m) => m['id']).toList();
      expect(ids, ['temp-c-abc', 'msg-3', 'msg-2', 'msg-1']);
    });

    test('own messages are not counted as new incoming', () {
      final existing = [
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      final fetched = [
        msg(id: 'msg-2', timestamp: t2, senderId: currentUid), // own message
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      // msg-2 is from us, so it should NOT be in newIncomingKeys.
      expect(result.newIncomingKeys, isEmpty);
    });

    test('empty existing list with fetched data', () {
      final existing = <Map<String, dynamic>>[];
      final fetched = [
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isFalse,
          reason: 'empty list should not trigger wasReplaced');
      expect(result.messages.length, 2);
      expect(result.newIncomingKeys, hasLength(2));
    });

    test('does not mutate the input existing list', () {
      final existing = [
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];
      final originalLength = existing.length;
      final originalId = existing[0]['id'];

      final fetched = [
        msg(id: 'msg-2', timestamp: t2, senderId: 'admin'),
        msg(id: 'msg-1', timestamp: t1, senderId: 'admin'),
      ];

      mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(existing.length, originalLength,
          reason: 'should not mutate existing list');
      expect(existing[0]['id'], originalId);
    });

    test('no-overlap replace preserves in-flight temp-* bubbles', () {
      // Existing list has both regular messages (stale cache) and a temp.
      // Fetched page has no overlap with the regular messages.
      final existing = [
        msg(
          id: 'temp-c-999',
          clientId: 'c-999',
          timestamp: t5,
          senderId: currentUid,
        ),
        msg(id: 'old-2', timestamp: t1, senderId: 'admin'),
        msg(id: 'old-1', timestamp: t0, senderId: 'admin'),
      ];

      // Fetched page has completely new messages (no overlap with old-*).
      final fetched = [
        msg(id: 'new-3', timestamp: t4, senderId: 'admin'),
        msg(id: 'new-2', timestamp: t3, senderId: 'admin'),
        msg(id: 'new-1', timestamp: t2, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      expect(result.wasReplaced, isTrue,
          reason: 'no overlap with non-temp messages');
      // The temp bubble should be preserved and pinned at the front.
      expect(result.messages.first['id'], 'temp-c-999',
          reason: 'in-flight temp should survive the replace');
      // All fetched messages should be present, old stale ones gone.
      final ids = result.messages.map((m) => m['id']).toList();
      expect(ids, ['temp-c-999', 'new-3', 'new-2', 'new-1']);
      // Old stale messages should be removed.
      expect(result.messages.any((m) => m['id'] == 'old-1'), isFalse);
      expect(result.messages.any((m) => m['id'] == 'old-2'), isFalse);
      // The fetched messages are incoming from admin.
      expect(result.newIncomingKeys, hasLength(3));
    });

    test('no-overlap replace with matching temp clientId reconciles', () {
      // Edge case: the temp message's server copy is in the fetched page
      // (it carries the same clientId).
      final inFlightTemps = [
        msg(
          id: 'temp-c-777',
          clientId: 'c-777',
          timestamp: t4,
          senderId: currentUid,
        ),
      ];

      final fetched = [
        msg(
          id: 'real-777',
          clientId: 'c-777',
          timestamp: t4,
          senderId: currentUid,
        ),
        msg(id: 'new-2', timestamp: t3, senderId: 'admin'),
        msg(id: 'new-1', timestamp: t2, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: inFlightTemps,
        fetched: fetched,
        currentUid: currentUid,
      );

      // The temp should be replaced by the server copy.
      expect(result.messages.any((m) => m['id'] == 'temp-c-777'), isFalse);
      expect(result.messages.any((m) => m['id'] == 'real-777'), isTrue);
      // Server copy keeps the clientId.
      final serverCopy =
          result.messages.firstWhere((m) => m['id'] == 'real-777');
      expect(serverCopy['clientId'], 'c-777');
      // All three messages present.
      expect(result.messages.length, 3);
    });

    test('existing is ONLY temp-* messages with unrelated fetched → normal merge, not replace', () {
      // User opens empty chat, sends first message (temp bubble),
      // then a broadcast or admin message arrives at the same time.
      final existing = [
        msg(
          id: 'temp-c-abc',
          clientId: 'c-abc',
          timestamp: t2,
          senderId: currentUid,
        ),
      ];

      final fetched = [
        msg(id: 'broadcast-1', timestamp: t3, senderId: 'admin'),
      ];

      final result = mergeFetchedPage(
        existing: existing,
        fetched: fetched,
        currentUid: currentUid,
      );

      // Should NOT replace — existing is all temps, no stale cache.
      expect(result.wasReplaced, isFalse,
          reason: 'all-temp existing should not trigger wasReplaced');
      // Temp pinned at front, fetched appended.
      final ids = result.messages.map((m) => m['id']).toList();
      expect(ids, ['temp-c-abc', 'broadcast-1']);
      // The admin message is new incoming.
      expect(result.newIncomingKeys, ['broadcast-1']);
    });
  });
}
