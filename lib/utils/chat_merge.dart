// Pure data-manipulation functions for merging chat messages.
// Extracted from ChatScreen for testability.

/// Result of merging a fetched page into the existing message list.
class MergeResult {
  /// The merged message list (sorted: temp-* pinned at front, then timestamp
  /// desc, then id desc).
  final List<Map<String, dynamic>> messages;

  /// Keys (clientId ?? id) of genuinely new incoming messages that should
  /// animate if the user is near the bottom.
  final List<String> newIncomingKeys;

  /// Whether the existing list was fully replaced because no overlap was found
  /// (stale cache scenario).
  final bool wasReplaced;

  const MergeResult({
    required this.messages,
    required this.newIncomingKeys,
    required this.wasReplaced,
  });
}

/// Merge a fetched page of messages into the existing list.
///
/// Rules:
/// 1. Key every message by `clientId ?? id`.
/// 2. If a fetched message's `clientId` matches an in-flight `temp-*` bubble,
///    replace the temp bubble with the server copy (keeps the key stable).
/// 3. If a fetched message's key already exists, update it in-place.
/// 4. If no fetched key overlaps the existing list at all (stale cache),
///    replace the list entirely.
/// 5. Genuinely new messages are collected (for animation / pending pill).
/// 6. After merging, sort: in-flight temp-* pinned at front, then by
///    timestamp desc, id desc.
///
/// [existing] — current `_messages` list (will NOT be mutated; a copy is made).
/// [fetched] — page-1 results from Firestore, already sorted timestamp desc.
/// [currentUid] — the current user's uid, so we can distinguish incoming vs own.
MergeResult mergeFetchedPage({
  required List<Map<String, dynamic>> existing,
  required List<Map<String, dynamic>> fetched,
  required String? currentUid,
}) {
  // Work on a copy so we don't mutate the caller's list.
  final messages = existing.map((m) => Map<String, dynamic>.of(m)).toList();

  // Build a lookup of what we already have, keyed by (clientId ?? id).
  final existingByKey = <String, int>{};
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final key = _msgKey(m);
    if (key.isNotEmpty) existingByKey[key] = i;
  }

  // Collect the clientIds of in-flight temp-* bubbles.
  final inFlightClientIds = <String>{};
  for (final m in messages) {
    final id = m['id'] as String?;
    final cid = m['clientId'] as String?;
    if (cid != null && id != null && id.startsWith('temp-')) {
      inFlightClientIds.add(cid);
    }
  }

  // ── Stale-cache detection ──
  // If the existing list has non-temp messages and NO fetched key (clientId ?? id)
  // matches any existing key, the cache is so far behind that merging would
  // leave a gap. Replace entirely.
  // Only consider non-temp messages for the overlap check — temp-* bubbles
  // are in-flight sends that naturally have no overlap with fetched messages.
  final hasNonTempExisting = messages.any((m) {
    final id = m['id'] as String?;
    return id == null || !id.startsWith('temp-');
  });

  if (hasNonTempExisting && fetched.isNotEmpty) {
    final hasOverlap = fetched.any((msg) {
      final key = _msgKey(msg);
      if (key.isEmpty) return false;
      if (existingByKey.containsKey(key)) return true;
      // Also check if a fetched message's clientId matches an in-flight temp.
      final cid = msg['clientId'] as String?;
      if (cid != null && inFlightClientIds.contains(cid)) return true;
      return false;
    });

    if (!hasOverlap) {
      // Full replace — but preserve in-flight temp-* bubbles.
      final preservedTemps = messages.where((m) {
        final id = m['id'] as String?;
        final cid = m['clientId'] as String?;
        if (id == null || !id.startsWith('temp-')) return false;
        // Drop temps whose server copy is in the fetched page.
        if (cid != null) {
          final serverCopyExists = fetched.any(
            (f) => f['clientId'] == cid,
          );
          if (serverCopyExists) return false;
        }
        return true;
      }).toList();

      final newKeys = <String>[];
      for (final msg in fetched) {
        if (msg['senderId'] != currentUid) {
          final key = _msgKey(msg);
          if (key.isNotEmpty) newKeys.add(key);
        }
      }
      return MergeResult(
        messages: _sortMessages([...preservedTemps, ...fetched]),
        newIncomingKeys: newKeys,
        wasReplaced: true,
      );
    }
  }

  // ── Normal merge ──
  final newIncomingKeys = <String>[];

  for (final msg in fetched) {
    final msgId = msg['id'] as String?;
    final msgClientId = msg['clientId'] as String?;
    final key = _msgKey(msg);

    if (key.isEmpty) continue;

    // Check if this server message matches an in-flight temp bubble.
    if (msgClientId != null && inFlightClientIds.contains(msgClientId)) {
      final idx = existingByKey[msgClientId];
      if (idx != null) {
        messages[idx] = Map<String, dynamic>.of(msg);
        inFlightClientIds.remove(msgClientId);
        // Update the key→index mapping for the new key.
        if (msgId != null && msgId != msgClientId) {
          existingByKey[msgId] = idx;
        }
        continue;
      }
    }

    // Check if this message already exists (by its natural key).
    final idx = existingByKey[key];
    if (idx != null) {
      // Update in-place with the fresh version from server.
      messages[idx] = Map<String, dynamic>.of(msg);
    } else {
      // Genuinely new message.
      messages.add(msg);
      existingByKey[key] = messages.length - 1;

      if (msg['senderId'] != currentUid && msgId != null) {
        newIncomingKeys.add(_msgKey(msg));
      }
    }
  }

  return MergeResult(
    messages: _sortMessages(messages),
    newIncomingKeys: newIncomingKeys,
    wasReplaced: false,
  );
}

/// Canonical key for a message: clientId ?? id.
String _msgKey(Map<String, dynamic> m) {
  return (m['clientId'] as String?) ?? (m['id'] as String?) ?? '';
}

/// Sort messages: in-flight temp-* pinned at front (by timestamp desc),
/// then all others by timestamp desc, then id desc.
List<Map<String, dynamic>> _sortMessages(List<Map<String, dynamic>> msgs) {
  final temps = <Map<String, dynamic>>[];
  final rest = <Map<String, dynamic>>[];

  for (final m in msgs) {
    final id = m['id'] as String?;
    if (id != null && id.startsWith('temp-')) {
      temps.add(m);
    } else {
      rest.add(m);
    }
  }

  // Sort temps by timestamp desc (most recent temp first).
  temps.sort((a, b) => _compareDesc(a, b));

  // Sort rest by timestamp desc, then id desc.
  rest.sort((a, b) => _compareDesc(a, b));

  return [...temps, ...rest];
}

/// Compare two messages for descending sort: timestamp desc, then id desc.
int _compareDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final tsA = _extractTimestamp(a);
  final tsB = _extractTimestamp(b);

  final tsComp = tsB.compareTo(tsA);
  if (tsComp != 0) return tsComp;

  // Tie-break by id desc.
  final idA = (a['id'] as String?) ?? '';
  final idB = (b['id'] as String?) ?? '';
  return idB.compareTo(idA);
}

/// Extract a comparable timestamp from a message.
/// Handles DateTime, Firestore Timestamp (via microsecondsSinceEpoch), or
/// falls back to epoch 0.
DateTime _extractTimestamp(Map<String, dynamic> m) {
  final ts = m['timestamp'];
  if (ts is DateTime) return ts;
  // Firestore Timestamp — call toDate().
  if (ts != null) {
    try {
      return (ts as dynamic).toDate() as DateTime;
    } catch (_) {}
  }
  return DateTime.fromMicrosecondsSinceEpoch(0);
}

