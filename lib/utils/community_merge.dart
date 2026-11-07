// Pure data-manipulation functions for merging community chat snapshots.
// Extracted from CommunityChatScreen for testability.

import '../models/community_chat_message.dart';

/// Result of merging a Firestore snapshot into the existing message list.
class CommunityMergeResult {
  /// The merged message list (sorted: current user's isPending pinned at front,
  /// then timestamp desc, then id desc).
  final List<CommunityChatMessage> messages;

  /// Ids of genuinely new incoming messages (from other users) that should
  /// animate if the user is near the bottom.
  final Set<String> newIncomingIds;

  /// Ids of genuinely new own messages (from the current user) that should
  /// animate.
  final Set<String> newOwnIds;

  /// Whether the existing list was fully replaced because no overlap was found
  /// (stale cache scenario).
  final bool wasReplaced;

  /// Whether the merge produced any change worth a setState.
  final bool changed;

  const CommunityMergeResult({
    required this.messages,
    required this.newIncomingIds,
    required this.newOwnIds,
    required this.wasReplaced,
    required this.changed,
  });
}

/// Merge a Firestore snapshot page into the existing message list.
///
/// Rules:
/// 1. Key every message by `message.id`.
/// 2. If a snapshot message's id already exists, update in-place (edits, status,
///    pending → confirmed). Ignore timestamp differences for pending docs when
///    computing `changed`.
/// 3. New messages from the current user (incl pending): add to `newOwnIds`.
/// 4. New messages from others: add to `newIncomingIds`.
/// 5. If no snapshot id exists in existing + alsoKnown (stale cache),
///    set `wasReplaced = true` and return the snapshot as the list.
/// 6. Window slide protection: ids in existing but not in the snapshot are KEPT
///    (delete is `if false` in rules).
/// 7. After merging, sort: current user's isPending pinned at front, then
///    timestamp desc, id desc.
/// 8. Never mutate inputs.
///
/// [existing] — current `_messages` list (NOT mutated).
/// [snapshot] — the latest snapshot page from Firestore (already sorted desc).
/// [alsoKnown] — ids that are known elsewhere (e.g. in _pendingIncoming)
///               to avoid double-queuing.
/// [currentUid] — the current user's uid.
CommunityMergeResult mergeCommunitySnapshot({
  required List<CommunityChatMessage> existing,
  required List<CommunityChatMessage> snapshot,
  Set<String> alsoKnown = const {},
  String? currentUid,
}) {
  if (snapshot.isEmpty && existing.isEmpty) {
    return const CommunityMergeResult(
      messages: [],
      newIncomingIds: {},
      newOwnIds: {},
      wasReplaced: false,
      changed: false,
    );
  }

  // Build a lookup of existing messages by id.
  final existingById = <String, int>{};
  for (var i = 0; i < existing.length; i++) {
    existingById[existing[i].id] = i;
  }

  // All known ids = existing + alsoKnown.
  final allKnownIds = <String>{...existingById.keys, ...alsoKnown};

  // ── Stale-cache detection ──
  // If the existing list has non-pending messages and NO snapshot id exists in
  // allKnownIds, the cache is so far behind that merging would leave a gap.
  // Replace entirely.
  final hasNonPendingExisting = existing.any((m) => !m.isPending);

  if (hasNonPendingExisting && snapshot.isNotEmpty) {
    final hasOverlap = snapshot.any((msg) => allKnownIds.contains(msg.id));

    if (!hasOverlap) {
      // Full replace — but preserve pending messages (own in-flight sends).
      final preservedPending = existing.where((m) {
        if (!m.isPending) return false;
        // Drop pending messages whose server copy is in the snapshot.
        if (snapshot.any((s) => s.id == m.id)) return false;
        return true;
      }).toList();

      final newIncomingIds = <String>{};
      final newOwnIds = <String>{};
      for (final msg in snapshot) {
        if (msg.senderId == currentUid) {
          newOwnIds.add(msg.id);
        } else {
          newIncomingIds.add(msg.id);
        }
      }

      return CommunityMergeResult(
        messages: _sortMessages([...preservedPending, ...snapshot], currentUid),
        newIncomingIds: newIncomingIds,
        newOwnIds: newOwnIds,
        wasReplaced: true,
        changed: true,
      );
    }
  }

  // ── Normal merge ──
  // Copy existing so we don't mutate the caller's list.
  final messages = List<CommunityChatMessage>.of(existing);
  final newIncomingIds = <String>{};
  final newOwnIds = <String>{};
  var changed = false;

  for (final msg in snapshot) {
    final idx = existingById[msg.id];

    if (idx != null) {
      // Update in-place. Check if it actually changed to avoid needless
      // rebuilds. Ignore timestamp differences for pending → confirmed
      // transitions (pending docs have a local fallback timestamp).
      final old = messages[idx];
      final contentChanged = old.text != msg.text ||
          old.status != msg.status ||
          old.senderName != msg.senderName ||
          old.isPending != msg.isPending ||
          old.type != msg.type;
      // Timestamp change only matters if the content also changed or if
      // a pending message is being confirmed.
      final tsChanged = old.isPending && !msg.isPending;
      if (contentChanged || tsChanged) {
        messages[idx] = msg;
        changed = true;
      }
    } else {
      // Genuinely new message.
      messages.add(msg);
      existingById[msg.id] = messages.length - 1;
      changed = true;

      if (msg.senderId == currentUid) {
        newOwnIds.add(msg.id);
      } else {
        newIncomingIds.add(msg.id);
      }
    }
  }

  // If nothing changed, return early with the existing list reference
  // so the caller can skip setState.
  if (!changed) {
    return CommunityMergeResult(
      messages: existing,
      newIncomingIds: const {},
      newOwnIds: const {},
      wasReplaced: false,
      changed: false,
    );
  }

  return CommunityMergeResult(
    messages: _sortMessages(messages, currentUid),
    newIncomingIds: newIncomingIds,
    newOwnIds: newOwnIds,
    wasReplaced: false,
    changed: true,
  );
}

/// Filter out pending messages for caching.
/// Pending messages have local-only timestamps and should never be persisted.
List<CommunityChatMessage> filterForCache(
  List<CommunityChatMessage> messages, {
  int maxItems = 30,
}) {
  return messages.where((m) => !m.isPending).take(maxItems).toList();
}

/// Sort messages: current user's isPending pinned at front (by timestamp desc),
/// then all others by timestamp desc, id desc.
List<CommunityChatMessage> _sortMessages(
  List<CommunityChatMessage> msgs,
  String? currentUid,
) {
  final pending = <CommunityChatMessage>[];
  final rest = <CommunityChatMessage>[];

  for (final m in msgs) {
    if (m.isPending && m.senderId == currentUid) {
      pending.add(m);
    } else {
      rest.add(m);
    }
  }

  // Sort pending by timestamp desc (most recent first).
  pending.sort((a, b) => _compareDesc(a, b));

  // Sort rest by timestamp desc, then id desc.
  rest.sort((a, b) => _compareDesc(a, b));

  return [...pending, ...rest];
}

/// Compare two messages for descending sort: timestamp desc, then id desc.
int _compareDesc(CommunityChatMessage a, CommunityChatMessage b) {
  final tsA = a.timestamp.toDate();
  final tsB = b.timestamp.toDate();

  final tsComp = tsB.compareTo(tsA);
  if (tsComp != 0) return tsComp;

  // Tie-break by id desc.
  return b.id.compareTo(a.id);
}

