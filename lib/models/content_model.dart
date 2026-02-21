import '../utils/logger.dart';

class ContentModel {
  final String id;
  final String title;
  final String contentType; // 'text', 'video', 'pdf', etc.
  final String content;
  final int order;
  final String moduleId;
  final bool? isPublished; // Content-level publishing control
  
  // HLS-specific fields for video content
  final String? hlsUrl;           // HLS master playlist URL (.m3u8)
  final String? originalUrl;      // Backup original MP4 URL
  final String? processingStatus; // 'pending', 'processing', 'completed', 'failed'
  final double? duration;         // Video duration in seconds

  final DateTime? createdAt;      // When this item was created in Firestore

  ContentModel({
    required this.id,
    required this.title,
    required this.contentType,
    required this.content,
    required this.order,
    this.moduleId = '',
    this.isPublished,
    this.hlsUrl,
    this.originalUrl,
    this.processingStatus,
    this.duration,
    this.createdAt,
  });

  factory ContentModel.fromJson(Map<String, dynamic> json, String id) {
    // Debug logging
    Logger.d("ContentModel.fromJson input - id: $id, data: $json");

    // Handle content field with multiple possible names
    String contentValue =
        json['content'] ??
        json['url'] ??
        json['fileUrl'] ??
        json['videoUrl'] ??
        json['text'] ??
        '';

    // Determine content type
    String contentTypeValue;
    if (json.containsKey('type')) {
      contentTypeValue = json['type'];
    } else if (json.containsKey('contentType')) {
      contentTypeValue = json['contentType'];
    } else {
      // Infer type from content URL if possible
      final lowerContent = contentValue.toLowerCase();
      if (lowerContent.contains('.mp4') ||
          lowerContent.contains('youtube.com') ||
          lowerContent.contains('youtu.be')) {
        contentTypeValue = 'video';
      } else if (lowerContent.contains('.pdf')) {
        contentTypeValue = 'pdf';
      } else if (lowerContent.contains('.ppt') ||
                 lowerContent.contains('.pptx') ||
                 lowerContent.contains('powerpoint')) {
        contentTypeValue = 'ppt';
      } else if (lowerContent.contains('.jpg') ||
                 lowerContent.contains('.jpeg') ||
                 lowerContent.contains('.png') ||
                 lowerContent.contains('.gif') ||
                 lowerContent.contains('.webp') ||
                 lowerContent.contains('.bmp') ||
                 lowerContent.contains('image')) {
        contentTypeValue = 'image';
      } else if (lowerContent.startsWith('http')) {
        contentTypeValue = 'link';
      } else {
        contentTypeValue = 'text';
      }
    }

    // Handle order field with multiple possible names
    int orderValue = 0;
    if (json.containsKey('order')) {
      orderValue =
          json['order'] is int
              ? json['order']
              : int.tryParse(json['order'].toString()) ?? 0;
    } else if (json.containsKey('position')) {
      orderValue =
          json['position'] is int
              ? json['position']
              : int.tryParse(json['position'].toString()) ?? 0;
    } else if (json.containsKey('index')) {
      orderValue =
          json['index'] is int
              ? json['index']
              : int.tryParse(json['index'].toString()) ?? 0;
    }

    // Get title with fallback
    String titleValue =
        json['title'] ??
        json['name'] ??
        'Untitled ${contentTypeValue.toUpperCase()}';

    // Get moduleId if available
    String moduleIdValue = json['moduleId'] ?? '';

    // Parse isPublished field (null if not present for backwards compatibility)
    bool? isPublishedValue = json['isPublished'] as bool?;

    // Parse createdAt — Firestore Timestamp, DateTime, or ISO string
    DateTime? createdAtValue;
    final rawCreatedAt = json['createdAt'];
    if (rawCreatedAt != null) {
      try {
        createdAtValue = (rawCreatedAt as dynamic).toDate() as DateTime;
      } catch (_) {
        if (rawCreatedAt is String) {
          createdAtValue = DateTime.tryParse(rawCreatedAt);
        } else if (rawCreatedAt is DateTime) {
          createdAtValue = rawCreatedAt;
        }
      }
    }

    // Parse HLS-specific fields for video content
    String? hlsUrlValue;
    String? originalUrlValue;
    String? processingStatusValue;
    double? durationValue;

    if (contentTypeValue == 'video') {
      hlsUrlValue = json['hlsUrl'];
      originalUrlValue = json['originalUrl'];
      processingStatusValue = json['processingStatus'];
      
      // Parse duration from various possible formats
      if (json['duration'] != null) {
        if (json['duration'] is num) {
          durationValue = json['duration'].toDouble();
        } else if (json['duration'] is String) {
          durationValue = double.tryParse(json['duration']);
        }
      }
      
      Logger.d(
        "HLS fields - hlsUrl: $hlsUrlValue, status: $processingStatusValue, duration: $durationValue",
      );
    }

    Logger.d(
      "ContentModel.fromJson output - title: $titleValue, type: $contentTypeValue, content: $contentValue",
    );

    return ContentModel(
      id: id,
      title: titleValue,
      contentType: contentTypeValue,
      content: contentValue,
      order: orderValue,
      moduleId: moduleIdValue,
      isPublished: isPublishedValue,
      hlsUrl: hlsUrlValue,
      originalUrl: originalUrlValue,
      processingStatus: processingStatusValue,
      duration: durationValue,
      createdAt: createdAtValue,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'title': title,
      'contentType': contentType,
      'content': content,
      'order': order,
      'moduleId': moduleId,
    };
    
    // Add isPublished if present
    if (isPublished != null) json['isPublished'] = isPublished;
    
    // Add HLS fields if they exist (only for video content)
    if (contentType == 'video') {
      if (hlsUrl != null) json['hlsUrl'] = hlsUrl;
      if (originalUrl != null) json['originalUrl'] = originalUrl;
      if (processingStatus != null) json['processingStatus'] = processingStatus;
      if (duration != null) json['duration'] = duration;
    }
    
    return json;
  }
}
