import '../utils/logger.dart';

class ContentModel {
  final String id;
  final String title;
  final String contentType; // 'text', 'video', 'pdf', etc.
  final String content;
  final int order;
  final String moduleId;

  ContentModel({
    required this.id,
    required this.title,
    required this.contentType,
    required this.content,
    required this.order,
    this.moduleId = '',
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
      if (contentValue.toLowerCase().contains('.mp4') ||
          contentValue.toLowerCase().contains('youtube.com') ||
          contentValue.toLowerCase().contains('youtu.be')) {
        contentTypeValue = 'video';
      } else if (contentValue.toLowerCase().contains('.pdf')) {
        contentTypeValue = 'pdf';
      } else if (contentValue.toLowerCase().startsWith('http')) {
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'contentType': contentType,
      'content': content,
      'order': order,
      'moduleId': moduleId,
    };
  }
}
