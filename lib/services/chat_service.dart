import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import '../services/attachment_service.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../utils/logger.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  final int _messagesPerPage = 20; // Number of messages to load per batch

  // ── Static in-memory cache for instant chat open ──
  static List<Map<String, dynamic>> _cache = [];

  /// Returns a shallow copy of the cached messages (newest first).
  static List<Map<String, dynamic>> get cachedMessages => List.of(_cache);

  /// Update the cache with the latest messages (keeps at most 30).
  /// Filters out any unconfirmed temp-* or failed messages so the next
  /// screen open never shows stale optimistic bubbles.
  static void updateCache(List<Map<String, dynamic>> m) {
    _cache = m
        .where((msg) {
          final id = msg['id'] as String?;
          if (id != null && id.startsWith('temp-')) return false;
          if (msg['status'] == 'failed') return false;
          return true;
        })
        .take(30)
        .toList();
  }

  /// Clear the cache (call on sign-out so one user never sees another's data).
  static void clearCache() => _cache = [];

  /// Pre-fetch the first page of messages into the static cache.
  /// Safe to call from splash / home screen on a fire-and-forget basis.
  Future<void> prefetch() async {
    try {
      _cache = await getMessagesPaginated(limit: 20);
    } catch (e) {
      Logger.w('ChatService.prefetch failed (non-blocking): $e');
    }
  }

  // Get the actual user display name from UserModel
  Future<String> _getUserDisplayName() async {
    try {
      // Try to get from cached user data first (faster)
      final cachedUser = await AuthPersistenceService.getUserData();
      if (cachedUser != null && cachedUser.displayName.isNotEmpty) {
        return cachedUser.displayName;
      }

      // Fallback to getting fresh user data from Firestore
      final userData = await _authService.getUserData();
      if (userData != null && userData.displayName.isNotEmpty) {
        return userData.displayName;
      }

      // Final fallback to Firebase Auth displayName
      final user = _auth.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        return user.displayName!;
      }

      // Last resort fallback
      return 'Student';
    } catch (e) {
      Logger.e('Error getting user display name: $e');
      return 'Student';
    }
  }

  // Get messages with pagination using compound cursor (timestamp + docId)
  Future<List<Map<String, dynamic>>> getMessagesPaginated({
    Timestamp? lastTimestamp,
    String? lastId,
    int limit = 20,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      // Create queries for each message type
      List<Query> queries = [
        // Messages sent TO student
        _createPaginatedQuery(
          field: 'receiverId',
          value: user.uid,
          lastTimestamp: lastTimestamp,
          lastId: lastId,
          limit: limit,
        ),

        // Messages sent BY student
        _createPaginatedQuery(
          field: 'senderId',
          value: user.uid,
          lastTimestamp: lastTimestamp,
          lastId: lastId,
          limit: limit,
        ),

        // Broadcast messages
        _createPaginatedQuery(
          field: 'receiverId',
          value: 'ALL',
          lastTimestamp: lastTimestamp,
          lastId: lastId,
          limit: limit,
        ),
      ];

      // Execute all queries
      List<QuerySnapshot> snapshots = await Future.wait(
        queries.map((query) => query.get()),
      );

      // Process and combine results
      List<Map<String, dynamic>> allMessages = [];
      for (var snapshot in snapshots) {
        allMessages.addAll(_processQuerySnapshot(snapshot));
      }

      // Deduplicate by message ID (safety net)
      final Map<String, Map<String, dynamic>> uniqueMessages = {};
      for (var msg in allMessages) {
        uniqueMessages[msg['id']] = msg;
      }

      // Convert to list and sort by timestamp desc, then docId desc
      final result = uniqueMessages.values.toList();
      result.sort((a, b) {
        final tsCompare = b['timestamp'].compareTo(a['timestamp']);
        if (tsCompare != 0) return tsCompare;
        return (b['id'] as String).compareTo(a['id'] as String);
      });

      // Limit to the requested number.
      // Messages fetched but trimmed are older than the new cursor, so the
      // next page will pick them up correctly — no gaps, no duplicates.
      return result.take(limit).toList();
    } catch (e) {
      Logger.e('Error fetching paginated messages: $e');
      return [];
    }
  }

  // Create a query with compound cursor pagination
  Query _createPaginatedQuery({
    required String field,
    required dynamic value,
    Timestamp? lastTimestamp,
    String? lastId,
    required int limit,
  }) {
    Query query = _firestore
        .collection('messages')
        .where(field, isEqualTo: value)
        .orderBy('timestamp', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit);

    if (lastTimestamp != null && lastId != null) {
      query = query.startAfter([lastTimestamp, lastId]);
    }

    return query;
  }

  /// Lightweight stream that emits whenever the newest message for the current
  /// user changes. Uses `limit(1)` per query for minimal Firestore reads.
  /// Each emission is a record with the doc's id, senderId, and clientId
  /// so the listener can make a targeted skip decision.
  Stream<({String id, String? senderId, String? clientId})?> newestMessageStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    Stream<({String id, String? senderId, String? clientId})?> latestDoc(
        String field, dynamic value) {
      return _firestore
          .collection('messages')
          .where(field, isEqualTo: value)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .map((snap) {
        if (snap.docs.isEmpty) return null;
        final doc = snap.docs.first;
        final data = doc.data();
        return (
          id: doc.id,
          senderId: data['senderId'] as String?,
          clientId: data['clientId'] as String?,
        );
      });
    }

    // Merge all three — emits whenever ANY stream fires a change.
    return Rx.merge([
      latestDoc('receiverId', user.uid),
      latestDoc('senderId', user.uid),
      latestDoc('receiverId', 'ALL'),
    ]);
  }

  // Legacy method for backward compatibility
  Stream<List<Map<String, dynamic>>> getMessages() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Create two separate queries and combine them
    // 1. Messages sent TO student (receiverId is student's UID)
    final receivedMessagesStream = _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(_messagesPerPage)
        .snapshots()
        .map((snapshot) => _processQuerySnapshot(snapshot));

    // 2. Messages sent BY student (senderId is student's UID)
    final sentMessagesStream = _firestore
        .collection('messages')
        .where('senderId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(_messagesPerPage)
        .snapshots()
        .map((snapshot) => _processQuerySnapshot(snapshot));

    // 3. Broadcast messages (receiverId is "ALL")
    final broadcastMessagesStream = _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: 'ALL')
        .orderBy('timestamp', descending: true)
        .limit(_messagesPerPage)
        .snapshots()
        .map((snapshot) => _processQuerySnapshot(snapshot));

    // Combine all streams into one
    return Rx.combineLatest3(
      receivedMessagesStream,
      sentMessagesStream,
      broadcastMessagesStream,
      (
        List<Map<String, dynamic>> received,
        List<Map<String, dynamic>> sent,
        List<Map<String, dynamic>> broadcasts,
      ) {
        // Combine all messages
        final allMessages = [...received, ...sent, ...broadcasts];

        // Deduplicate by message ID
        final Map<String, Map<String, dynamic>> uniqueMessages = {};
        for (var msg in allMessages) {
          uniqueMessages[msg['id']] = msg;
        }

        // Convert to list and sort by timestamp
        final result = uniqueMessages.values.toList();
        result.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        return result;
      },
    );
  }

  // Helper to process query snapshots
  List<Map<String, dynamic>> _processQuerySnapshot(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        ...data,
        'timestamp': data['timestamp']?.toDate() ?? DateTime.now(),
        // Keep the raw Firestore Timestamp for compound cursor pagination.
        '_firestoreTimestamp': data['timestamp'],
      };
    }).toList();
  }

  // Send a text message to admin
  Future<Map<String, dynamic>> sendMessage({
    required String text,
    String? replyToMessageId,
    String? clientId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return {'success': false, 'error': 'User not logged in'};
    }

    try {
      // Get the actual user display name
      final senderName = await _getUserDisplayName();

      // Create message document
      final messageData = {
        'text': text,
        'senderId': user.uid,
        'senderName': senderName,
        'receiverId': 'ADMIN', // Send to admin
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': 'text',
      };

      // Persist clientId so the fetch path can match temp → confirmed.
      if (clientId != null) {
        messageData['clientId'] = clientId;
      }

      // Add reply information if provided
      if (replyToMessageId != null) {
        messageData['replyToMessageId'] = replyToMessageId;
      }

      // Add to Firestore
      final docRef = await _firestore.collection('messages').add(messageData);

      return {'success': true, 'messageId': docRef.id};
    } catch (e) {
      Logger.e('Error sending message: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Send a message with attachment to admin
  Future<Map<String, dynamic>> sendMessageWithAttachment({
    required AttachmentData attachment,
    String? text,
    String? replyToMessageId,
    String? clientId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return {'success': false, 'error': 'User not logged in'};
    }

    try {
      // Get the actual user display name
      final senderName = await _getUserDisplayName();

      final messageType =
          attachment.type == AttachmentType.image
              ? 'image'
              : attachment.type == AttachmentType.video
              ? 'video'
              : attachment.type == AttachmentType.document
              ? 'document'
              : 'attachment';

      // Create message document
      final messageData = {
        'text': text ?? '',
        'senderId': user.uid,
        'senderName': senderName,
        'receiverId': 'ADMIN', // Send to admin
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': messageType,
        'attachment': attachment.toMap(),
      };

      // Persist clientId so the fetch path can match temp → confirmed.
      if (clientId != null) {
        messageData['clientId'] = clientId;
      }

      // Add reply information if provided
      if (replyToMessageId != null) {
        messageData['replyToMessageId'] = replyToMessageId;
      }

      // Add to Firestore
      final docRef = await _firestore.collection('messages').add(messageData);

      return {'success': true, 'messageId': docRef.id};
    } catch (e) {
      Logger.e('Error sending message with attachment: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Mark message as read
  Future<bool> markMessageAsRead(String messageId) async {
    try {
      await _firestore.collection('messages').doc(messageId).update({
        'status': 'read',
        'statusTimestamp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      Logger.e('Error marking message as read: $e');
      return false;
    }
  }

  // Get admin information
  Future<Map<String, dynamic>?> getAdminInfo() async {
    try {
      final querySnapshot =
          await _firestore
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .limit(1)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        final adminDoc = querySnapshot.docs.first;
        return {'id': adminDoc.id, ...adminDoc.data()};
      }
      return null;
    } catch (e) {
      Logger.e('Error getting admin info: $e');
      return null;
    }
  }
}
