import 'package:cloud_firestore/cloud_firestore.dart';

class ModuleModel {
  final String id;
  final String title;
  final String description;
  final int order;
  final bool isPublished;
  final String courseId;
  /// Timestamp of the last content update in this module.
  /// Used to show an "Updated" badge when a module was completed
  /// before the content was updated.
  final DateTime? contentUpdatedAt;

  ModuleModel({
    required this.id,
    required this.title,
    required this.description,
    required this.order,
    this.isPublished = true,
    required this.courseId,
    this.contentUpdatedAt,
  });

  factory ModuleModel.fromJson(Map<String, dynamic> json, String id) {
    // Parse contentUpdatedAt from Timestamp, int (millis from cache), or null
    DateTime? contentUpdatedAt;
    final raw = json['contentUpdatedAt'];
    if (raw is Timestamp) {
      contentUpdatedAt = raw.toDate();
    } else if (raw is int) {
      contentUpdatedAt = DateTime.fromMillisecondsSinceEpoch(raw);
    }

    return ModuleModel(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      order: json['order'] ?? 0,
      isPublished: json['isPublished'] ?? true,
      courseId: json['courseId'] ?? '',
      contentUpdatedAt: contentUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'order': order,
      'isPublished': isPublished,
      'courseId': courseId,
      if (contentUpdatedAt != null)
        'contentUpdatedAt': contentUpdatedAt!.millisecondsSinceEpoch,
    };
  }
} 