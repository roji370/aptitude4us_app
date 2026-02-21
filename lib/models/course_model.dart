class CourseModel {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final bool isPublished;
  final bool isPinned;

  CourseModel({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    this.isPublished = true,
    this.isPinned = false,
  });

  factory CourseModel.fromJson(Map<String, dynamic> json, String id) {
    // Handle multiple possible field names for published status
    bool publishedStatus = true; // Default to true for backward compatibility
    
    // Check common field names used by admin apps
    if (json.containsKey('isPublished')) {
      publishedStatus = json['isPublished'] ?? true;
    } else if (json.containsKey('published')) {
      publishedStatus = json['published'] ?? true;
    } else if (json.containsKey('status')) {
      // Handle status field (published/draft/active/inactive)
      final status = json['status']?.toString().toLowerCase() ?? 'published';
      publishedStatus = status == 'published' || status == 'active';
    } else if (json.containsKey('isDraft')) {
      // Handle isDraft field (opposite of isPublished)
      publishedStatus = !(json['isDraft'] ?? false);
    }
    
    return CourseModel(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      isPublished: publishedStatus,
      isPinned: json['isPinned'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'isPublished': isPublished,
      'isPinned': isPinned,
    };
  }
} 