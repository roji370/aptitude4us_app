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
  final String? replyToMessageId;
  final CommunityChatMessage? replyToMessage;

  /// Whether this message has pending local writes (not yet confirmed by server).
  /// Set from `doc.metadata.hasPendingWrites` in `fromFirestore`.
  /// Never persisted to Firestore — it's a client-only field.
  final bool isPending;

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
    this.replyToMessageId,
    this.replyToMessage,
    this.isPending = false,
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
      replyToMessageId: data['replyToMessageId'],
      replyToMessage: null, // Will be populated separately if needed
      isPending: doc.metadata.hasPendingWrites,
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
      'replyToMessageId': replyToMessageId,
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

  /// Check if this message is a reply to another message
  bool get isReply => replyToMessageId != null;

  /// Get a copy of this message with updated reply information
  CommunityChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? receiverId,
    String? text,
    Timestamp? timestamp,
    String? status,
    String? type,
    bool? isCommunity,
    AttachmentData? attachment,
    String? replyToMessageId,
    CommunityChatMessage? replyToMessage,
    bool? isPending,
  }) {
    return CommunityChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      isCommunity: isCommunity ?? this.isCommunity,
      attachment: attachment ?? this.attachment,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      isPending: isPending ?? this.isPending,
    );
  }
}
