class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String role;
  final List<String> assignedCourseIds;
  final String? password;
  
  // Profile completion fields
  final String? photoUrl;
  final DateTime? dateOfJoining;
  final DateTime? examDate;
  final String? mobile;
  final String? subscriptionPeriod;
  final bool profileCompleted;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.assignedCourseIds,
    this.password,
    this.photoUrl,
    this.dateOfJoining,
    this.examDate,
    this.mobile,
    this.subscriptionPeriod,
    this.profileCompleted = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String uid) {
    // Parse dates from Firestore timestamps or strings
    DateTime? parseDateOfJoining;
    DateTime? parseExamDate;
    
    if (json['dateOfJoining'] != null) {
      if (json['dateOfJoining'] is int) {
        parseDateOfJoining = DateTime.fromMillisecondsSinceEpoch(json['dateOfJoining']);
      } else if (json['dateOfJoining'] is String) {
        parseDateOfJoining = DateTime.tryParse(json['dateOfJoining']);
      }
    }
    
    if (json['examDate'] != null) {
      if (json['examDate'] is int) {
        parseExamDate = DateTime.fromMillisecondsSinceEpoch(json['examDate']);
      } else if (json['examDate'] is String) {
        parseExamDate = DateTime.tryParse(json['examDate']);
      }
    }
    
    return UserModel(
      uid: uid,
      displayName: json['displayName'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'student',
      assignedCourseIds: List<String>.from(json['assignedCourseIds'] ?? []),
      password: json['password'],
      photoUrl: json['photoUrl'],
      dateOfJoining: parseDateOfJoining,
      examDate: parseExamDate,
      mobile: json['mobile'],
      subscriptionPeriod: json['subscriptionPeriod'],
      profileCompleted: json['profileCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'role': role,
      'assignedCourseIds': assignedCourseIds,
      'password': password,
      'photoUrl': photoUrl,
      'dateOfJoining': dateOfJoining?.millisecondsSinceEpoch,
      'examDate': examDate?.millisecondsSinceEpoch,
      'mobile': mobile,
      'subscriptionPeriod': subscriptionPeriod,
      'profileCompleted': profileCompleted,
    };
  }
  
  /// Check if all required profile fields are filled
  bool get isProfileComplete {
    return photoUrl != null &&
        photoUrl!.isNotEmpty &&
        dateOfJoining != null &&
        examDate != null &&
        mobile != null &&
        mobile!.isNotEmpty &&
        subscriptionPeriod != null &&
        subscriptionPeriod!.isNotEmpty;
  }
  
  /// Create a copy of UserModel with updated fields
  UserModel copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? role,
    List<String>? assignedCourseIds,
    String? password,
    String? photoUrl,
    DateTime? dateOfJoining,
    DateTime? examDate,
    String? mobile,
    String? subscriptionPeriod,
    bool? profileCompleted,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      role: role ?? this.role,
      assignedCourseIds: assignedCourseIds ?? this.assignedCourseIds,
      password: password ?? this.password,
      photoUrl: photoUrl ?? this.photoUrl,
      dateOfJoining: dateOfJoining ?? this.dateOfJoining,
      examDate: examDate ?? this.examDate,
      mobile: mobile ?? this.mobile,
      subscriptionPeriod: subscriptionPeriod ?? this.subscriptionPeriod,
      profileCompleted: profileCompleted ?? this.profileCompleted,
    );
  }
}
