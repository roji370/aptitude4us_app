import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/attachment_service.dart';

class CommunityChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String text;
  final Timestamp timestamp;
  final String status;
  final String type;
  final bool isCommunity;
  final AttachmentData? attachment;

  CommunityChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    required this.status,
    required this.type,
    this.isCommunity = true,
    this.attachment,
  });

  factory CommunityChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    AttachmentData? attachment;
    if (data['attachment'] != null) {
      attachment = AttachmentData.fromMap(
        data['attachment'] as Map<String, dynamic>,
      );
    }

    return CommunityChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      receiverId: data['receiverId'] ?? 'COMMUNITY',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      status: data['status'] ?? 'sent',
      type: data['type'] ?? 'text',
      isCommunity: data['isCommunity'] ?? true,
      attachment: attachment,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'status': status,
      'type': type,
      'isCommunity': isCommunity,
      'attachment': attachment?.toMap(),
    };
  }

  /// Check if message has an attachment
  bool get hasAttachment => attachment != null;

  /// Get attachment type for easy access
  AttachmentType? get attachmentType => attachment?.type;

  /// Check if message is pure text (no attachment)
  bool get isTextOnly => attachment == null && text.isNotEmpty;

  /// Check if message is attachment only (no text)
  bool get isAttachmentOnly => attachment != null && text.isEmpty;
}
