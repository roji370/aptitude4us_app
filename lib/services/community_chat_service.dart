import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_chat_message.dart';
import '../services/attachment_service.dart';
import '../utils/logger.dart';

class CommunityChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'communityChat';

  // ── Static in-memory cache for instant chat open ──
  static List<CommunityChatMessage> _cache = [];

  /// Returns a shallow copy of the cached messages (newest first).
  static List<CommunityChatMessage> get cachedMessages => List.of(_cache);

  /// Update the cache with the latest messages (keeps at most 30, non-pending).
  static void updateCache(List<CommunityChatMessage> messages) {
    _cache = messages.where((m) => !m.isPending).take(30).toList();
  }

  /// Clear the cache (call on sign-out).
  static void clearCache() => _cache = [];

  /// Pre-fetch the first page of messages into the static cache.
  /// Safe to call from splash / home screen on a fire-and-forget basis.
  Future<void> prefetch() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      _cache = snapshot.docs
          .map((doc) => CommunityChatMessage.fromFirestore(doc))
          .toList();
    } catch (e) {
      Logger.w('CommunityChatService.prefetch failed (non-blocking): $e');
    }
  }

  // ── Live stream with a bounded window ──

  /// Get a live stream of the newest community chat messages.
  /// Returns a stream of QuerySnapshot so the screen can use
  /// StreamSubscription and process metadata per-doc.
  Stream<QuerySnapshot<Map<String, dynamic>>> getCommunityMessagesStream({
    int limit = 30,
  }) {
    return _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Pagination ──

  /// Fetch one page of older messages, using a compound cursor
  /// (timestamp + docId) to avoid gaps or duplicates.
  Future<List<CommunityChatMessage>> getOlderMessages({
    required Timestamp beforeTimestamp,
    required String beforeId,
    int limit = 30,
  }) async {
    // Primary cursor: timestamp < beforeTimestamp.
    final byTimestamp = await _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .where('timestamp', isLessThan: beforeTimestamp)
        .limit(limit)
        .get();

    // Edge case: if there are messages with the same timestamp as the cursor
    // but a different (earlier) docId, they'd be missed. Fetch those too.
    final sameTsQuery = await _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .where('timestamp', isEqualTo: beforeTimestamp)
        .get();

    final sameTsDocs = sameTsQuery.docs
        .where((doc) => doc.id.compareTo(beforeId) < 0)
        .toList();

    // Merge, deduplicate, sort, and limit.
    final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in sameTsDocs) {
      allDocs[doc.id] = doc;
    }
    for (final doc in byTimestamp.docs) {
      allDocs[doc.id] = doc;
    }

    final sorted = allDocs.values.toList()
      ..sort((a, b) {
        final tsA = a.data()['timestamp'] as Timestamp?;
        final tsB = b.data()['timestamp'] as Timestamp?;
        if (tsA != null && tsB != null) {
          final cmp = tsB.compareTo(tsA);
          if (cmp != 0) return cmp;
        }
        return b.id.compareTo(a.id);
      });

    return sorted
        .take(limit)
        .map((doc) => CommunityChatMessage.fromFirestore(doc))
        .toList();
  }

  // Send a new text message to community chat
  Future<void> sendMessage({
    required String senderId,
    required String senderName,
    required String text,
    String? replyToMessageId,
  }) async {
    try {
      final messageData = {
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': 'COMMUNITY',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': 'text',
        'isCommunity': true,
      };

      // Add reply information if provided
      if (replyToMessageId != null) {
        messageData['replyToMessageId'] = replyToMessageId;
      }

      // Don't await — let the local write appear immediately in the snapshot.
      // The doc id is generated client-side by add(), so the pending doc's id
      // is already stable.
      _firestore.collection(_collection).add(messageData);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Send a message with attachment to community chat
  Future<void> sendMessageWithAttachment({
    required String senderId,
    required String senderName,
    required AttachmentData attachment,
    String? text,
    String? replyToMessageId,
  }) async {
    try {
      final messageType =
          attachment.type == AttachmentType.image
              ? 'image'
              : attachment.type == AttachmentType.video
              ? 'video'
              : attachment.type == AttachmentType.document
              ? 'document'
              : 'attachment';

      final messageData = {
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': 'COMMUNITY',
        'text': text ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': messageType,
        'isCommunity': true,
        'attachment': attachment.toMap(),
      };

      // Add reply information if provided
      if (replyToMessageId != null) {
        messageData['replyToMessageId'] = replyToMessageId;
      }

      await _firestore.collection(_collection).add(messageData);
    } catch (e) {
      throw Exception('Failed to send message with attachment: $e');
    }
  }

  // Get a specific message by ID
  Future<CommunityChatMessage?> getMessageById(String messageId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(messageId).get();
      if (doc.exists) {
        return CommunityChatMessage.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      Logger.e('Error getting message by ID: $e');
      return null;
    }
  }

  // Update message status
  Future<void> updateMessageStatus({
    required String messageId,
    required String status,
  }) async {
    try {
      await _firestore.collection(_collection).doc(messageId).update({
        'status': status,
      });
    } catch (e) {
      throw Exception('Failed to update message status: $e');
    }
  }

  // Optional: Add system welcome message if collection is empty
  Future<void> addWelcomeMessageIfNeeded() async {
    try {
      final messages = await _firestore.collection(_collection).limit(1).get();
      if (messages.docs.isEmpty) {
        await _firestore.collection(_collection).add({
          'senderId': 'system',
          'senderName': 'System',
          'receiverId': 'COMMUNITY',
          'text':
              'Welcome to Community Chat! 👋 Feel free to start a conversation with your fellow students and admins.',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'sent',
          'type': 'text',
          'isCommunity': true,
        });
      }
    } catch (e) {
      Logger.e('Error adding welcome message: $e');
    }
  }
}
