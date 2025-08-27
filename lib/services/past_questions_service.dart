import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/past_questions_message.dart';
import '../services/attachment_service.dart';
import '../utils/logger.dart';

class PastQuestionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'pastQuestions';

  // Get stream of past questions messages
  Stream<List<PastQuestionsMessage>> getPastQuestionsMessages() {
    return _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => PastQuestionsMessage.fromFirestore(doc))
                  .toList(),
        );
  }

  // Send a new text message to past questions
  Future<void> sendMessage({
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    try {
      await _firestore.collection(_collection).add({
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': 'PAST_QUESTIONS',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': 'text',
        'isPastQuestions': true,
      });
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  // Send a message with attachment to past questions
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
        'receiverId': 'PAST_QUESTIONS',
        'text': text ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'type': messageType,
        'isPastQuestions': true,
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
          'receiverId': 'PAST_QUESTIONS',
          'text':
              'Welcome to Past Questions! 📚 Share and discuss past exam questions, practice problems, and study materials with your fellow students.',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'sent',
          'type': 'text',
          'isPastQuestions': true,
        });
      }
    } catch (e) {
      Logger.e('Error adding welcome message: $e');
    }
  }
}

