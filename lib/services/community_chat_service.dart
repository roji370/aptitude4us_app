import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_chat_message.dart';
import '../services/attachment_service.dart';
import '../utils/logger.dart';

class CommunityChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'communityChat';

  // Get stream of community chat messages
  Stream<List<CommunityChatMessage>> getCommunityMessages() {
    return _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => CommunityChatMessage.fromFirestore(doc))
                  .toList(),
        );
  }

  // Send a new text message to community chat
  Future<void> sendMessage({
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    try {
      await _firestore.collection(_collection).add({
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': 'COMMUNITY',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': 'text',
        'isCommunity': true,
      });
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

      await _firestore.collection(_collection).add({
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': 'COMMUNITY',
        'text': text ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': messageType,
        'isCommunity': true,
        'attachment': attachment.toMap(),
      });
    } catch (e) {
      throw Exception('Failed to send message with attachment: $e');
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
              'Welcome to Student Details! 👋 Feel free to start a conversation with your fellow students and admins.',
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
